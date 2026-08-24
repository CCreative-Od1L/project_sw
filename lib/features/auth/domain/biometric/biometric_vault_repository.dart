import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';

/// Vault operations that use the device's biometric key store.
abstract interface class BiometricVaultRepository {
  /// Whether the last opened vault header advertised biometric access.
  bool get hasBiometricUnlock;

  /// Reads the vault header and reports whether biometric access is configured.
  Future<bool> hasConfiguredBiometricUnlock();

  /// Protects the current unlocked MVK with a newly provisioned platform key.
  Future<void> enableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  });

  /// Removes the biometric envelope and deletes the platform key.
  Future<void> disableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  });

  /// Uses the platform key to restore the unlocked MVK and safe projections.
  Future<void> unlockWithBiometric();
}
