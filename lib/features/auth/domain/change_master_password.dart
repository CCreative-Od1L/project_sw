import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/shared/result.dart';

/// Expected business failures when changing an existing master password.
enum ChangeMasterPasswordFailure {
  /// The current master password did not authenticate the vault.
  invalidCurrentMasterPassword,

  /// The replacement master password is empty.
  invalidNewMasterPassword,
}

/// Successful completion of an atomic Master Vault Key re-wrap.
final class ChangedMasterPassword {
  /// Creates a successful change outcome.
  const ChangedMasterPassword();
}

/// Changes the master password without re-encrypting VaultEntry ciphertext.
final class ChangeMasterPassword {
  /// Creates the use case around the repository seam.
  const ChangeMasterPassword(this._repository);

  final MasterPasswordChangeRepository _repository;

  /// Validates expected input failures and delegates the atomic re-wrap.
  Future<Result<ChangedMasterPassword, ChangeMasterPasswordFailure>> call({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    if (currentMasterPassword.isEmpty) {
      return const Failure<ChangedMasterPassword, ChangeMasterPasswordFailure>(
        ChangeMasterPasswordFailure.invalidCurrentMasterPassword,
      );
    }
    if (newMasterPassword.isEmpty) {
      return const Failure<ChangedMasterPassword, ChangeMasterPasswordFailure>(
        ChangeMasterPasswordFailure.invalidNewMasterPassword,
      );
    }
    try {
      await _repository.changeMasterPassword(
        currentMasterPassword: currentMasterPassword,
        newMasterPassword: newMasterPassword,
      );
      return const Success<ChangedMasterPassword, ChangeMasterPasswordFailure>(
        ChangedMasterPassword(),
      );
    } on InvalidMasterPasswordException {
      return const Failure<ChangedMasterPassword, ChangeMasterPasswordFailure>(
        ChangeMasterPasswordFailure.invalidCurrentMasterPassword,
      );
    }
  }
}
