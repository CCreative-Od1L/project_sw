import 'dart:typed_data';

/// Pure cryptographic primitives used by vault orchestration.
abstract interface class CryptoService {
  /// Derives a 256-bit KEK without blocking the UI isolate.
  Future<Uint8List> deriveKek(
    String password,
    Uint8List salt, {
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  });

  /// Generates a fresh 256-bit key.
  Uint8List generateKey();

  /// Generates cryptographically secure random bytes.
  Uint8List randomBytes(int length);

  /// Selects an unbiased integer in the range [0, upperBound).
  int randomBytesUniform(int upperBound);

  /// Encrypts [plaintext] with XChaCha20-Poly1305 and a fresh nonce.
  AeadCiphertext encryptWithAead(
    Uint8List key,
    Uint8List plaintext,
    Uint8List additionalData,
  );

  /// Decrypts an AEAD ciphertext or throws when authentication fails.
  Uint8List decryptWithAead(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List additionalData,
  );
}

/// The nonce and combined ciphertext returned by an AEAD operation.
final class AeadCiphertext {
  /// Creates an AEAD result.
  const AeadCiphertext({required this.nonce, required this.ciphertext});

  /// A freshly generated 24-byte XChaCha20 nonce.
  final Uint8List nonce;

  /// Ciphertext with its Poly1305 authentication tag.
  final Uint8List ciphertext;
}

/// Clears a sensitive byte buffer in place.
void clearSensitiveBytes(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
