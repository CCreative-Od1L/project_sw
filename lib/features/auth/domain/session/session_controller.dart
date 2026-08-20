import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';

/// Global session source of truth for route access and authentication state.
final class SessionController extends ChangeNotifier {
  /// Creates a session controller with an explicit bootstrap [initialState].
  SessionController({
    SessionState initialState = const VaultNotCreatedSession(),
    this.secretCleaner,
    this.idleTimeout = const Duration(minutes: 5),
    this.timerFactory = createDartSessionTimer,
  }) : _state = initialState,
       _secretCleaners = <SessionSecretCleaner>[?secretCleaner] {
    if (_state is UnlockedSession) {
      _startIdleTimer();
    }
  }

  final StreamController<SessionState> _states =
      StreamController<SessionState>.broadcast(sync: true);
  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast(sync: true);
  final List<SessionSecretCleaner> _secretCleaners;
  SessionState _state;
  SessionTimer? _idleTimer;
  LockSuppressionReason? _lockSuppressionReason;

  /// Collaborator that clears sensitive unlocked state before routing to lock.
  final SessionSecretCleaner? secretCleaner;

  /// Fixed foreground inactivity window for this application session.
  final Duration idleTimeout;

  /// Injectable timer implementation used by the session source of truth.
  final SessionTimerFactory timerFactory;

  /// The current immutable session state.
  SessionState get state => _state;

  /// The sole derived route state consumed by GoRouter.
  SessionRouteState get routeState => _state.routeState;

  /// Emits state changes for UI projections such as AuthCubit.
  Stream<SessionState> get states => _states.stream;

  /// Emits domain events after they enter the session source of truth.
  Stream<SessionEvent> get events => _events.stream;

  /// Whether an unlocked session currently owns an idle timer.
  bool get hasActiveIdleTimer => _idleTimer?.isActive ?? false;

  /// Whether the foreground idle timeout is temporarily suppressed.
  bool get isIdleTimeoutSuppressed => _lockSuppressionReason != null;

  /// Whether the current unlocked session needs a master-password step-up.
  bool get requiresMasterPasswordStepUp => switch (_state) {
    UnlockedSession(:final AuthStrength authStrength) =>
      authStrength != AuthStrength.masterPassword,
    _ => false,
  };

  /// Registers a page-local cleaner that must run before a lock transition.
  void registerSecretCleaner(SessionSecretCleaner cleaner) {
    if (!_secretCleaners.contains(cleaner)) {
      _secretCleaners.add(cleaner);
    }
  }

  /// Removes a page-local cleaner after its route has been disposed.
  void unregisterSecretCleaner(SessionSecretCleaner cleaner) {
    _secretCleaners.remove(cleaner);
  }

  /// Records that a vault was created and requires a cold-start unlock.
  void markVaultCreated() {
    _cancelIdleTimer();
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
    _cancelIdleTimer();
    _lockSuppressionReason = null;
    _transition(UnlockedSession(authStrength: authStrength));
    _startIdleTimer();
  }

  /// Temporarily suppresses the idle timeout for an in-progress operation.
  void beginIdleTimeoutSuppression(LockSuppressionReason reason) {
    if (_state is! UnlockedSession) {
      throw StateError('Only an unlocked session can suppress idle timeout.');
    }
    if (_lockSuppressionReason != null && _lockSuppressionReason != reason) {
      throw StateError('Another lock suppression is already active.');
    }
    _lockSuppressionReason = reason;
    _cancelIdleTimer();
  }

  /// Ends an idle-timeout suppression and starts a fresh inactivity window.
  void endIdleTimeoutSuppression(LockSuppressionReason reason) {
    if (_lockSuppressionReason != reason) {
      return;
    }
    _lockSuppressionReason = null;
    _startIdleTimer();
  }

  /// Locks the current vault session for [reason].
  void lock(LockReason reason) {
    _lockSuppressionReason = null;
    if (_state is LockedSession) {
      final LockedSession current = _state as LockedSession;
      if (current.reason == reason) {
        return;
      }
      _cancelIdleTimer();
      _transition(LockedSession(reason: reason));
      return;
    }
    _cancelIdleTimer();
    for (final SessionSecretCleaner cleaner in _secretCleaners) {
      cleaner.clearUnlockedSession();
    }
    _transition(LockedSession(reason: reason));
  }

  /// Clears unlocked state and blocks every route while a wipe is in progress.
  void beginWipe() {
    lock(LockReason.wipeStarted);
  }

  /// Publishes first-run setup only after durable wipe verification succeeds.
  void completeWipe() {
    final SessionState current = _state;
    if (current is! LockedSession || current.reason != LockReason.wipeStarted) {
      throw StateError('Only an active wipe can publish first-run setup.');
    }
    _cancelIdleTimer();
    _lockSuppressionReason = null;
    _transition(const VaultNotCreatedSession());
  }

  /// Upgrades an unlocked biometric session to master-password strength.
  ///
  /// The password verification itself belongs to the authentication use case;
  /// this method only applies the already-verified state transition.
  void completeMasterPasswordStepUp() {
    final SessionState current = _state;
    if (current is! UnlockedSession) {
      throw StateError('A locked session cannot complete a step-up.');
    }
    if (current.authStrength == AuthStrength.masterPassword) {
      return;
    }
    _transition(
      const UnlockedSession(authStrength: AuthStrength.masterPassword),
    );
  }

  /// Sends a domain event through the session state machine.
  void handle(SessionEvent event) {
    _events.add(event);
    switch (event) {
      case SessionEvent.appForegrounded:
        return;
      case SessionEvent.appBackgrounded:
        lock(LockReason.backgroundOrTimeout);
      case SessionEvent.userInteractionObserved:
        _resetIdleTimer();
      case SessionEvent.idleTimeoutElapsed:
        if (_lockSuppressionReason != null) {
          _startIdleTimer();
          return;
        }
        lock(LockReason.backgroundOrTimeout);
      case SessionEvent.biometricInvalidated:
        lock(LockReason.biometricInvalidated);
    }
  }

  /// Releases stream resources owned by this controller.
  @override
  void dispose() {
    _cancelIdleTimer();
    _events.close();
    _states.close();
    super.dispose();
  }

  void _resetIdleTimer() {
    if (_state is! UnlockedSession) {
      return;
    }
    _cancelIdleTimer();
    _startIdleTimer();
  }

  void _startIdleTimer() {
    if (_state is! UnlockedSession) {
      return;
    }
    _idleTimer = timerFactory(idleTimeout, () {
      _idleTimer = null;
      handle(SessionEvent.idleTimeoutElapsed);
    });
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _transition(SessionState nextState) {
    _state = nextState;
    _states.add(nextState);
    notifyListeners();
  }
}
