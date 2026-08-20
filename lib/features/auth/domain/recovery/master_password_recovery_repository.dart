/// Re-wraps the currently unlocked MVK after biometric-assisted recovery.
abstract interface class MasterPasswordRecoveryRepository {
  /// Generates a fresh salt and wraps the unchanged MVK with the replacement.
  Future<void> recoverMasterPassword({required String newMasterPassword});
}
