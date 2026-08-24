import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/recover_master_password.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/shared/result.dart';

/// Reads whether the vault currently has a usable biometric recovery envelope.
typedef HasConfiguredBiometricRecovery = Future<bool> Function();

/// UI state for the master-password change form.
sealed class MasterPasswordChangeViewState {
  /// Creates a master-password change state.
  const MasterPasswordChangeViewState();
}

/// The form is ready for input.
final class MasterPasswordChangeReady extends MasterPasswordChangeViewState {
  /// Creates the ready state.
  const MasterPasswordChangeReady({this.recoveryAvailable = false});

  /// Whether a previously revealed recovery flow may be resumed.
  final bool recoveryAvailable;
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
  const MasterPasswordChangeInvalidCurrent({this.recoveryAvailable = false});

  /// Whether the hidden recovery entry may now be shown.
  final bool recoveryAvailable;
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

/// The replacement recovery password failed input validation.
final class MasterPasswordRecoveryInvalidNew
    extends MasterPasswordChangeViewState {
  /// Creates the invalid recovery-password state.
  const MasterPasswordRecoveryInvalidNew();
}

/// The replacement recovery password remains in the weak strength band.
final class MasterPasswordRecoveryWeakNew
    extends MasterPasswordChangeViewState {
  /// Creates the weak recovery-password state.
  const MasterPasswordRecoveryWeakNew();
}

/// The recovery password and confirmation did not match.
final class MasterPasswordRecoveryConfirmationMismatch
    extends MasterPasswordChangeViewState {
  /// Creates the recovery confirmation-mismatch state.
  const MasterPasswordRecoveryConfirmationMismatch();
}

/// Recovery eligibility changed before the operation began.
final class MasterPasswordRecoveryUnavailable
    extends MasterPasswordChangeViewState {
  /// Creates the unavailable-recovery state.
  const MasterPasswordRecoveryUnavailable();
}

/// The user cancelled the second biometric confirmation.
final class MasterPasswordRecoveryBiometricCancelled
    extends MasterPasswordChangeViewState {
  /// Creates the cancelled-biometric state.
  const MasterPasswordRecoveryBiometricCancelled();
}

/// The configured biometric path is unavailable or invalidated.
final class MasterPasswordRecoveryBiometricUnavailable
    extends MasterPasswordChangeViewState {
  /// Creates the unavailable-biometric state.
  const MasterPasswordRecoveryBiometricUnavailable();
}

/// Biometric confirmation and vault re-wrapping are running.
final class MasterPasswordRecoveryWorking
    extends MasterPasswordChangeViewState {
  /// Creates the working recovery state.
  const MasterPasswordRecoveryWorking();
}

/// The master password was recovered without changing session strength.
final class MasterPasswordRecoveryCompleted
    extends MasterPasswordChangeViewState {
  /// Creates the completed recovery state.
  const MasterPasswordRecoveryCompleted();
}

/// A system fault prevented recovery from completing.
final class MasterPasswordRecoveryFault extends MasterPasswordChangeViewState {
  /// Creates the recovery fault state.
  const MasterPasswordRecoveryFault();
}

/// Coordinates one master-password change form with the session truth source.
final class MasterPasswordChangeCubit
    extends Cubit<MasterPasswordChangeViewState> {
  /// Creates the presentation coordinator.
  MasterPasswordChangeCubit(
    this._changeMasterPassword,
    this._sessionController, {
    MasterPasswordRecoveryGate? recoveryGate,
    HasConfiguredBiometricRecovery? hasConfiguredBiometricRecovery,
    RecoverMasterPassword? recoverMasterPassword,
  }) : assert(
         (recoveryGate == null &&
                 hasConfiguredBiometricRecovery == null &&
                 recoverMasterPassword == null) ||
             (recoveryGate != null &&
                 hasConfiguredBiometricRecovery != null &&
                 recoverMasterPassword != null),
         'Recovery collaborators must be registered together.',
       ),
       _recoveryGate = recoveryGate,
       _hasConfiguredBiometricRecovery = hasConfiguredBiometricRecovery,
       _recoverMasterPassword = recoverMasterPassword,
       super(const MasterPasswordChangeReady());

  final ChangeMasterPassword _changeMasterPassword;
  final SessionController _sessionController;
  final MasterPasswordRecoveryGate? _recoveryGate;
  final HasConfiguredBiometricRecovery? _hasConfiguredBiometricRecovery;
  final RecoverMasterPassword? _recoverMasterPassword;

  /// Restores a completed or failed form to its initial state.
  Future<void> reset() async {
    if (state is MasterPasswordChangeWorking ||
        state is MasterPasswordRecoveryWorking) {
      return;
    }
    try {
      emit(
        MasterPasswordChangeReady(
          recoveryAvailable: await _currentRecoveryAvailability(),
        ),
      );
    } on Object {
      emit(const MasterPasswordChangeFault());
    }
  }

  /// Validates confirmation, changes the password, and upgrades auth strength.
  Future<void> submit({
    required String currentMasterPassword,
    required String newMasterPassword,
    required String confirmation,
  }) async {
    if (state is MasterPasswordChangeWorking ||
        state is MasterPasswordRecoveryWorking) {
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
          await _recoveryGate?.recordChangePasswordSuccess();
          emit(const MasterPasswordChangeCompleted());
        case Failure<ChangedMasterPassword, ChangeMasterPasswordFailure>(
          :final ChangeMasterPasswordFailure failure,
        ):
          if (failure ==
              ChangeMasterPasswordFailure.invalidCurrentMasterPassword) {
            emit(
              MasterPasswordChangeInvalidCurrent(
                recoveryAvailable: await _recordRecoveryFailure(),
              ),
            );
          } else {
            emit(const MasterPasswordChangeInvalidNew());
          }
      }
    } on Object {
      emit(const MasterPasswordChangeFault());
    }
  }

