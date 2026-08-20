/// Persists an atomic Master Vault Key re-wrap under a new master password.
abstract interface class MasterPasswordChangeRepository {
  /// Verifies [currentMasterPassword], generates a fresh KDF salt, and wraps
  /// the unchanged Master Vault Key with [newMasterPassword].
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  });
}
