/// Durable intent that keeps a partially completed wipe blocked after restart.
abstract interface class VaultWipeProgressStore {
  /// Whether an earlier wipe has not yet verified all deletion targets.
  Future<bool> readPending();

  /// Persists intent before the first irreversible deletion starts.
  Future<void> markPending();

  /// Removes intent only after every deletion target has been verified absent.
  Future<void> clear();
}
