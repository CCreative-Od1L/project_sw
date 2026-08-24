import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/aad_builder.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/vault/data/vault_entry_json_codec.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';

/// Resolves the application-support location where the vault file is stored.
typedef VaultPathResolver = Future<String> Function();

/// Coordinates KDF, MVK wrapping, and the empty-vault file commit.
final class EncryptedVaultRepository
    implements
        VaultRepository,
        BiometricVaultRepository,
        MasterPasswordVerifier,
        MasterPasswordChangeRepository,
        MasterPasswordRecoveryRepository,
        MigrationVaultPort {
  /// Creates a repository with a production or test [vaultPathResolver].
  EncryptedVaultRepository({
    required this.crypto,
    required this.vaultFileEngine,
    required this.vaultPathResolver,
    this.biometricKeyStore,
  });

  /// Crypto primitives used to create and wrap the initial keys.
  final CryptoService crypto;

  /// The block-level single-file storage engine.
  final VaultFileEngine vaultFileEngine;

  /// Resolves the application-support vault path.
  final VaultPathResolver vaultPathResolver;

  /// Platform adapter that gates transient K_bio release with biometrics.
  final BiometricKeyStore? biometricKeyStore;
  Uint8List? _masterVaultKey;
  List<EntrySummary> _entrySummaries = const <EntrySummary>[];
  Argon2idParameters? _activeKdfParameters;
  Object? _activeUnlockOperation;
  var _hasBiometricUnlock = false;

  @override
  bool get hasUnlockedSession => _masterVaultKey != null;

  @override
  List<EntrySummary> get entrySummaries =>
      List<EntrySummary>.unmodifiable(_entrySummaries);

  @override
  Argon2idParameters? get activeKdfParameters => _activeKdfParameters;

  @override
  bool get hasBiometricUnlock => _hasBiometricUnlock;

  @override
  Future<bool> hasConfiguredBiometricUnlock() async {
    VaultFileHeader? header;
    try {
      final String path = await vaultPathResolver();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      _hasBiometricUnlock = header.biometricWrappedMasterVaultKey != null;
      return _hasBiometricUnlock;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
    }
  }

  @override
  Future<void> enableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) {
      throw const VaultLockedException();
    }
    final BiometricKeyStore store = _requireBiometricKeyStore();
    Uint8List? biometricKey;
    Uint8List? aad;
    Uint8List? wrappedMvk;
    AeadCiphertext? encrypted;
    VaultFileHeader? previousHeader;
    VaultFileHeader? disabledHeader;
    VaultFileHeader? currentHeader;
    VaultFileHeader? enabledHeader;
    var createdKey = false;
    var committedKey = false;
    try {
      if (await store.availability != BiometricAvailability.available) {
        throw const BiometricUnavailableException();
      }
      activityGuard.ensureActive();
      final String previousPath = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile previous = vaultFileEngine.openVaultFile(
        previousPath,
      );
      previousHeader = previous.header;
      _hasBiometricUnlock =
          previousHeader.biometricWrappedMasterVaultKey != null;
      if (_hasBiometricUnlock) {
        disabledHeader = previousHeader.copyWithBiometric(null);
        activityGuard.ensureActive();
        vaultFileEngine.commitHeaderUpdate(
          path: previousPath,
          opened: previous,
          header: disabledHeader,
        );
        _hasBiometricUnlock = false;
        await store.deleteKey();
        activityGuard.ensureActive();
      }
      biometricKey = await store.createAndStoreKey();
      createdKey = true;
      activityGuard.ensureActive();
      _validateBiometricKey(biometricKey);
      aad = AadBuilder.forWrapBiometricMvk(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: 1,
      );
      encrypted = crypto.encryptWithAead(biometricKey, masterVaultKey, aad);
      wrappedMvk = _join(encrypted.nonce, encrypted.ciphertext);
      if (wrappedMvk.length != 72) {
        throw const CryptoInitializationException();
      }
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      currentHeader = opened.header;
      enabledHeader = currentHeader.copyWithBiometric(wrappedMvk);
      activityGuard.ensureActive();
      // From this point a thrown backup refresh can still mean that the
      // primary header was durably replaced. Preserve the matching key.
      committedKey = true;
      vaultFileEngine.commitHeaderUpdate(
        path: path,
        opened: opened,
        header: enabledHeader,
      );
      _hasBiometricUnlock = true;
      activityGuard.ensureActive();
    } on SessionActivityInterrupted {
      rethrow;
    } on BiometricKeyStoreException {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (createdKey && !committedKey) {
        try {
          await store.deleteKey();
        } on Object {
          // The vault header remains disabled; orphan cleanup is best-effort.
        }
      }
      for (final VaultFileHeader? header in <VaultFileHeader?>[
        previousHeader,
        disabledHeader,
        currentHeader,
        enabledHeader,
      ]) {
        if (header != null) {
          _clearHeaderKeyMaterial(header);
        }
      }
      if (encrypted != null) {
        clearSensitiveBytes(encrypted.nonce);
        clearSensitiveBytes(encrypted.ciphertext);
      }
      if (wrappedMvk != null) {
        clearSensitiveBytes(wrappedMvk);
      }
      if (aad != null) {
        clearSensitiveBytes(aad);
      }
      if (biometricKey != null) {
        clearSensitiveBytes(biometricKey);
      }
    }
  }

  @override
  Future<void> disableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    if (_masterVaultKey == null) {
      throw const VaultLockedException();
    }
    final BiometricKeyStore store = _requireBiometricKeyStore();
    VaultFileHeader? header;
    VaultFileHeader? nextHeader;
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      if (header.biometricWrappedMasterVaultKey != null) {
        nextHeader = header.copyWithBiometric(null);
        activityGuard.ensureActive();
        vaultFileEngine.commitHeaderUpdate(
          path: path,
          opened: opened,
          header: nextHeader,
        );
      }
      _hasBiometricUnlock = false;
      await store.deleteKey();
      activityGuard.ensureActive();
    } on SessionActivityInterrupted {
      rethrow;
    } on BiometricKeyStoreException {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
      if (nextHeader != null) {
        _clearHeaderKeyMaterial(nextHeader);
      }
    }
  }

  @override
  Future<void> unlockWithBiometric({
    required SessionActivityGuard activityGuard,
  }) async {
    final Object operation = _beginUnlockOperation(activityGuard);
    late final BiometricKeyStore store;
    Uint8List? biometricKey;
    Uint8List? aad;
    Uint8List? nonce;
    Uint8List? ciphertext;
    VaultFileHeader? header;
    var committed = false;
    try {
      store = _requireBiometricKeyStore();
      final String path = await vaultPathResolver();
      _ensureUnlockOperationActive(activityGuard, operation);
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      final Uint8List? wrappedMvk = header.biometricWrappedMasterVaultKey;
      if (wrappedMvk == null) {
        throw const BiometricUnavailableException();
      }
      biometricKey = await store.loadKey();
      _ensureUnlockOperationActive(activityGuard, operation);
      _validateBiometricKey(biometricKey);
      aad = AadBuilder.forWrapBiometricMvk(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: header.aeadAlgorithmId,
      );
      nonce = Uint8List.fromList(wrappedMvk.sublist(0, 24));
      ciphertext = Uint8List.fromList(wrappedMvk.sublist(24));
      try {
        _masterVaultKey = crypto.decryptWithAead(
          biometricKey,
          nonce,
          ciphertext,
          aad,
        );
      } on Object catch (error) {
        throw VaultCorruptedException(cause: error);
      }
      _ensureUnlockOperationActive(activityGuard, operation);
      try {
        _entrySummaries = _loadEntrySummaries(
          path: path,
          header: header,
          directory: opened.directory,
          masterVaultKey: _masterVaultKey!,
        );
        _activeKdfParameters = Argon2idParameters(
          memoryKiB: header.kdfParameters.memoryKiB,
          iterations: header.kdfParameters.iterations,
          parallelism: header.kdfParameters.parallelism,
        );
        _hasBiometricUnlock = true;
        _ensureUnlockOperationActive(activityGuard, operation);
        committed = true;
      } on VaultException {
        clearUnlockedSession();
        rethrow;
      } on Object catch (error) {
        clearUnlockedSession();
        throw VaultCorruptedException(cause: error);
      }
    } on SessionUnlockInterrupted {
      rethrow;
    } on SessionActivityInterrupted {
      rethrow;
    } on BiometricKeyStoreException {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (!committed) {
        _clearUnlockSessionIfOwned(operation);
      }
      _finishUnlockOperation(operation);
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
      if (ciphertext != null) {
        clearSensitiveBytes(ciphertext);
      }
      if (nonce != null) {
        clearSensitiveBytes(nonce);
      }
      if (aad != null) {
        clearSensitiveBytes(aad);
      }
      if (biometricKey != null) {
        clearSensitiveBytes(biometricKey);
      }
    }
  }

  @override
  Future<void> createEmptyVault({
    required String masterPassword,
    required Argon2idParameters kdfParameters,
  }) async {
    Uint8List? salt;
    Uint8List? kek;
    Uint8List? mvk;
    Uint8List? aad;
    try {
      salt = crypto.randomBytes(16);
      kek = await crypto.deriveKek(
        masterPassword,
        salt,
        memoryKiB: kdfParameters.memoryKiB,
        iterations: kdfParameters.iterations,
        parallelism: kdfParameters.parallelism,
      );
      mvk = crypto.generateKey();
      final Uint8List kdfBytes = _encodeKdfParameters(kdfParameters);
      try {
        aad = AadBuilder.forWrapMvk(
          magic: vaultMagic,
          formatVersion: vaultFormatVersion,
          kdfAlgorithmId: 1,
          kdfParameters: kdfBytes,
          kdfSalt: salt,
        );
      } finally {
        clearSensitiveBytes(kdfBytes);
      }
      final AeadCiphertext wrapped = crypto.encryptWithAead(kek, mvk, aad);
      final Uint8List wrappedMvk =
          Uint8List(wrapped.nonce.length + wrapped.ciphertext.length)
            ..setRange(0, wrapped.nonce.length, wrapped.nonce)
            ..setRange(
              wrapped.nonce.length,
              wrapped.nonce.length + wrapped.ciphertext.length,
              wrapped.ciphertext,
            );
      try {
        if (wrappedMvk.length != 72) {
          throw const CryptoInitializationException();
        }
        const VaultJournal journal = VaultJournal(
          operation: VaultJournalOperation.create,
          sequence: 1,
          directoryOffset: vaultFileHeaderLength,
          directoryLength: vaultDirectoryLength,
        );
        final VaultFileHeader header = VaultFileHeader(
          kdfParameters: VaultKdfParameters(
            memoryKiB: kdfParameters.memoryKiB,
            iterations: kdfParameters.iterations,
            parallelism: kdfParameters.parallelism,
          ),
          kdfSalt: salt,
          wrappedMasterVaultKey: wrappedMvk,
          activeDirectoryOffset: vaultFileHeaderLength,
          entryCount: 0,
          freeListHead: 0,
          sequenceCounter: 1,
          committedSequence: 0,
          journal: journal,
        );
        final String path = await vaultPathResolver();
        vaultFileEngine.createEmptyVault(path, header);
      } finally {
        clearSensitiveBytes(wrapped.nonce);
        clearSensitiveBytes(wrapped.ciphertext);
        clearSensitiveBytes(wrappedMvk);
      }
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (aad != null) {
        clearSensitiveBytes(aad);
      }
      if (mvk != null) {
        clearSensitiveBytes(mvk);
      }
      if (kek != null) {
        clearSensitiveBytes(kek);
      }
      if (salt != null) {
        clearSensitiveBytes(salt);
      }
    }
  }

  @override
  Future<List<MigrationEntryPayload>> exportMigrationEntries({
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) {
      throw const VaultLockedException();
    }
    final List<MigrationEntryPayload> exported = <MigrationEntryPayload>[];
    VaultFileHeader? header;
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      for (final VaultEntryRecord record in opened.directory.records) {
        exported.add(
          _exportMigrationEntry(
            path: path,
            header: header,
            record: record,
            masterVaultKey: masterVaultKey,
          ),
        );
      }
      activityGuard.ensureActive();
      return List<MigrationEntryPayload>.unmodifiable(exported);
    } on SessionActivityInterrupted {
      for (final MigrationEntryPayload payload in exported) {
        payload.dispose();
      }
      rethrow;
    } on VaultException {
      for (final MigrationEntryPayload payload in exported) {
        payload.dispose();
      }
      rethrow;
    } on FileSystemException catch (error) {
      for (final MigrationEntryPayload payload in exported) {
        payload.dispose();
      }
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      for (final MigrationEntryPayload payload in exported) {
        payload.dispose();
      }
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      for (final MigrationEntryPayload payload in exported) {
        payload.dispose();
      }
      throw VaultCorruptedException(cause: error);
    } finally {
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
    }
  }

  @override
  Future<void> importMigrationEntries(
    List<MigrationEntryPayload> entries, {
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) {
      throw const VaultLockedException();
    }
    if (entries.isEmpty) {
      return;
    }
    VaultFileHeader? header;
    final List<VaultMigrationEntry> buffered = <VaultMigrationEntry>[];
    final List<EntrySummary> projected = <EntrySummary>[..._entrySummaries];
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      for (final MigrationEntryPayload payload in entries) {
        final VaultEntry incoming = _decryptMigrationEntry(
          header: header,
          payload: payload,
        );
        final int existingIndex = projected.indexWhere(
          (EntrySummary summary) =>
              _sameBytes(summary.entryId, incoming.entryId),
        );
        if (existingIndex >= 0 &&
            !incoming.updatedAt.isAfter(projected[existingIndex].updatedAt)) {
          continue;
        }

        Uint8List? wrapAad;
        Uint8List? wrappedDek;
        Uint8List? block;
        AeadCiphertext? wrappedCiphertext;
        try {
          wrapAad = AadBuilder.forWrapDek(
            magic: vaultMagic,
            formatVersion: vaultFormatVersion,
            aeadAlgorithmId: header.aeadAlgorithmId,
            entryId: payload.entryId,
          );
          wrappedCiphertext = crypto.encryptWithAead(
            masterVaultKey,
            payload.dek,
            wrapAad,
          );
          wrappedDek = _join(
            wrappedCiphertext.nonce,
            wrappedCiphertext.ciphertext,
          );
          block = _join(wrappedDek, payload.entryCiphertext);
          final VaultMigrationEntry next = VaultMigrationEntry(
            entryId: payload.entryId,
            block: block,
            plaintextFormatId: payload.plaintextFormatId,
            sequence: payload.sequence,
          );
          final int bufferedIndex = buffered.indexWhere(
            (VaultMigrationEntry current) =>
                _sameBytes(current.entryId, payload.entryId),
          );
          if (bufferedIndex >= 0) {
            buffered[bufferedIndex].dispose();
            buffered[bufferedIndex] = next;
          } else {
            buffered.add(next);
          }
          final EntrySummary summary = incoming.toSummary();
          if (existingIndex >= 0) {
            projected[existingIndex] = summary;
          } else {
            projected.add(summary);
          }
        } finally {
          if (block != null) {
            clearSensitiveBytes(block);
          }
          if (wrappedDek != null) {
            clearSensitiveBytes(wrappedDek);
          }
          if (wrapAad != null) {
            clearSensitiveBytes(wrapAad);
          }
          if (wrappedCiphertext != null) {
            clearSensitiveBytes(wrappedCiphertext.nonce);
            clearSensitiveBytes(wrappedCiphertext.ciphertext);
          }
        }
      }
      if (buffered.isNotEmpty) {
        activityGuard.ensureActive();
        vaultFileEngine.commitMigration(
          path: path,
          opened: opened,
          entries: buffered,
        );
        activityGuard.ensureActive();
        _entrySummaries = List<EntrySummary>.unmodifiable(projected);
      }
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultCorruptedException(cause: error);
    } finally {
      for (final VaultMigrationEntry entry in buffered) {
        entry.dispose();
      }
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
    }
  }

  @override
  Future<void> unlockWithMasterPassword(
    String masterPassword, {
    required SessionActivityGuard activityGuard,
  }) async {
    final Object operation = _beginUnlockOperation(activityGuard);
    Uint8List? kek;
    Uint8List? aad;
    Uint8List? nonce;
    Uint8List? ciphertext;
    VaultFileHeader? header;
    var committed = false;
    try {
      final String path = await vaultPathResolver();
      _ensureUnlockOperationActive(activityGuard, operation);
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      _hasBiometricUnlock = header.biometricWrappedMasterVaultKey != null;
      kek = await crypto.deriveKek(
        masterPassword,
        header.kdfSalt,
        memoryKiB: header.kdfParameters.memoryKiB,
        iterations: header.kdfParameters.iterations,
        parallelism: header.kdfParameters.parallelism,
      );
      _ensureUnlockOperationActive(activityGuard, operation);
      final Uint8List kdfBytes = _encodeVaultKdfParameters(
        header.kdfParameters,
      );
      try {
        aad = AadBuilder.forWrapMvk(
          magic: vaultMagic,
          formatVersion: vaultFormatVersion,
          kdfAlgorithmId: header.kdfAlgorithmId,
          kdfParameters: kdfBytes,
          kdfSalt: header.kdfSalt,
        );
      } finally {
        clearSensitiveBytes(kdfBytes);
      }
      nonce = Uint8List.fromList(header.wrappedMasterVaultKey.sublist(0, 24));
      ciphertext = Uint8List.fromList(header.wrappedMasterVaultKey.sublist(24));
      try {
        _masterVaultKey = crypto.decryptWithAead(kek, nonce, ciphertext, aad);
      } on VaultException {
        rethrow;
      } on Object {
        throw const InvalidMasterPasswordException();
      }
      _ensureUnlockOperationActive(activityGuard, operation);
      try {
        _entrySummaries = _loadEntrySummaries(
          path: path,
          header: header,
          directory: opened.directory,
          masterVaultKey: _masterVaultKey!,
        );
        _activeKdfParameters = Argon2idParameters(
          memoryKiB: header.kdfParameters.memoryKiB,
          iterations: header.kdfParameters.iterations,
          parallelism: header.kdfParameters.parallelism,
        );
        _ensureUnlockOperationActive(activityGuard, operation);
        committed = true;
      } on VaultException {
        clearUnlockedSession();
        rethrow;
      } on Object catch (error) {
        clearUnlockedSession();
        throw VaultCorruptedException(cause: error);
      }
    } on SessionUnlockInterrupted {
      rethrow;
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (!committed) {
        _clearUnlockSessionIfOwned(operation);
      }
      _finishUnlockOperation(operation);
      if (ciphertext != null) {
        clearSensitiveBytes(ciphertext);
      }
      if (nonce != null) {
        clearSensitiveBytes(nonce);
      }
      if (aad != null) {
        clearSensitiveBytes(aad);
      }
      if (kek != null) {
        clearSensitiveBytes(kek);
      }
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
    }
  }

  /// Verifies the master password while preserving the current unlocked data.
  @override
  Future<void> verifyMasterPassword(String masterPassword) =>
      _verifyMasterPassword(masterPassword);

  Future<void> _verifyMasterPassword(
    String masterPassword, {
    SessionActivityGuard? activityGuard,
  }) async {
    activityGuard?.ensureActive();
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) {
      throw const VaultLockedException();
    }
    Uint8List? kek;
    Uint8List? aad;
    Uint8List? nonce;
    Uint8List? ciphertext;
    Uint8List? verifiedMasterVaultKey;
    VaultFileHeader? header;
    try {
      final String path = await vaultPathResolver();
      activityGuard?.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      kek = await crypto.deriveKek(
        masterPassword,
        header.kdfSalt,
        memoryKiB: header.kdfParameters.memoryKiB,
        iterations: header.kdfParameters.iterations,
        parallelism: header.kdfParameters.parallelism,
      );
      activityGuard?.ensureActive();
      final Uint8List kdfBytes = _encodeVaultKdfParameters(
        header.kdfParameters,
      );
      try {
        aad = AadBuilder.forWrapMvk(
          magic: vaultMagic,
          formatVersion: vaultFormatVersion,
          kdfAlgorithmId: header.kdfAlgorithmId,
          kdfParameters: kdfBytes,
          kdfSalt: header.kdfSalt,
        );
      } finally {
        clearSensitiveBytes(kdfBytes);
      }
      nonce = Uint8List.fromList(header.wrappedMasterVaultKey.sublist(0, 24));
      ciphertext = Uint8List.fromList(header.wrappedMasterVaultKey.sublist(24));
      try {
        verifiedMasterVaultKey = crypto.decryptWithAead(
          kek,
          nonce,
          ciphertext,
          aad,
        );
      } on VaultException {
        rethrow;
      } on Object {
        throw const InvalidMasterPasswordException();
      }
      activityGuard?.ensureActive();
      if (!_sameBytes(verifiedMasterVaultKey, masterVaultKey)) {
        throw const VaultCorruptedException();
      }
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (verifiedMasterVaultKey != null) {
        clearSensitiveBytes(verifiedMasterVaultKey);
      }
      if (ciphertext != null) {
        clearSensitiveBytes(ciphertext);
      }
      if (nonce != null) {
        clearSensitiveBytes(nonce);
      }
      if (aad != null) {
        clearSensitiveBytes(aad);
      }
      if (kek != null) {
        clearSensitiveBytes(kek);
      }
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
    }
  }

  /// Atomically re-wraps the unchanged MVK under a fresh salt and new KEK.
  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    await _verifyMasterPassword(
      currentMasterPassword,
      activityGuard: activityGuard,
    );
    activityGuard.ensureActive();
    await _rewrapMasterVaultKey(
      newMasterPassword: newMasterPassword,
      activityGuard: activityGuard,
    );
    activityGuard.ensureActive();
  }

  /// Re-wraps the unlocked MVK after the domain recovery gates have passed.
  @override
  Future<void> recoverMasterPassword({
    required String newMasterPassword,
    required SessionActivityLease activityLease,
  }) => _rewrapMasterVaultKey(
    newMasterPassword: newMasterPassword,
    activityGuard: activityLease,
  );

  Future<void> _rewrapMasterVaultKey({
    required String newMasterPassword,
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) {
      throw const VaultLockedException();
    }
    Uint8List? newSalt;
    Uint8List? newKek;
    Uint8List? newAad;
    Uint8List? newWrappedMasterVaultKey;
    AeadCiphertext? newWrappedCiphertext;
    VaultFileHeader? header;
    VaultFileHeader? nextHeader;
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      newSalt = crypto.randomBytes(16);
      if (newSalt.length != 16) {
        throw const CryptoInitializationException();
      }
      newKek = await crypto.deriveKek(
        newMasterPassword,
        newSalt,
        memoryKiB: header.kdfParameters.memoryKiB,
        iterations: header.kdfParameters.iterations,
        parallelism: header.kdfParameters.parallelism,
      );
      activityGuard.ensureActive();
      final Uint8List newKdfBytes = _encodeVaultKdfParameters(
        header.kdfParameters,
      );
      try {
        newAad = AadBuilder.forWrapMvk(
          magic: vaultMagic,
          formatVersion: vaultFormatVersion,
          kdfAlgorithmId: header.kdfAlgorithmId,
          kdfParameters: newKdfBytes,
          kdfSalt: newSalt,
        );
      } finally {
        clearSensitiveBytes(newKdfBytes);
      }
      newWrappedCiphertext = crypto.encryptWithAead(
        newKek,
        masterVaultKey,
        newAad,
      );
      newWrappedMasterVaultKey = _join(
        newWrappedCiphertext.nonce,
        newWrappedCiphertext.ciphertext,
      );
      if (newWrappedMasterVaultKey.length != 72) {
        throw const CryptoInitializationException();
      }
      nextHeader = header.copyWithMasterPassword(
        kdfSalt: newSalt,
        wrappedMasterVaultKey: newWrappedMasterVaultKey,
      );
      activityGuard.ensureActive();
      vaultFileEngine.commitHeaderUpdate(
        path: path,
        opened: opened,
        header: nextHeader,
      );
      activityGuard.ensureActive();
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      for (final Uint8List? bytes in <Uint8List?>[
        newWrappedMasterVaultKey,
        newAad,
        newKek,
        newSalt,
      ]) {
        if (bytes != null) {
          clearSensitiveBytes(bytes);
        }
      }
      if (newWrappedCiphertext != null) {
        clearSensitiveBytes(newWrappedCiphertext.nonce);
        clearSensitiveBytes(newWrappedCiphertext.ciphertext);
      }
      if (nextHeader != null) {
        _clearHeaderKeyMaterial(nextHeader);
      }
      if (header != null) {
        _clearHeaderKeyMaterial(header);
      }
    }
  }

  @override
  Future<EntrySummary> addEntry(
    NewVaultEntry entry, {
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    if (entry.name.trim().isEmpty) {
      throw const InvalidArgumentException('An entry name is required.');
    }
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) {
      throw const VaultLockedException();
    }
    Uint8List? entryId;
    Uint8List? dek;
    Uint8List? wrapAad;
    Uint8List? entryAad;
    Uint8List? plaintext;
    Uint8List? wrappedDek;
    Uint8List? entryCiphertext;
    Uint8List? block;
    AeadCiphertext? wrappedCiphertext;
    AeadCiphertext? encryptedEntry;
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      entryId = crypto.randomBytes(16);
      final DateTime now = DateTime.now().toUtc();
      final VaultEntry completeEntry = VaultEntry(
        entryId: entryId,
        name: entry.name,
        url: entry.url,
        username: entry.username,
        password: entry.password,
        notes: entry.notes,
        createdAt: now,
        updatedAt: now,
        favorite: entry.favorite,
        customFields: entry.customFields,
      );
      plaintext = VaultEntryJsonCodec.encode(completeEntry);
      dek = crypto.generateKey();
      wrapAad = AadBuilder.forWrapDek(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: opened.header.aeadAlgorithmId,
        entryId: entryId,
      );
      wrappedCiphertext = crypto.encryptWithAead(masterVaultKey, dek, wrapAad);
      wrappedDek = _join(wrappedCiphertext.nonce, wrappedCiphertext.ciphertext);
      if (wrappedDek.length != 72) {
        throw const CryptoInitializationException();
      }
      entryAad = AadBuilder.forEncryptEntry(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: opened.header.aeadAlgorithmId,
        entryId: entryId,
        sequence: opened.header.sequenceCounter,
      );
      encryptedEntry = crypto.encryptWithAead(dek, plaintext, entryAad);
      entryCiphertext = _join(encryptedEntry.nonce, encryptedEntry.ciphertext);
      block = _join(wrappedDek, entryCiphertext);
      final VaultFreeSlot slot = vaultFileEngine.allocateEntryBlockSlot(
        path: path,
        opened: opened,
        requiredLength: block.length,
      );
      final VaultEntryRecord record = VaultEntryRecord(
        entryId: entryId,
        blockOffset: slot.offset,
        blockLength: block.length,
        blockCapacity: slot.capacity,
        plaintextFormatId: 1,
        sequence: opened.header.sequenceCounter,
      );
      activityGuard.ensureActive();
      vaultFileEngine.commitEntryBlock(
        path: path,
        opened: opened,
        record: record,
        block: block,
        nextFreeListHead: slot.nextFreeListHead,
        splitFreeSlot: slot.remainder,
      );
      final EntrySummary summary = completeEntry.toSummary();
      _entrySummaries = List<EntrySummary>.unmodifiable(<EntrySummary>[
        ..._entrySummaries,
        summary,
      ]);
      return summary;
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } on Object catch (error) {
      throw VaultIoException(cause: error);
    } finally {
      if (block != null) {
        clearSensitiveBytes(block);
      }
      if (entryCiphertext != null) {
        clearSensitiveBytes(entryCiphertext);
      }
      if (wrappedDek != null) {
        clearSensitiveBytes(wrappedDek);
      }
      if (encryptedEntry != null) {
        clearSensitiveBytes(encryptedEntry.nonce);
        clearSensitiveBytes(encryptedEntry.ciphertext);
      }
      if (wrappedCiphertext != null) {
        clearSensitiveBytes(wrappedCiphertext.nonce);
        clearSensitiveBytes(wrappedCiphertext.ciphertext);
      }
      if (plaintext != null) {
        clearSensitiveBytes(plaintext);
      }
      if (entryAad != null) {
        clearSensitiveBytes(entryAad);
      }
      if (wrapAad != null) {
        clearSensitiveBytes(wrapAad);
      }
      if (dek != null) {
        clearSensitiveBytes(dek);
      }
      if (entryId != null) {
        clearSensitiveBytes(entryId);
      }
    }
  }

  @override
  Future<EntryDetail> getEntryDetail(
    Uint8List entryId, {
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) throw const VaultLockedException();
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      final VaultEntryRecord record = _recordFor(opened.directory, entryId);
      return EntryDetail(
        _decryptEntry(path, opened.header, record, masterVaultKey),
      );
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on Object catch (error) {
      throw VaultCorruptedException(cause: error);
    }
  }

  @override
  Future<void> deleteEntry(
    Uint8List entryId, {
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    if (_masterVaultKey == null) throw const VaultLockedException();
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      final VaultEntryRecord record = _recordFor(opened.directory, entryId);
      activityGuard.ensureActive();
      vaultFileEngine.commitEntryDeletion(
        path: path,
        opened: opened,
        record: record,
      );
      _entrySummaries = List<EntrySummary>.unmodifiable(
        _entrySummaries.where(
          (EntrySummary item) => !_sameBytes(item.entryId, entryId),
        ),
      );
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on Object catch (error) {
      throw VaultCorruptedException(cause: error);
    }
  }

  @override
  Future<EntrySummary> updateEntry(
    VaultEntry entry, {
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    if (entry.name.trim().isEmpty) {
      throw const InvalidArgumentException('An entry name is required.');
    }
    final Uint8List? masterVaultKey = _masterVaultKey;
    if (masterVaultKey == null) throw const VaultLockedException();
    Uint8List? plaintext;
    Uint8List? dek;
    Uint8List? wrapAad;
    Uint8List? entryAad;
    Uint8List? wrapped;
    Uint8List? cipher;
    Uint8List? block;
    AeadCiphertext? wrappedCipher;
    AeadCiphertext? encrypted;
    try {
      final String path = await vaultPathResolver();
      activityGuard.ensureActive();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      final VaultEntryRecord current = _recordFor(
        opened.directory,
        entry.entryId,
      );
      final VaultEntry replacement = entry.copyWith(
        updatedAt: DateTime.now().toUtc(),
      );
      plaintext = VaultEntryJsonCodec.encode(replacement);
      dek = crypto.generateKey();
      wrapAad = AadBuilder.forWrapDek(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: opened.header.aeadAlgorithmId,
        entryId: entry.entryId,
      );
      wrappedCipher = crypto.encryptWithAead(masterVaultKey, dek, wrapAad);
      wrapped = _join(wrappedCipher.nonce, wrappedCipher.ciphertext);
      entryAad = AadBuilder.forEncryptEntry(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: opened.header.aeadAlgorithmId,
        entryId: entry.entryId,
        sequence: opened.header.sequenceCounter,
      );
      encrypted = crypto.encryptWithAead(dek, plaintext, entryAad);
      cipher = _join(encrypted.nonce, encrypted.ciphertext);
      block = _join(wrapped, cipher);
      final bool inPlace = block.length <= current.blockCapacity;
      final VaultFreeSlot slot = inPlace
          ? VaultFreeSlot(
              offset: current.blockOffset,
              capacity: current.blockCapacity,
              nextOffset: opened.header.freeListHead,
            )
          : vaultFileEngine.allocateEntryBlockSlot(
              path: path,
              opened: opened,
              requiredLength: block.length,
            );
      final VaultEntryRecord record = VaultEntryRecord(
        entryId: entry.entryId,
        blockOffset: slot.offset,
        blockLength: block.length,
        blockCapacity: slot.capacity,
        plaintextFormatId: 1,
        sequence: opened.header.sequenceCounter,
      );
      final int nextFree = inPlace
          ? opened.header.freeListHead
          : current.blockOffset;
      activityGuard.ensureActive();
      vaultFileEngine.commitEntryBlock(
        path: path,
        opened: opened,
        record: record,
        block: block,
        replacedRecord: current,
        freedRecord: inPlace ? null : current,
        nextFreeListHead: nextFree,
        freedNextOffset: slot.nextFreeListHead,
        splitFreeSlot: inPlace ? null : slot.remainder,
      );
      final EntrySummary summary = replacement.toSummary();
      _entrySummaries = List<EntrySummary>.unmodifiable(
        _entrySummaries.map(
          (EntrySummary item) =>
              _sameBytes(item.entryId, entry.entryId) ? summary : item,
        ),
      );
      return summary;
    } on SessionActivityInterrupted {
      rethrow;
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on Object catch (error) {
      throw VaultCorruptedException(cause: error);
    } finally {
      for (final Uint8List? bytes in <Uint8List?>[
        block,
        cipher,
        wrapped,
        plaintext,
        entryAad,
        wrapAad,
        dek,
      ]) {
        if (bytes != null) clearSensitiveBytes(bytes);
      }
      if (wrappedCipher != null) {
        clearSensitiveBytes(wrappedCipher.nonce);
        clearSensitiveBytes(wrappedCipher.ciphertext);
      }
      if (encrypted != null) {
        clearSensitiveBytes(encrypted.nonce);
        clearSensitiveBytes(encrypted.ciphertext);
      }
    }
  }

  @override
  void clearUnlockedSession() {
    _activeUnlockOperation = null;
    final Uint8List? masterVaultKey = _masterVaultKey;
    _masterVaultKey = null;
    if (masterVaultKey != null) {
      clearSensitiveBytes(masterVaultKey);
    }
    _entrySummaries = const <EntrySummary>[];
    _activeKdfParameters = null;
  }

  MigrationEntryPayload _exportMigrationEntry({
    required String path,
    required VaultFileHeader header,
    required VaultEntryRecord record,
    required Uint8List masterVaultKey,
  }) {
    Uint8List? block;
    Uint8List? wrappedNonce;
    Uint8List? wrappedCiphertext;
    Uint8List? entryCiphertext;
    Uint8List? dek;
    Uint8List? wrapAad;
    try {
      block = vaultFileEngine.readEntryBlock(path, record);
      if (block.length < 112) {
        throw const FormatException('Entry Block has an invalid length.');
      }
      wrappedNonce = Uint8List.fromList(block.sublist(0, 24));
      wrappedCiphertext = Uint8List.fromList(block.sublist(24, 72));
      entryCiphertext = Uint8List.fromList(block.sublist(72));
      wrapAad = AadBuilder.forWrapDek(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: header.aeadAlgorithmId,
        entryId: record.entryId,
      );
      try {
        dek = crypto.decryptWithAead(
          masterVaultKey,
          wrappedNonce,
          wrappedCiphertext,
          wrapAad,
        );
      } on Object catch (error) {
        throw VaultCorruptedException(cause: error);
      }
      if (dek.length != 32) {
        throw const FormatException('Entry DEK has an invalid length.');
      }
      return MigrationEntryPayload(
        entryId: record.entryId,
        sequence: record.sequence,
        plaintextFormatId: record.plaintextFormatId,
        entryCiphertext: entryCiphertext,
        dek: dek,
      );
    } finally {
      for (final Uint8List? bytes in <Uint8List?>[
        block,
        wrappedNonce,
        wrappedCiphertext,
        entryCiphertext,
        dek,
        wrapAad,
      ]) {
        if (bytes != null) {
          clearSensitiveBytes(bytes);
        }
      }
    }
  }

  VaultEntry _decryptMigrationEntry({
    required VaultFileHeader header,
    required MigrationEntryPayload payload,
  }) {
    Uint8List? nonce;
    Uint8List? ciphertext;
    Uint8List? plaintext;
    Uint8List? entryAad;
    try {
      nonce = Uint8List.fromList(payload.entryCiphertext.sublist(0, 24));
      ciphertext = Uint8List.fromList(payload.entryCiphertext.sublist(24));
      entryAad = AadBuilder.forEncryptEntry(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: header.aeadAlgorithmId,
        entryId: payload.entryId,
        sequence: payload.sequence,
      );
      try {
        plaintext = crypto.decryptWithAead(
          payload.dek,
          nonce,
          ciphertext,
          entryAad,
        );
      } on Object catch (error) {
        throw VaultCorruptedException(cause: error);
      }
      return VaultEntryJsonCodec.decode(plaintext, entryId: payload.entryId);
    } finally {
      for (final Uint8List? bytes in <Uint8List?>[
        nonce,
        ciphertext,
        plaintext,
        entryAad,
      ]) {
        if (bytes != null) {
          clearSensitiveBytes(bytes);
        }
      }
    }
  }

  List<EntrySummary> _loadEntrySummaries({
    required String path,
    required VaultFileHeader header,
    required VaultDirectory directory,
    required Uint8List masterVaultKey,
  }) {
    final List<EntrySummary> summaries = <EntrySummary>[];
    for (final VaultEntryRecord record in directory.records) {
      Uint8List? block;
      Uint8List? wrappedNonce;
      Uint8List? wrappedCiphertext;
      Uint8List? dek;
      Uint8List? entryNonce;
      Uint8List? entryCiphertext;
      Uint8List? plaintext;
      Uint8List? wrapAad;
      Uint8List? entryAad;
      try {
        block = vaultFileEngine.readEntryBlock(path, record);
        if (block.length < 72 + 24 + 16) {
          throw const FormatException('Entry Block has an invalid length.');
        }
        wrappedNonce = Uint8List.fromList(block.sublist(0, 24));
        wrappedCiphertext = Uint8List.fromList(block.sublist(24, 72));
        wrapAad = AadBuilder.forWrapDek(
          magic: vaultMagic,
          formatVersion: vaultFormatVersion,
          aeadAlgorithmId: header.aeadAlgorithmId,
          entryId: record.entryId,
        );
        try {
          dek = crypto.decryptWithAead(
            masterVaultKey,
            wrappedNonce,
            wrappedCiphertext,
            wrapAad,
          );
        } on Object catch (error) {
          throw VaultCorruptedException(cause: error);
        }
        entryNonce = Uint8List.fromList(block.sublist(72, 96));
        entryCiphertext = Uint8List.fromList(block.sublist(96));
        entryAad = AadBuilder.forEncryptEntry(
          magic: vaultMagic,
          formatVersion: vaultFormatVersion,
          aeadAlgorithmId: header.aeadAlgorithmId,
          entryId: record.entryId,
          sequence: record.sequence,
        );
        try {
          plaintext = crypto.decryptWithAead(
            dek,
            entryNonce,
            entryCiphertext,
            entryAad,
          );
        } on Object catch (error) {
          throw VaultCorruptedException(cause: error);
        }
        summaries.add(
          VaultEntryJsonCodec.decode(
            plaintext,
            entryId: record.entryId,
          ).toSummary(),
        );
      } finally {
        if (entryAad != null) {
          clearSensitiveBytes(entryAad);
        }
        if (wrapAad != null) {
          clearSensitiveBytes(wrapAad);
        }
        if (plaintext != null) {
          clearSensitiveBytes(plaintext);
        }
        if (entryCiphertext != null) {
          clearSensitiveBytes(entryCiphertext);
        }
        if (entryNonce != null) {
          clearSensitiveBytes(entryNonce);
        }
        if (dek != null) {
          clearSensitiveBytes(dek);
        }
        if (wrappedCiphertext != null) {
          clearSensitiveBytes(wrappedCiphertext);
        }
        if (wrappedNonce != null) {
          clearSensitiveBytes(wrappedNonce);
        }
        if (block != null) {
          clearSensitiveBytes(block);
        }
      }
    }
    return List<EntrySummary>.unmodifiable(summaries);
  }

  VaultEntryRecord _recordFor(VaultDirectory directory, Uint8List entryId) {
    for (final VaultEntryRecord record in directory.records) {
      if (_sameBytes(record.entryId, entryId)) return record;
    }
    throw const VaultCorruptedException();
  }

  VaultEntry _decryptEntry(
    String path,
    VaultFileHeader header,
    VaultEntryRecord record,
    Uint8List masterVaultKey,
  ) {
    Uint8List? block;
    Uint8List? dek;
    Uint8List? plaintext;
    Uint8List? wrapAad;
    Uint8List? entryAad;
    try {
      block = vaultFileEngine.readEntryBlock(path, record);
      if (block.length < 112) {
        throw const FormatException('Entry Block is invalid.');
      }
      wrapAad = AadBuilder.forWrapDek(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: header.aeadAlgorithmId,
        entryId: record.entryId,
      );
      dek = crypto.decryptWithAead(
        masterVaultKey,
        Uint8List.fromList(block.sublist(0, 24)),
        Uint8List.fromList(block.sublist(24, 72)),
        wrapAad,
      );
      entryAad = AadBuilder.forEncryptEntry(
        magic: vaultMagic,
        formatVersion: vaultFormatVersion,
        aeadAlgorithmId: header.aeadAlgorithmId,
        entryId: record.entryId,
        sequence: record.sequence,
      );
      plaintext = crypto.decryptWithAead(
        dek,
        Uint8List.fromList(block.sublist(72, 96)),
        Uint8List.fromList(block.sublist(96)),
        entryAad,
      );
      return VaultEntryJsonCodec.decode(plaintext, entryId: record.entryId);
    } on VaultException {
      rethrow;
    } on Object catch (error) {
      throw VaultCorruptedException(cause: error);
    } finally {
      for (final Uint8List? bytes in <Uint8List?>[
        entryAad,
        wrapAad,
        plaintext,
        dek,
        block,
      ]) {
        if (bytes != null) clearSensitiveBytes(bytes);
      }
    }
  }

  Uint8List _join(Uint8List first, Uint8List second) {
    return Uint8List(first.length + second.length)
      ..setRange(0, first.length, first)
      ..setRange(first.length, first.length + second.length, second);
  }

  bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Uint8List _encodeKdfParameters(Argon2idParameters parameters) {
    final ByteData data = ByteData(12)
      ..setUint32(0, parameters.memoryKiB, Endian.big)
      ..setUint32(4, parameters.iterations, Endian.big)
      ..setUint32(8, parameters.parallelism, Endian.big);
    return data.buffer.asUint8List();
  }

  Uint8List _encodeVaultKdfParameters(VaultKdfParameters parameters) {
    final ByteData data = ByteData(12)
      ..setUint32(0, parameters.memoryKiB, Endian.big)
      ..setUint32(4, parameters.iterations, Endian.big)
      ..setUint32(8, parameters.parallelism, Endian.big);
    return data.buffer.asUint8List();
  }

  Object _beginUnlockOperation(SessionActivityGuard activityGuard) {
    activityGuard.ensureActive();
    clearUnlockedSession();
    final Object operation = Object();
    _activeUnlockOperation = operation;
    return operation;
  }

  void _ensureUnlockOperationActive(
    SessionActivityGuard activityGuard,
    Object operation,
  ) {
    activityGuard.ensureActive();
    if (!identical(_activeUnlockOperation, operation)) {
      throw const SessionUnlockInterrupted();
    }
  }

  void _clearUnlockSessionIfOwned(Object operation) {
    if (identical(_activeUnlockOperation, operation)) {
      clearUnlockedSession();
    }
  }

  void _finishUnlockOperation(Object operation) {
    if (identical(_activeUnlockOperation, operation)) {
      _activeUnlockOperation = null;
    }
  }

  BiometricKeyStore _requireBiometricKeyStore() {
    final BiometricKeyStore? store = biometricKeyStore;
    if (store == null) {
      throw const BiometricUnavailableException();
    }
    return store;
  }

  void _validateBiometricKey(Uint8List key) {
    if (key.length != 32) {
      throw const CryptoInitializationException();
    }
  }

  void _clearHeaderKeyMaterial(VaultFileHeader header) {
    clearSensitiveBytes(header.kdfSalt);
    clearSensitiveBytes(header.wrappedMasterVaultKey);
    final Uint8List? biometricWrapped = header.biometricWrappedMasterVaultKey;
    if (biometricWrapped != null) {
      clearSensitiveBytes(biometricWrapped);
    }
  }
}
