import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/shared/result.dart';

/// Expected business failure before a normal authenticated wipe may begin.
enum AuthenticatedWipeFailure {
  /// The supplied current master password was rejected.
  invalidMasterPassword,
}

/// Verifies the current master password before entering the wipe transaction.
final class AuthenticatedWipeVault {
  /// Creates the normal wipe path from verification and destruction use cases.
  const AuthenticatedWipeVault(
    this._verifyMasterPassword,
    this._wipeVault,
    this._sessionController,
  );

  final VerifyMasterPassword _verifyMasterPassword;
  final WipeVault _wipeVault;
  final SessionController _sessionController;

  /// Wrong passwords are business failures; wipe system faults still throw.
  Future<Result<WipedVault, AuthenticatedWipeFailure>> call(
    String masterPassword,
  ) async {
    final SessionActivityLease activityLease = _sessionController.beginActivity(
      SessionActivity.authenticatedWipe,
    );
    try {
      final Result<VerifiedMasterPassword, VerifyMasterPasswordFailure>
      verification = await _verifyMasterPassword(masterPassword);
      activityLease.ensureActive();
      if (verification
          case Failure<VerifiedMasterPassword, VerifyMasterPasswordFailure>()) {
        return const Failure<WipedVault, AuthenticatedWipeFailure>(
          AuthenticatedWipeFailure.invalidMasterPassword,
        );
      }
      activityLease.ensureActive();
      return Success<WipedVault, AuthenticatedWipeFailure>(await _wipeVault());
    } finally {
      activityLease.complete();
    }
  }
}
