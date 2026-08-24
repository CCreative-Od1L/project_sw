/// Performs the second biometric confirmation required by password recovery.
abstract interface class BiometricRecoveryConfirmer {
  /// Completes only when the platform releases the current biometric key.
  Future<void> confirm();
}
