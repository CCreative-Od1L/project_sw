import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/unlock_vault.dart';
import 'package:project_sw/shared/result.dart';

/// UI state for a master-password unlock attempt.
sealed class UnlockViewState {
  /// Creates unlock view state values.
  const UnlockViewState();
}

/// The form accepts a master password.
final class UnlockReady extends UnlockViewState {
  /// Creates the ready state.
  const UnlockReady();
}

/// A KDF and header-unwrapping operation is in flight.
final class Unlocking extends UnlockViewState {
  /// Creates the loading state.
  const Unlocking();
}

/// The supplied password is an expected, recoverable form failure.
final class UnlockInvalidPassword extends UnlockViewState {
  /// Creates the expected invalid-password state.
  const UnlockInvalidPassword();
}

/// A non-password system failure requires fault presentation.
final class UnlockFault extends UnlockViewState {
  /// Creates a fault state with a safe generic message.
  const UnlockFault();
}

/// Owns only unlock-form interaction state, not the session state machine.
final class UnlockCubit extends Cubit<UnlockViewState> {
  /// Creates a form coordinator around the use case and session source.
  UnlockCubit(this._unlockVault, this._sessionController)
    : super(const UnlockReady());

  final UnlockVault _unlockVault;
  final SessionController _sessionController;

  /// Submits a master password and updates the session only after success.
  Future<void> submit(String masterPassword) async {
    if (state is Unlocking) {
      return;
    }
    emit(const Unlocking());
    try {
      final Result<UnlockedVault, UnlockFailure> result = await _unlockVault(
        masterPassword,
      );
      switch (result) {
        case Success<UnlockedVault, UnlockFailure>():
          _sessionController.unlock(AuthStrength.masterPassword);
          emit(const UnlockReady());
        case Failure<UnlockedVault, UnlockFailure>():
          emit(const UnlockInvalidPassword());
      }
    } on Object {
      emit(const UnlockFault());
    }
  }
}
