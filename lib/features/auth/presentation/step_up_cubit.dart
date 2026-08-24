import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/shared/result.dart';

/// UI state for a master-password step-up challenge.
sealed class StepUpViewState {
  /// Creates a step-up state.
  const StepUpViewState();
}

/// No step-up request is currently running.
final class StepUpReady extends StepUpViewState {
  /// Creates the ready state.
  const StepUpReady();
}

/// The master-password verifier is running.
final class StepUpVerifying extends StepUpViewState {
  /// Creates the verifying state.
  const StepUpVerifying();
}

/// The supplied password was rejected without changing the session.
final class StepUpInvalidPassword extends StepUpViewState {
  /// Creates the invalid-password state.
  const StepUpInvalidPassword();
}

/// A system failure prevented the step-up from completing.
final class StepUpFault extends StepUpViewState {
  /// Creates the fault state.
  const StepUpFault();
}

/// The session was no longer unlocked when the challenge was requested.
final class StepUpUnavailable extends StepUpViewState {
  /// Creates the unavailable state.
  const StepUpUnavailable();
}

/// Coordinates high-sensitivity master-password upgrades for the session.
final class StepUpCubit extends Cubit<StepUpViewState> {
  /// Creates a step-up coordinator around the session source of truth.
  StepUpCubit(this._verifyMasterPassword, this._sessionController)
    : super(const StepUpReady());

  final VerifyMasterPassword _verifyMasterPassword;
  final SessionController _sessionController;
  MasterPasswordStepUpChallenge? _activeChallenge;

  /// Whether this session currently needs a master-password challenge.
  bool get requiresMasterPassword =>
      _sessionController.requiresMasterPasswordStepUp;

  /// Verifies the password and upgrades the global session on success.
  Future<bool> verify(String masterPassword) async {
    if (!_sessionController.state.routeState.isUnlocked) {
      emit(const StepUpUnavailable());
      return false;
    }
    if (!requiresMasterPassword) {
      return true;
    }
    if (state is StepUpVerifying) {
      return false;
    }
    final MasterPasswordStepUpChallenge challenge;
    try {
      challenge = _sessionController.beginMasterPasswordStepUp();
    } on StateError {
      emit(const StepUpUnavailable());
      return false;
    }
    _activeChallenge = challenge;
    challenge.onInvalidated(() {
      if (!isClosed && identical(_activeChallenge, challenge)) {
        _activeChallenge = null;
        emit(const StepUpUnavailable());
      }
    });
    emit(const StepUpVerifying());
    try {
      final Result<VerifiedMasterPassword, VerifyMasterPasswordFailure> result =
          await _verifyMasterPassword(masterPassword);
      if (!identical(_activeChallenge, challenge) || !challenge.isActive) {
        return false;
      }
      switch (result) {
        case Success<VerifiedMasterPassword, VerifyMasterPasswordFailure>():
          if (!challenge.complete()) {
            _activeChallenge = null;
            emit(const StepUpUnavailable());
            return false;
          }
          _activeChallenge = null;
          emit(const StepUpReady());
          return true;
        case Failure<VerifiedMasterPassword, VerifyMasterPasswordFailure>():
          challenge.cancel();
          _activeChallenge = null;
          emit(const StepUpInvalidPassword());
          return false;
      }
    } on Object {
      if (!identical(_activeChallenge, challenge) || !challenge.isActive) {
        return false;
      }
      challenge.cancel();
      _activeChallenge = null;
      emit(const StepUpFault());
      return false;
    }
  }

  @override
  Future<void> close() async {
    _activeChallenge?.cancel();
    _activeChallenge = null;
    await super.close();
  }
}

extension on SessionRouteState {
  bool get isUnlocked => this == SessionRouteState.home;
}
