import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/authenticated_wipe_vault.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/shared/result.dart';

/// UI state for the normal current-password-authenticated wipe path.
sealed class AuthenticatedWipeViewState {
  /// Creates an authenticated-wipe state.
  const AuthenticatedWipeViewState();
}

/// The destructive confirmation form is ready.
final class AuthenticatedWipeReady extends AuthenticatedWipeViewState {
  /// Creates the ready state.
  const AuthenticatedWipeReady();
}

/// Password verification or verified deletion is running.
final class AuthenticatedWipeWorking extends AuthenticatedWipeViewState {
  /// Creates the working state.
  const AuthenticatedWipeWorking();
}

/// The current master password was rejected before deletion began.
final class AuthenticatedWipeInvalidPassword
    extends AuthenticatedWipeViewState {
  /// Creates the invalid-password state.
  const AuthenticatedWipeInvalidPassword();
}

/// Every wipe target was verified absent.
final class AuthenticatedWipeCompleted extends AuthenticatedWipeViewState {
  /// Creates the completed state.
  const AuthenticatedWipeCompleted();
}

/// A system failure left setup blocked for safe retry.
final class AuthenticatedWipeFault extends AuthenticatedWipeViewState {
  /// Creates the fault state.
  const AuthenticatedWipeFault();
}

/// Coordinates the settings-page normal wipe form.
final class AuthenticatedWipeCubit extends Cubit<AuthenticatedWipeViewState> {
  /// Creates the coordinator around the authenticated wipe use case.
  AuthenticatedWipeCubit(this._wipeVault)
    : super(const AuthenticatedWipeReady());

  final AuthenticatedWipeVault _wipeVault;

  /// Restores a failed form for a fresh explicit attempt.
  void reset() {
    if (state is! AuthenticatedWipeWorking) {
      emit(const AuthenticatedWipeReady());
    }
  }

  /// Verifies [masterPassword] before any destructive state transition.
  Future<void> submit(String masterPassword) async {
    if (state is AuthenticatedWipeWorking) return;
    emit(const AuthenticatedWipeWorking());
    try {
      final Result<WipedVault, AuthenticatedWipeFailure> result =
          await _wipeVault(masterPassword);
      emit(switch (result) {
        Success<WipedVault, AuthenticatedWipeFailure>() =>
          const AuthenticatedWipeCompleted(),
        Failure<WipedVault, AuthenticatedWipeFailure>() =>
          const AuthenticatedWipeInvalidPassword(),
      });
    } on Object {
      emit(const AuthenticatedWipeFault());
    }
  }
}
