/// Vault operations that use the device's biometric key store.
abstract interface class BiometricVaultRepository {
  /// Whether the last opened vault header advertised biometric access.
  bool get hasBiometricUnlock;

  /// Reads the vault header and reports whether biometric access is configured.
  Future<bool> hasConfiguredBiometricUnlock();

  /// Protects the current unlocked MVK with a newly provisioned platform key.
  Future<void> enableBiometricUnlock();

  /// Removes the biometric envelope and deletes the platform key.
  Future<void> disableBiometricUnlock();

  /// Uses the platform key to restore the unlocked MVK and safe projections.
  Future<void> unlockWithBiometric();
}
