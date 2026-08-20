/// Non-secret deadlines that govern master-password recovery visibility.
final class MasterPasswordRecoveryMetadata {
  /// Creates recovery metadata; every deadline must be interpreted as UTC.
  const MasterPasswordRecoveryMetadata({
    this.cooldownUntil,
    this.availableUntil,
  });

  /// UTC deadline for the one-week post-recovery cooldown.
  final DateTime? cooldownUntil;

  /// UTC deadline for resuming a recovery entry that already became visible.
  final DateTime? availableUntil;

  /// Whether no recovery deadline needs persistence.
  bool get isEmpty => cooldownUntil == null && availableUntil == null;
}

/// Atomically persists non-secret master-password recovery deadlines.
abstract interface class MasterPasswordRecoveryStore {
  /// Returns persisted metadata, or an empty value when the file is absent.
  Future<MasterPasswordRecoveryMetadata> read();

  /// Atomically replaces all persisted deadlines with [metadata].
  Future<void> write(MasterPasswordRecoveryMetadata metadata);

  /// Removes all recovery metadata, including temporary replacement files.
  Future<void> clear();
}

/// Normalized failure while reading or writing recovery metadata.
final class MasterPasswordRecoveryStoreException implements Exception {
  /// Creates a safe store failure without exposing filesystem paths.
  const MasterPasswordRecoveryStoreException({this.cause});

  /// Underlying adapter failure retained for local diagnostics.
  final Object? cause;

  @override
  String toString() => 'MasterPasswordRecoveryStoreException';
}
