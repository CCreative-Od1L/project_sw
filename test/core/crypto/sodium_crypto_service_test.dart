import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/core/crypto/sodium_crypto_service.dart';
import 'package:test/test.dart';

void main() {
  test(
    'derives Argon2id in a short-lived isolate and round-trips AEAD',
    () async {
      final SodiumCryptoService crypto = await SodiumCryptoService.initialize();
      final Uint8List salt = crypto.randomBytes(16);
      final Uint8List plaintext = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final Uint8List additionalData = Uint8List.fromList(<int>[5, 6]);
      Uint8List? kek;
      Uint8List? key;
      Uint8List? decrypted;
      try {
        kek = await crypto.deriveKek(
          'test-only master password',
          salt,
          memoryKiB: 19 * 1024,
          iterations: 2,
          parallelism: 1,
        );
        expect(kek, hasLength(32));
        key = crypto.generateKey();
        final AeadCiphertext encrypted = crypto.encryptWithAead(
          key,
          plaintext,
          additionalData,
        );
        try {
          decrypted = crypto.decryptWithAead(
            key,
            encrypted.nonce,
            encrypted.ciphertext,
            additionalData,
          );
          expect(decrypted, plaintext);
        } finally {
          clearSensitiveBytes(encrypted.nonce);
          clearSensitiveBytes(encrypted.ciphertext);
        }
      } finally {
        clearSensitiveBytes(salt);
        clearSensitiveBytes(plaintext);
        clearSensitiveBytes(additionalData);
        if (kek != null) {
          clearSensitiveBytes(kek);
        }
        if (key != null) {
          clearSensitiveBytes(key);
        }
        if (decrypted != null) {
          clearSensitiveBytes(decrypted);
        }
      }
    },
  );

  test('derives matching directional crypto_kx session keys', () async {
    final SodiumCryptoService crypto = await SodiumCryptoService.initialize();
    final EphemeralKeyPair clientIdentity = crypto.generateEphemeralKeyPair();
    final EphemeralKeyPair serverIdentity = crypto.generateEphemeralKeyPair();
    final Uint8List clientPublicKey = Uint8List.fromList(
      clientIdentity.publicKey,
    );
    final Uint8List serverPublicKey = Uint8List.fromList(
      serverIdentity.publicKey,
    );
    DirectionalSessionKeys? clientKeys;
    DirectionalSessionKeys? serverKeys;
    try {
      clientKeys = crypto.deriveClientSessionKeys(
        clientPublicKey: clientPublicKey,
        clientSecretKey: clientIdentity.secretKey,
        serverPublicKey: serverPublicKey,
      );
      serverKeys = crypto.deriveServerSessionKeys(
        serverPublicKey: serverIdentity.publicKey,
        serverSecretKey: serverIdentity.secretKey,
        clientPublicKey: clientPublicKey,
      );

      expect(clientKeys.tx, serverKeys.rx);
      expect(clientKeys.rx, serverKeys.tx);
    } finally {
      clientIdentity.dispose();
      serverIdentity.dispose();
      clearSensitiveBytes(clientPublicKey);
      clearSensitiveBytes(serverPublicKey);
      clientKeys?.dispose();
      serverKeys?.dispose();
    }
  });
}
