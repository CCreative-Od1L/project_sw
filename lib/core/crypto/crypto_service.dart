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

  /// Generates a one-time X25519 key pair for a migration handshake.
  EphemeralKeyPair generateEphemeralKeyPair();

  /// Derives the client-to-server and server-to-client session keys.
  DirectionalSessionKeys deriveClientSessionKeys({
    required Uint8List clientPublicKey,
    required Uint8List clientSecretKey,
    required Uint8List serverPublicKey,
  });

  /// Derives the server-to-client and client-to-server session keys.
  DirectionalSessionKeys deriveServerSessionKeys({
    required Uint8List serverPublicKey,
    required Uint8List serverSecretKey,
    required Uint8List clientPublicKey,
  });

  /// Computes a fixed-size transcript digest.
  Uint8List hash(Uint8List message);

  /// Computes a fixed-size keyed transcript MAC.
  Uint8List mac(Uint8List key, Uint8List message);
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

/// A one-time X25519 key pair owned by a migration handshake.
final class EphemeralKeyPair {
  /// Creates a key pair from copied public and secret key bytes.
  EphemeralKeyPair({required Uint8List publicKey, required Uint8List secretKey})
    : publicKey = Uint8List.fromList(publicKey),
      secretKey = Uint8List.fromList(secretKey) {
    if (this.publicKey.length != 32 || this.secretKey.length != 32) {
      throw ArgumentError('X25519 keys must be 32 bytes long.');
    }
  }

  /// Public key safe to place in the pairing payload.
  final Uint8List publicKey;

  /// Secret key that must be cleared after session-key derivation.
  final Uint8List secretKey;

  /// Clears the secret key and public-key buffer in place.
  void dispose() {
    clearSensitiveBytes(publicKey);
    clearSensitiveBytes(secretKey);
  }
}

/// Directional keys returned by a migration key exchange.
final class DirectionalSessionKeys {
  /// Creates copied transmit and receive keys.
  DirectionalSessionKeys({required Uint8List tx, required Uint8List rx})
    : tx = Uint8List.fromList(tx),
      rx = Uint8List.fromList(rx) {
    if (this.tx.length != 32 || this.rx.length != 32) {
      throw ArgumentError('Migration session keys must be 32 bytes long.');
    }
  }

  /// Key used to encrypt messages sent by this endpoint.
  final Uint8List tx;

  /// Key used to decrypt messages received by this endpoint.
  final Uint8List rx;

  /// Clears both directional keys in place.
  void dispose() {
    clearSensitiveBytes(tx);
    clearSensitiveBytes(rx);
  }
}

/// Clears a sensitive byte buffer in place.
void clearSensitiveBytes(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
