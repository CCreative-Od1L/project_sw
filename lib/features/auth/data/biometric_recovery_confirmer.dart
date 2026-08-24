import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';

/// Uses the existing K_bio release path only as a recovery confirmation.
final class BiometricKeyStoreRecoveryConfirmer
    implements BiometricRecoveryConfirmer {
  /// Creates the adapter around the platform biometric key store.
  const BiometricKeyStoreRecoveryConfirmer(this._keyStore);

  final BiometricKeyStore _keyStore;

  @override
  Future<void> confirm() async {
    Uint8List? releasedKey;
    try {
      releasedKey = await _keyStore.loadKey();
      if (releasedKey.length != 32) {
        throw const BiometricAuthenticationException();
      }
    } finally {
      if (releasedKey != null) {
        clearSensitiveBytes(releasedKey);
      }
    }
  }
}
