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
}
