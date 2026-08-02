import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/aad_builder.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/vault/data/vault_entry_json_codec.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';

/// Resolves the application-support location where the vault file is stored.
typedef VaultPathResolver = Future<String> Function();

/// Coordinates KDF, MVK wrapping, and the empty-vault file commit.
final class EncryptedVaultRepository implements VaultRepository {
  /// Creates a repository with a production or test [vaultPathResolver].
  EncryptedVaultRepository({
    required this.crypto,
    required this.vaultFileEngine,
    required this.vaultPathResolver,
  });

  /// Crypto primitives used to create and wrap the initial keys.
  final CryptoService crypto;

  /// The block-level single-file storage engine.
  final VaultFileEngine vaultFileEngine;

  /// Resolves the application-support vault path.
  final VaultPathResolver vaultPathResolver;
  Uint8List? _masterVaultKey;
  List<EntrySummary> _entrySummaries = const <EntrySummary>[];

  @override
  bool get hasUnlockedSession => _masterVaultKey != null;

  @override
  List<EntrySummary> get entrySummaries =>
      List<EntrySummary>.unmodifiable(_entrySummaries);

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
  Future<void> unlockWithMasterPassword(String masterPassword) async {
    Uint8List? kek;
    Uint8List? aad;
    Uint8List? nonce;
    Uint8List? ciphertext;
    VaultFileHeader? header;
    clearUnlockedSession();
    try {
      final String path = await vaultPathResolver();
      final OpenVaultFile opened = vaultFileEngine.openVaultFile(path);
      header = opened.header;
      kek = await crypto.deriveKek(
        masterPassword,
        header.kdfSalt,
        memoryKiB: header.kdfParameters.memoryKiB,
        iterations: header.kdfParameters.iterations,
        parallelism: header.kdfParameters.parallelism,
      );
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
      try {
        _entrySummaries = _loadEntrySummaries(
          path: path,
          header: header,
          directory: opened.directory,
          masterVaultKey: _masterVaultKey!,
        );
      } on VaultException {
        clearUnlockedSession();
        rethrow;
      } on Object catch (error) {
        clearUnlockedSession();
        throw VaultCorruptedException(cause: error);
      }
    } on VaultException {
      rethrow;
    } on FileSystemException catch (error) {
      throw VaultIoException(cause: error);
    } on FormatException catch (error) {
      throw VaultCorruptedException(cause: error);
    } finally {
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
        clearSensitiveBytes(header.kdfSalt);
        clearSensitiveBytes(header.wrappedMasterVaultKey);
      }
    }
  }

  @override
  Future<EntrySummary> addEntry(NewVaultEntry entry) async {
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
      final VaultEntryRecord record = VaultEntryRecord(
        entryId: entryId,
        blockOffset: vaultFileEngine.allocateEntryBlockOffset(opened.directory),
        blockLength: block.length,
        blockCapacity: block.length,
        plaintextFormatId: 1,
        sequence: opened.header.sequenceCounter,
      );
      vaultFileEngine.commitEntryBlock(
        path: path,
        opened: opened,
        record: record,
        block: block,
      );
      final EntrySummary summary = completeEntry.toSummary();
      _entrySummaries = List<EntrySummary>.unmodifiable(<EntrySummary>[
        ..._entrySummaries,
        summary,
      ]);
      return summary;
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
  void clearUnlockedSession() {
    final Uint8List? masterVaultKey = _masterVaultKey;
    _masterVaultKey = null;
    if (masterVaultKey != null) {
      clearSensitiveBytes(masterVaultKey);
    }
    _entrySummaries = const <EntrySummary>[];
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

  Uint8List _join(Uint8List first, Uint8List second) {
    return Uint8List(first.length + second.length)
      ..setRange(0, first.length, first)
      ..setRange(first.length, first.length + second.length, second);
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
}
