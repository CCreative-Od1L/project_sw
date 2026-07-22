import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';

/// Immutable UI projection of state owned by [SessionController].
final class AuthViewState {
  /// Creates an authentication UI state from already-derived session facts.
  const AuthViewState({
    required this.routeState,
    required this.isLocked,
    required this.canUseBiometric,
    required this.authStrength,
    this.lockReason,
  });

  /// Produces a UI projection without introducing state-machine rules.
  factory AuthViewState.fromSessionState(SessionState sessionState) {
    return switch (sessionState) {
      VaultNotCreatedSession() => const AuthViewState(
        routeState: SessionRouteState.setup,
        isLocked: true,
        canUseBiometric: false,
        authStrength: AuthStrength.none,
      ),
      LockedSession(:final LockReason reason, :final bool canUseBiometric) =>
        AuthViewState(
          routeState: SessionRouteState.unlock,
          isLocked: true,
          canUseBiometric: canUseBiometric,
          authStrength: AuthStrength.none,
          lockReason: reason,
        ),
      UnlockedSession(:final AuthStrength authStrength) => AuthViewState(
        routeState: SessionRouteState.home,
        isLocked: false,
        canUseBiometric: false,
        authStrength: authStrength,
      ),
    };
  }

  /// The route state projected from the session source of truth.
  final SessionRouteState routeState;

  /// Whether the UI should treat the vault as inaccessible.
  final bool isLocked;

  /// Whether the session source of truth permits biometric presentation.
  final bool canUseBiometric;

  /// The already-established authentication strength.
  final AuthStrength authStrength;

  /// The lock cause when [isLocked] is true for an existing vault.
  final LockReason? lockReason;
}

/// Cubit that projects, but never owns, global session state.
final class AuthCubit extends Cubit<AuthViewState> {
  /// Starts projecting [sessionController] state for presentation consumers.
  AuthCubit(SessionController sessionController)
    : _sessionController = sessionController,
      super(AuthViewState.fromSessionState(sessionController.state)) {
    _subscription = _sessionController.states.listen((
      SessionState sessionState,
    ) {
      emit(AuthViewState.fromSessionState(sessionState));
    });
  }

  final SessionController _sessionController;
  late final StreamSubscription<SessionState> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await super.close();
  }
}
