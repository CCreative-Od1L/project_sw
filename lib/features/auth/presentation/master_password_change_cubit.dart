import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/shared/result.dart';

/// UI state for the master-password change form.
sealed class MasterPasswordChangeViewState {
  /// Creates a master-password change state.
  const MasterPasswordChangeViewState();
}

/// The form is ready for input.
final class MasterPasswordChangeReady extends MasterPasswordChangeViewState {
  /// Creates the ready state.
  const MasterPasswordChangeReady();
}

/// Password verification and atomic re-wrap are running.
final class MasterPasswordChangeWorking extends MasterPasswordChangeViewState {
  /// Creates the working state.
  const MasterPasswordChangeWorking();
}

/// The current master password was rejected.
final class MasterPasswordChangeInvalidCurrent
    extends MasterPasswordChangeViewState {
  /// Creates the invalid-current-password state.
  const MasterPasswordChangeInvalidCurrent();
}

/// The replacement master password failed input validation.
final class MasterPasswordChangeInvalidNew
    extends MasterPasswordChangeViewState {
  /// Creates the invalid-new-password state.
  const MasterPasswordChangeInvalidNew();
}

/// The replacement password and confirmation did not match.
final class MasterPasswordChangeConfirmationMismatch
    extends MasterPasswordChangeViewState {
  /// Creates the confirmation-mismatch state.
  const MasterPasswordChangeConfirmationMismatch();
}

/// The master password and session strength were updated successfully.
final class MasterPasswordChangeCompleted
    extends MasterPasswordChangeViewState {
  /// Creates the completed state.
  const MasterPasswordChangeCompleted();
}

/// A system fault prevented the change from completing.
final class MasterPasswordChangeFault extends MasterPasswordChangeViewState {
  /// Creates the fault state.
  const MasterPasswordChangeFault();
}

/// Coordinates one master-password change form with the session truth source.
final class MasterPasswordChangeCubit
    extends Cubit<MasterPasswordChangeViewState> {
  /// Creates the presentation coordinator.
  MasterPasswordChangeCubit(this._changeMasterPassword, this._sessionController)
    : super(const MasterPasswordChangeReady());

  final ChangeMasterPassword _changeMasterPassword;
  final SessionController _sessionController;

  /// Restores a completed or failed form to its initial state.
  void reset() {
    if (state is! MasterPasswordChangeWorking) {
      emit(const MasterPasswordChangeReady());
    }
  }

  /// Validates confirmation, changes the password, and upgrades auth strength.
  Future<void> submit({
    required String currentMasterPassword,
    required String newMasterPassword,
    required String confirmation,
  }) async {
    if (state is MasterPasswordChangeWorking) {
      return;
    }
    if (newMasterPassword != confirmation) {
      emit(const MasterPasswordChangeConfirmationMismatch());
      return;
    }
    emit(const MasterPasswordChangeWorking());
    try {
      final Result<ChangedMasterPassword, ChangeMasterPasswordFailure> result =
          await _changeMasterPassword(
            currentMasterPassword: currentMasterPassword,
            newMasterPassword: newMasterPassword,
          );
      switch (result) {
        case Success<ChangedMasterPassword, ChangeMasterPasswordFailure>():
          final SessionState session = _sessionController.state;
          if (session is! UnlockedSession) {
            emit(const MasterPasswordChangeFault());
            return;
          }
          if (_sessionController.requiresMasterPasswordStepUp) {
            _sessionController.completeMasterPasswordStepUp();
          }
          emit(const MasterPasswordChangeCompleted());
        case Failure<ChangedMasterPassword, ChangeMasterPasswordFailure>(
          :final ChangeMasterPasswordFailure failure,
        ):
          emit(switch (failure) {
            ChangeMasterPasswordFailure.invalidCurrentMasterPassword =>
              const MasterPasswordChangeInvalidCurrent(),
            ChangeMasterPasswordFailure.invalidNewMasterPassword =>
              const MasterPasswordChangeInvalidNew(),
          });
      }
    } on Object {
      emit(const MasterPasswordChangeFault());
    }
  }
}
