import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/shared/result.dart';

/// Stable, user-actionable failures for the master-password unlock form.
enum UnlockFailure {
  /// The supplied password cannot unwrap the vault's MVK.
  invalidMasterPassword,
}

/// Successful master-password authentication with an unlocked repository.
final class UnlockedVault {
  /// Creates a successful unlock outcome.
  const UnlockedVault();
}

/// Opens a vault and maps only an expected bad-password failure to [Result].
final class UnlockVault {
  /// Creates the use case from its repository boundary.
  const UnlockVault(this._repository);

  final VaultRepository _repository;

  /// Attempts master-password authentication without absorbing system faults.
  Future<Result<UnlockedVault, UnlockFailure>> call(
    String masterPassword,
  ) async {
    if (masterPassword.isEmpty) {
      return const Failure<UnlockedVault, UnlockFailure>(
        UnlockFailure.invalidMasterPassword,
      );
    }
    try {
      await _repository.unlockWithMasterPassword(masterPassword);
      return const Success<UnlockedVault, UnlockFailure>(UnlockedVault());
    } on InvalidMasterPasswordException {
      return const Failure<UnlockedVault, UnlockFailure>(
        UnlockFailure.invalidMasterPassword,
      );
    }
  }
}
