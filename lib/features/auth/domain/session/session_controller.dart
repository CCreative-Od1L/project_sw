import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';

/// Error raised when a locked session interrupts an in-flight activity.
final class SessionActivityInterrupted implements Exception {
  /// Creates a session activity interruption error.
  const SessionActivityInterrupted(this.activity);

  /// Activity that no longer owns the unlocked session.
  final SessionActivity activity;

  @override
  String toString() => 'SessionActivityInterrupted: $activity';
}

/// Unique ownership token for one unlocked foreground workflow.
final class SessionActivityLease implements SessionActivityGuard {
  SessionActivityLease._(this._owner, this.activity);

  final SessionController _owner;
  final List<void Function()> _interruptionListeners = <void Function()>[];

  /// Workflow represented by this lease.
  final SessionActivity activity;

  var _ended = false;
  var _interrupted = false;

  /// Whether this exact workflow still owns the current unlocked session.
  bool get isActive => !_ended && _owner._owns(this);

  /// Throws when lock or replacement has invalidated this workflow.
  @override
  void ensureActive() {
    if (!isActive) {
      throw SessionActivityInterrupted(activity);
    }
  }

  /// Registers synchronous notification used to cancel pending external I/O.
  void onInterrupted(void Function() listener) {
    if (_ended) {
      if (_interrupted) {
        try {
          listener();
        } on Object {
          // Locking must remain fail-closed when cancellation cleanup fails.
        }
      }
      return;
    }
    _interruptionListeners.add(listener);
  }

  /// Completes only this workflow; stale leases cannot affect newer activity.
  void complete() => _owner._completeActivity(this);

  /// Cancels this workflow without allowing it to restart the idle timer.
  void cancel() => _owner._cancelActivity(this);

  void _markCompleted() {
    _ended = true;
    _interruptionListeners.clear();
  }

  void _markInterrupted() {
    if (_ended) {
      return;
    }
    _ended = true;
    _interrupted = true;
    final List<void Function()> listeners = List<void Function()>.of(
      _interruptionListeners,
    );
    _interruptionListeners.clear();
    for (final void Function() listener in listeners) {
      try {
        listener();
      } on Object {
        // Locking must remain fail-closed even when cancellation cleanup fails.
      }
    }
  }
}

/// Unique ownership token for one master-password step-up challenge.
final class MasterPasswordStepUpChallenge implements SessionActivityGuard {
  MasterPasswordStepUpChallenge._(this._owner);

  final SessionController _owner;
  final List<void Function()> _invalidationListeners = <void Function()>[];
  var _ended = false;
  var _invalidated = false;

  /// Whether this exact challenge still belongs to the unlocked session.
  bool get isActive => !_ended && _owner._ownsStepUpChallenge(this);

  /// Registers synchronous notification when locking invalidates the challenge.
  void onInvalidated(void Function() listener) {
    if (_ended) {
      if (_invalidated) {
        _callSafely(listener);
      }
      return;
    }
    _invalidationListeners.add(listener);
  }

  /// Applies a verified master password only to the owning session.
  bool complete() => _owner._completeStepUpChallenge(this);

  /// Rejects sensitive work after this challenge loses its owning session.
  @override
  void ensureActive() {
    if (!isActive) {
      throw const SessionActivityInterrupted(SessionActivity.passwordChange);
    }
  }

  /// Releases an unsuccessful or abandoned challenge without upgrading.
  void cancel() => _owner._cancelStepUpChallenge(this);

  void _markCompleted() {
    _ended = true;
    _invalidationListeners.clear();
  }

  void _markInvalidated() {
    if (_ended) {
      return;
    }
    _ended = true;
    _invalidated = true;
    final List<void Function()> listeners = List<void Function()>.of(
      _invalidationListeners,
    );
    _invalidationListeners.clear();
    for (final void Function() listener in listeners) {
      _callSafely(listener);
    }
  }

  static void _callSafely(void Function() listener) {
    try {
      listener();
    } on Object {
      // Locking must remain fail-closed when UI invalidation cleanup fails.
    }
  }
}

/// Global session source of truth for route access and authentication state.
final class SessionController extends ChangeNotifier {
  /// Creates a session controller with an explicit bootstrap [initialState].
  SessionController({
    SessionState initialState = const VaultNotCreatedSession(),
    this.secretCleaner,
    this.idleTimeout = const Duration(minutes: 5),
    this.timerFactory = createDartSessionTimer,
  }) : _state = _validateInitialState(initialState),
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
  SessionActivityLease? _activityLease;
  MasterPasswordStepUpChallenge? _stepUpChallenge;
  final List<SessionState> _pendingStateTransitions = <SessionState>[];
  var _isPublishingState = false;
  var _isLocking = false;

