import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';

/// Global session source of truth for route access and authentication state.
final class SessionController extends ChangeNotifier {
  /// Creates a session controller with an explicit bootstrap [initialState].
  SessionController({
    SessionState initialState = const VaultNotCreatedSession(),
  }) : _state = initialState;

  final StreamController<SessionState> _states =
      StreamController<SessionState>.broadcast(sync: true);
  SessionState _state;

  /// The current immutable session state.
  SessionState get state => _state;

  /// The sole derived route state consumed by GoRouter.
  SessionRouteState get routeState => _state.routeState;

  /// Emits state changes for UI projections such as AuthCubit.
  Stream<SessionState> get states => _states.stream;

  /// Records that a vault was created and requires a cold-start unlock.
  void markVaultCreated() {
    _transition(const LockedSession(reason: LockReason.coldStart));
  }

  /// Records a successful authentication without reinterpreting its strength.
  void unlock(AuthStrength authStrength) {
    if (authStrength == AuthStrength.none) {
      throw ArgumentError.value(
        authStrength,
        'authStrength',
        'An unlocked session requires successful authentication.',
      );
    }
    _transition(UnlockedSession(authStrength: authStrength));
  }

  /// Locks the current vault session for [reason].
  void lock(LockReason reason) {
    _transition(LockedSession(reason: reason));
  }

  /// Releases stream resources owned by this controller.
  @override
  void dispose() {
    _states.close();
    super.dispose();
  }

  void _transition(SessionState nextState) {
    _state = nextState;
    _states.add(nextState);
    notifyListeners();
  }
}
