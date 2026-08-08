import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/shared/result.dart';

/// Expected outcomes for a master-password step-up challenge.
enum VerifyMasterPasswordFailure {
  /// The supplied password did not authenticate the vault.
  invalidMasterPassword,
}

/// Successful master-password verification without a new session object.
final class VerifiedMasterPassword {
  /// Creates a successful verification outcome.
  const VerifiedMasterPassword();
}

/// Verifies a master password for an already unlocked high-sensitivity action.
final class VerifyMasterPassword {
  /// Creates the use case from the password-verification boundary.
  const VerifyMasterPassword(this._verifier);

  final MasterPasswordVerifier _verifier;

  /// Maps only an expected bad password to a stable business failure.
  Future<Result<VerifiedMasterPassword, VerifyMasterPasswordFailure>> call(
    String masterPassword,
  ) async {
    if (masterPassword.isEmpty) {
      return const Failure<VerifiedMasterPassword, VerifyMasterPasswordFailure>(
        VerifyMasterPasswordFailure.invalidMasterPassword,
      );
    }
    try {
      await _verifier.verifyMasterPassword(masterPassword);
      return const Success<VerifiedMasterPassword, VerifyMasterPasswordFailure>(
        VerifiedMasterPassword(),
      );
    } on InvalidMasterPasswordException {
      return const Failure<VerifiedMasterPassword, VerifyMasterPasswordFailure>(
        VerifyMasterPasswordFailure.invalidMasterPassword,
      );
    }
  }
}
