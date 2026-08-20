/// Persists the non-secret cooldown deadline for master-password recovery.
abstract interface class MasterPasswordRecoveryStore {
  /// Returns the persisted UTC cooldown deadline, or null when absent.
  Future<DateTime?> readCooldownUntil();

  /// Persists the UTC [value] after a successful recovery.
  Future<void> writeCooldownUntil(DateTime value);

  /// Removes an expired or wiped cooldown record.
  Future<void> clearCooldown();
}

/// Normalized failure while reading or writing recovery cooldown metadata.
final class MasterPasswordRecoveryStoreException implements Exception {
  /// Creates a safe store failure without exposing filesystem paths.
  const MasterPasswordRecoveryStoreException({this.cause});

  /// Underlying adapter failure retained for local diagnostics.
  final Object? cause;

  @override
  String toString() => 'MasterPasswordRecoveryStoreException';
}
