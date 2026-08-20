/// Removes every durable artifact owned by the local password vault.
abstract interface class VaultWipeRepository {
  /// Completes only after platform keys and all explicit file targets are gone.
  Future<void> wipeVault();
}

/// Normalized failure while destroying vault-owned durable state.
final class VaultWipeException implements Exception {
  /// Creates a safe wipe failure without exposing paths or platform details.
  const VaultWipeException({this.cause});

  /// Underlying adapter failure retained for local diagnostics.
  final Object? cause;

  @override
  String toString() => 'VaultWipeException';
}
