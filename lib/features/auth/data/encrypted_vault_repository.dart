import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/aad_builder.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
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

  @override
  bool get hasUnlockedSession => _masterVaultKey != null;

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
      header = vaultFileEngine.openVaultFile(path).header;
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
  void clearUnlockedSession() {
    final Uint8List? masterVaultKey = _masterVaultKey;
    _masterVaultKey = null;
    if (masterVaultKey != null) {
      clearSensitiveBytes(masterVaultKey);
    }
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