  /// Confirms biometrics and installs a replacement password after warning UI.
  Future<void> recover({
    required String newMasterPassword,
    required String confirmation,
  }) async {
    if (state is MasterPasswordChangeWorking ||
        state is MasterPasswordRecoveryWorking) {
      return;
    }
    if (newMasterPassword != confirmation) {
      emit(const MasterPasswordRecoveryConfirmationMismatch());
      return;
    }
    final RecoverMasterPassword? recoverMasterPassword = _recoverMasterPassword;
    if (recoverMasterPassword == null ||
        _sessionController.state is! UnlockedSession) {
      emit(const MasterPasswordRecoveryUnavailable());
      return;
    }

    emit(const MasterPasswordRecoveryWorking());
    SessionActivityLease? activityLease;
    try {
      activityLease = _sessionController.beginActivity(
        SessionActivity.passwordRecovery,
      );
      final Result<RecoveredMasterPassword, RecoverMasterPasswordFailure>
      result = await recoverMasterPassword(
        newMasterPassword: newMasterPassword,
        activityLease: activityLease,
      );
      emit(switch (result) {
        Success<RecoveredMasterPassword, RecoverMasterPasswordFailure>() =>
          const MasterPasswordRecoveryCompleted(),
        Failure<RecoveredMasterPassword, RecoverMasterPasswordFailure>(
          :final RecoverMasterPasswordFailure failure,
        ) =>
          switch (failure) {
            RecoverMasterPasswordFailure.invalidNewMasterPassword =>
              const MasterPasswordRecoveryInvalidNew(),
            RecoverMasterPasswordFailure.weakNewMasterPassword =>
              const MasterPasswordRecoveryWeakNew(),
            RecoverMasterPasswordFailure.recoveryUnavailable =>
              const MasterPasswordRecoveryUnavailable(),
            RecoverMasterPasswordFailure.biometricCancelled =>
              const MasterPasswordRecoveryBiometricCancelled(),
            RecoverMasterPasswordFailure.biometricUnavailable =>
              const MasterPasswordRecoveryBiometricUnavailable(),
          },
      });
    } on Object {
      emit(const MasterPasswordRecoveryFault());
    } finally {
      activityLease?.complete();
    }
  }

  Future<bool> _recordRecoveryFailure() async {
    final MasterPasswordRecoveryGate? recoveryGate = _recoveryGate;
    final HasConfiguredBiometricRecovery? hasConfigured =
        _hasConfiguredBiometricRecovery;
    if (recoveryGate == null || hasConfigured == null) {
      return false;
    }
    final bool biometricConfigured = await hasConfigured();
    final MasterPasswordRecoveryState recoveryState = await recoveryGate
        .recordChangePasswordFailure(biometricConfigured: biometricConfigured);
    return recoveryState is MasterPasswordRecoveryAvailable;
  }

  Future<bool> _currentRecoveryAvailability() async {
    final MasterPasswordRecoveryGate? recoveryGate = _recoveryGate;
    final HasConfiguredBiometricRecovery? hasConfigured =
        _hasConfiguredBiometricRecovery;
    if (recoveryGate == null || hasConfigured == null) {
      return false;
    }
    final MasterPasswordRecoveryState recoveryState = await recoveryGate
        .currentState(biometricConfigured: await hasConfigured());
    return recoveryState is MasterPasswordRecoveryAvailable;
  }
}
