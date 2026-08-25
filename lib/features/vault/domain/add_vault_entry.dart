import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';

/// Adds one complete VaultEntry through the unlocked repository boundary.
final class AddVaultEntry {
  /// Creates the use case from the vault repository.
  const AddVaultEntry(this._repository);

  final VaultRepository _repository;

  /// Persists [entry] and returns its safe EntrySummary projection.
  Future<EntrySummary> call(
    NewVaultEntry entry, {
    required SessionActivityGuard activityGuard,
  }) => _repository.addEntry(entry, activityGuard: activityGuard);
}
