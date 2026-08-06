import 'dart:isolate';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:sodium/sodium_sumo.dart';

/// The production libsodium implementation of [CryptoService].
final class SodiumCryptoService implements CryptoService {
  /// Initializes the sodium runtime used by synchronous AEAD and CSPRNG calls.
  static Future<SodiumCryptoService> initialize() async {
    try {
      return SodiumCryptoService._(await SodiumSumoInit.init());
    } on Object catch (error) {
      throw CryptoInitializationException(cause: error);
    }
  }

  SodiumCryptoService._(this._sodium);

  final SodiumSumo _sodium;

  @override
  Future<Uint8List> deriveKek(
    String password,
    Uint8List salt, {
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) async {
    if (parallelism != 1) {
      throw const InvalidArgumentException(
        'Only Argon2id parallelism 1 is supported on mobile.',
      );
    }
    try {
      return await Isolate.run<Uint8List>(
        () => _deriveKekInBackground(
          password,
          Uint8List.fromList(salt),
          memoryKiB,
          iterations,
        ),
        debugName: 'argon2id-kek',
      );
    } on VaultException {
      rethrow;
    } on Object catch (error) {
      throw CryptoInitializationException(cause: error);
    }
  }

  @override
  Uint8List generateKey() => randomBytes(_aead.keyBytes);

  @override
  Uint8List randomBytes(int length) {
    try {
      return _sodium.randombytes.buf(length);
    } on Object catch (error) {
      throw EntropyUnavailableException(cause: error);
    }
  }

  @override
  int randomBytesUniform(int upperBound) {
    if (upperBound <= 0) {
      throw ArgumentError.value(upperBound, 'upperBound');
    }
    try {
      return _sodium.randombytes.uniform(upperBound);
    } on Object catch (error) {
      throw EntropyUnavailableException(cause: error);
    }
  }

  @override
  AeadCiphertext encryptWithAead(
    Uint8List key,
    Uint8List plaintext,
    Uint8List additionalData,
  ) {
    final SecureKey secureKey = SecureKey.fromList(_sodium, key);
    final Uint8List nonce = randomBytes(_aead.nonceBytes);
    try {
      return AeadCiphertext(
        nonce: nonce,
        ciphertext: _aead.encrypt(
          message: plaintext,
          nonce: nonce,
          key: secureKey,
          additionalData: additionalData,
        ),
      );
    } finally {
      secureKey.dispose();
    }
  }

  @override
  Uint8List decryptWithAead(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List additionalData,
  ) {
    final SecureKey secureKey = SecureKey.fromList(_sodium, key);
    try {
      return _aead.decrypt(
        cipherText: ciphertext,
        nonce: nonce,
        key: secureKey,
        additionalData: additionalData,
      );
    } finally {
      secureKey.dispose();
    }
  }

  Aead get _aead => _sodium.crypto.aeadXChaCha20Poly1305IETF;
}

Future<Uint8List> _deriveKekInBackground(
  String password,
  Uint8List salt,
  int memoryKiB,
  int iterations,
) async {
  Uint8List? keyBytes;
  try {
    final SodiumSumo sodium = await SodiumSumoInit.init();
    final Int8List passwordBytes = password.toCharArray();
    try {
      final SecureKey key = sodium.crypto.pwhash(
        outLen: 32,
        password: passwordBytes,
        salt: salt,
        opsLimit: iterations,
        memLimit: memoryKiB * 1024,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      try {
        keyBytes = key.extractBytes();
        return Uint8List.fromList(keyBytes);
      } finally {
        key.dispose();
      }
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
    }
  } finally {
    clearSensitiveBytes(salt);
    if (keyBytes != null) {
      clearSensitiveBytes(keyBytes);
    }
  }
}