  /// Collaborator that clears sensitive unlocked state before routing to lock.
  final SessionSecretCleaner? secretCleaner;

  /// Fixed foreground inactivity window for this application session.
  final Duration idleTimeout;

  /// Injectable timer implementation used by the session source of truth.
  final SessionTimerFactory timerFactory;

  static SessionState _validateInitialState(SessionState initialState) {
    if (initialState is UnlockedSession &&
        initialState.activity != SessionActivity.none) {
      throw ArgumentError.value(
        initialState,
        'initialState',
        'An active session must be established through beginActivity.',
      );
    }
    return initialState;
  }

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
  bool get isIdleTimeoutSuppressed =>
      _state is UnlockedSession &&
      (_state as UnlockedSession).activity != SessionActivity.none;

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
    if (_state is! VaultNotCreatedSession) {
      throw StateError('A vault can only be created from first-run setup.');
    }
    _cancelIdleTimer();
    _transition(const LockedSession(reason: LockReason.coldStart));
  }

  /// Records a successful authentication without reinterpreting its strength.
  void unlock(AuthStrength authStrength) {
    if (_isLocking) {
      throw StateError('A session cannot unlock while locking.');
    }
    if (authStrength == AuthStrength.none) {
      throw ArgumentError.value(
        authStrength,
        'authStrength',
        'An unlocked session requires successful authentication.',
      );
    }
    final SessionState current = _state;
    if (current is! LockedSession) {
      throw StateError('Only an existing locked vault can be unlocked.');
    }
    if (current.reason == LockReason.wipeStarted ||
        (authStrength == AuthStrength.biometric && !current.canUseBiometric)) {
      throw StateError('The current lock reason does not permit this unlock.');
    }
    _cancelIdleTimer();
    _transition(UnlockedSession(authStrength: authStrength));
    _startIdleTimer();
  }

  /// Starts an unlocked workflow and suspends foreground idle timeout.
  SessionActivityLease beginActivity(SessionActivity activity) {
    if (activity == SessionActivity.none) {
      throw ArgumentError.value(
        activity,
        'activity',
        'An active workflow requires a concrete activity.',
      );
    }
    if (_isLocking) {
      throw StateError('A session activity cannot start while locking.');
    }
    final SessionState current = _state;
    if (current is! UnlockedSession) {
      throw StateError('Only an unlocked session can start an activity.');
    }
    if (current.activity != SessionActivity.none) {
      throw StateError('Another session activity is already active.');
    }
    if (_stepUpChallenge != null) {
      throw StateError('A step-up challenge is already active.');
    }
    final SessionActivityLease lease = SessionActivityLease._(this, activity);
    _activityLease = lease;
    _cancelIdleTimer();
    _transition(
      UnlockedSession(authStrength: current.authStrength, activity: activity),
    );
    return lease;
  }

  /// Starts one master-password challenge bound to the current session.
  MasterPasswordStepUpChallenge beginMasterPasswordStepUp() {
    if (_isLocking) {
      throw StateError('A step-up challenge cannot start while locking.');
    }
    final SessionState current = _state;
    if (current is! UnlockedSession ||
        current.authStrength == AuthStrength.masterPassword) {
      throw StateError('The current session does not require a step-up.');
    }
    if (current.activity != SessionActivity.none) {
      throw StateError('A session activity cannot overlap a step-up.');
    }
    if (_stepUpChallenge != null) {
      throw StateError('Another step-up challenge is already active.');
    }
    final MasterPasswordStepUpChallenge challenge =
        MasterPasswordStepUpChallenge._(this);
    _stepUpChallenge = challenge;
    return challenge;
  }

  /// Locks the current vault session for [reason].
  void lock(LockReason reason) {
    if (_state is VaultNotCreatedSession) {
      return;
    }
    if (_state is LockedSession) {
      final LockedSession current = _state as LockedSession;
      if (current.reason == LockReason.wipeStarted ||
          (current.reason == LockReason.biometricInvalidated &&
              reason != LockReason.wipeStarted) ||
          (reason != LockReason.wipeStarted &&
              reason != LockReason.biometricInvalidated)) {
        return;
      }
      _isLocking = true;
      _cancelIdleTimer();
      _transition(LockedSession(reason: reason));
      return;
    }
    _isLocking = true;
    try {
      _invalidateStepUpChallenge();
      _interruptActivity();
      _cancelIdleTimer();
      _clearSessionSecrets();
      _transition(LockedSession(reason: reason));
    } on Object {
      _isLocking = false;
      rethrow;
    }
  }

  /// Clears unlocked state and blocks every route while a wipe is in progress.
  void beginWipe() {
    if (_state is VaultNotCreatedSession) {
      throw StateError('A vault must exist before a wipe can begin.');
    }
    lock(LockReason.wipeStarted);
  }

  /// Publishes first-run setup only after durable wipe verification succeeds.
  void completeWipe() {
    final SessionState current = _state;
    if (current is! LockedSession || current.reason != LockReason.wipeStarted) {
      throw StateError('Only an active wipe can publish first-run setup.');
    }
    _cancelIdleTimer();
    _transition(const VaultNotCreatedSession());
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
        if (isIdleTimeoutSuppressed) {
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
    _invalidateStepUpChallenge();
    _interruptActivity();
    _cancelIdleTimer();
    if (_state is UnlockedSession) {
      _clearSessionSecrets();
    }
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
    final SessionState current = _state;
    if (current is! UnlockedSession ||
        current.activity != SessionActivity.none) {
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

  void _clearSessionSecrets() {
    for (final SessionSecretCleaner cleaner in _secretCleaners) {
      try {
        cleaner.clearUnlockedSession();
      } on Object {
        // Lock and disposal remain fail-closed when cleanup is faulty.
      }
    }
  }

  bool _owns(SessionActivityLease lease) {
    final SessionState current = _state;
    return identical(_activityLease, lease) &&
        current is UnlockedSession &&
        current.activity == lease.activity;
  }

  void _completeActivity(SessionActivityLease lease) {
    if (!_owns(lease)) {
      lease._markInterrupted();
      return;
    }
    final UnlockedSession current = _state as UnlockedSession;
    _activityLease = null;
    lease._markCompleted();
    _transition(UnlockedSession(authStrength: current.authStrength));
    _startIdleTimer();
  }

  void _cancelActivity(SessionActivityLease lease) {
    if (!_owns(lease)) {
      lease._markInterrupted();
      return;
    }
    final UnlockedSession current = _state as UnlockedSession;
    _activityLease = null;
    lease._markInterrupted();
    _transition(UnlockedSession(authStrength: current.authStrength));
    _startIdleTimer();
  }

  void _interruptActivity() {
    final SessionActivityLease? lease = _activityLease;
    _activityLease = null;
    lease?._markInterrupted();
  }

  bool _ownsStepUpChallenge(MasterPasswordStepUpChallenge challenge) {
    final SessionState current = _state;
    return identical(_stepUpChallenge, challenge) &&
        current is UnlockedSession &&
        current.authStrength != AuthStrength.masterPassword;
  }

  bool _completeStepUpChallenge(MasterPasswordStepUpChallenge challenge) {
    if (!_ownsStepUpChallenge(challenge)) {
      challenge._markInvalidated();
      return false;
    }
    final UnlockedSession current = _state as UnlockedSession;
    _stepUpChallenge = null;
    challenge._markCompleted();
    _transition(
      UnlockedSession(
        authStrength: AuthStrength.masterPassword,
        activity: current.activity,
      ),
    );
    return switch (_state) {
      UnlockedSession(authStrength: AuthStrength.masterPassword) => true,
      _ => false,
    };
  }

  void _cancelStepUpChallenge(MasterPasswordStepUpChallenge challenge) {
    if (!identical(_stepUpChallenge, challenge)) {
      challenge._markInvalidated();
      return;
    }
    _stepUpChallenge = null;
    challenge._markCompleted();
  }

  void _invalidateStepUpChallenge() {
    final MasterPasswordStepUpChallenge? challenge = _stepUpChallenge;
    _stepUpChallenge = null;
    challenge?._markInvalidated();
  }

  void _transition(SessionState nextState) {
    _pendingStateTransitions.add(nextState);
    if (_isPublishingState) {
      return;
    }
    _isPublishingState = true;
    try {
      while (_pendingStateTransitions.isNotEmpty) {
        final SessionState pending = _pendingStateTransitions.removeAt(0);
        _state = pending;
        _states.add(pending);
        notifyListeners();
      }
    } finally {
      _isPublishingState = false;
      if (_state is LockedSession && _pendingStateTransitions.isEmpty) {
        _isLocking = false;
      }
    }
  }
}
