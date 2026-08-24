import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';

void main() {
  group('SessionController', () {
    test('starts in a cold-start no-vault state', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      expect(controller.state, isA<VaultNotCreatedSession>());
      expect(
        (controller.state as VaultNotCreatedSession).startReason,
        SessionStartReason.coldStart,
      );
      expect(controller.routeState, SessionRouteState.setup);
    });

    test('moves created vaults into cold-start locked state', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      controller.markVaultCreated();

      expect(controller.state, isA<LockedSession>());
      expect((controller.state as LockedSession).reason, LockReason.coldStart);
      expect(controller.routeState, SessionRouteState.unlock);
      expect((controller.state as LockedSession).canUseBiometric, isTrue);
    });

    test('preserves authentication strength until the next lock', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      controller.markVaultCreated();
      controller.unlock(AuthStrength.masterPassword);

      expect(controller.state, isA<UnlockedSession>());
      expect(
        (controller.state as UnlockedSession).authStrength,
        AuthStrength.masterPassword,
      );
      expect(controller.routeState, SessionRouteState.home);

      controller.lock(LockReason.backgroundOrTimeout);

      expect(controller.state, isA<LockedSession>());
      expect((controller.state as LockedSession).canUseBiometric, isTrue);
      expect(controller.routeState, SessionRouteState.unlock);
    });

    test('upgrades a biometric session through a master-password step-up', () {
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
        timerFactory: (Duration duration, void Function() callback) =>
            FakeSessionTimer(callback),
      );
      addTearDown(controller.dispose);

      expect(controller.requiresMasterPasswordStepUp, isTrue);

      controller.beginActivity(SessionActivity.passwordRecovery);
      controller.completeMasterPasswordStepUp();

      final UnlockedSession steppedUp = controller.state as UnlockedSession;
      expect(steppedUp.authStrength, AuthStrength.masterPassword);
      expect(steppedUp.activity, SessionActivity.passwordRecovery);
      expect(controller.requiresMasterPasswordStepUp, isFalse);
      expect(controller.hasActiveIdleTimer, isFalse);
    });

    test('records biometric invalidation even when already locked', () {
      final SessionController controller = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      addTearDown(controller.dispose);

      controller.handle(SessionEvent.biometricInvalidated);

      expect(controller.state, isA<LockedSession>());
      expect(
        (controller.state as LockedSession).reason,
        LockReason.biometricInvalidated,
      );
    });

    test('rejects an unlock without successful authentication', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      expect(() => controller.unlock(AuthStrength.none), throwsArgumentError);
    });

    test('owns and resets a controllable idle timer while unlocked', () {
      final List<FakeSessionTimer> timers = <FakeSessionTimer>[];
      final SessionController controller = SessionController(
        timerFactory: (Duration duration, void Function() callback) {
          final FakeSessionTimer timer = FakeSessionTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);

      controller.markVaultCreated();
      controller.unlock(AuthStrength.masterPassword);
      expect(controller.hasActiveIdleTimer, isTrue);
      expect(timers, hasLength(1));

      final FakeSessionTimer firstTimer = timers.single;
      controller.handle(SessionEvent.userInteractionObserved);

      expect(firstTimer.isActive, isFalse);
      expect(timers, hasLength(2));
      expect(controller.hasActiveIdleTimer, isTrue);

      timers.last.fire();
      expect(controller.state, isA<LockedSession>());
      expect(controller.hasActiveIdleTimer, isFalse);
    });

    test('cleans unlocked state before an idempotent background lock', () {
      final RecordingCleaner cleaner = RecordingCleaner();
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
        secretCleaner: cleaner,
        timerFactory: (Duration duration, void Function() callback) =>
            FakeSessionTimer(callback),
      );
      addTearDown(controller.dispose);

      controller.handle(SessionEvent.appBackgrounded);
      controller.handle(SessionEvent.appBackgrounded);

      expect(cleaner.clearCount, 1);
      expect(controller.state, isA<LockedSession>());
      expect(controller.hasActiveIdleTimer, isFalse);
    });

    test('locked sessions do not start an idle timer on interaction', () {
      final List<FakeSessionTimer> timers = <FakeSessionTimer>[];
      final SessionController controller = SessionController(
        timerFactory: (Duration duration, void Function() callback) {
          final FakeSessionTimer timer = FakeSessionTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);

      controller.handle(SessionEvent.userInteractionObserved);

      expect(timers, isEmpty);
      expect(controller.hasActiveIdleTimer, isFalse);
    });

    test('publishes migration activity and suspends the idle timer', () {
      final List<FakeSessionTimer> timers = <FakeSessionTimer>[];
      final SessionController controller = SessionController(
        timerFactory: (Duration duration, void Function() callback) {
          final FakeSessionTimer timer = FakeSessionTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);

      controller.markVaultCreated();
      controller.unlock(AuthStrength.masterPassword);
      controller.beginActivity(SessionActivity.migrationSending);

      final UnlockedSession active = controller.state as UnlockedSession;
      expect(active.activity, SessionActivity.migrationSending);
      expect(controller.isIdleTimeoutSuppressed, isTrue);
      expect(controller.hasActiveIdleTimer, isFalse);

      controller.handle(SessionEvent.userInteractionObserved);

      expect(controller.hasActiveIdleTimer, isFalse);
    });

    test(
      'activity ignores idle timeout but not an immediate background lock',
      () {
        final SessionController controller = SessionController(
          initialState: const UnlockedSession(
            authStrength: AuthStrength.masterPassword,
          ),
          timerFactory: (Duration duration, void Function() callback) =>
              FakeSessionTimer(callback),
        );
        addTearDown(controller.dispose);

        final SessionActivityLease lease = controller.beginActivity(
          SessionActivity.migrationSending,
        );
        var interruptionCount = 0;
        lease.onInterrupted(() => interruptionCount++);
        controller.handle(SessionEvent.idleTimeoutElapsed);

        expect(controller.state, isA<UnlockedSession>());
        expect(
          (controller.state as UnlockedSession).activity,
          SessionActivity.migrationSending,
        );
        expect(controller.hasActiveIdleTimer, isFalse);

        controller.handle(SessionEvent.appBackgrounded);
        lease.complete();

        expect(controller.state, isA<LockedSession>());
        expect(controller.isIdleTimeoutSuppressed, isFalse);
        expect(interruptionCount, 1);
      },
    );

    test('returns to idle activity with a fresh timeout window', () {
      final List<FakeSessionTimer> timers = <FakeSessionTimer>[];
      final SessionController controller = SessionController(
        timerFactory: (Duration duration, void Function() callback) {
          final FakeSessionTimer timer = FakeSessionTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);

      controller.markVaultCreated();
      controller.unlock(AuthStrength.masterPassword);
      final SessionActivityLease lease = controller.beginActivity(
        SessionActivity.migrationReceiving,
      );
      lease.complete();

      final UnlockedSession idle = controller.state as UnlockedSession;
      expect(idle.activity, SessionActivity.none);
      expect(controller.isIdleTimeoutSuppressed, isFalse);
      expect(controller.hasActiveIdleTimer, isTrue);
      expect(timers, hasLength(2));
    });

    test('rejects illegal or overlapping activity transitions', () {
      expect(
        () => SessionController(
          initialState: const UnlockedSession(
            authStrength: AuthStrength.masterPassword,
            activity: SessionActivity.migrationSending,
          ),
        ),
        throwsArgumentError,
      );
      final SessionController locked = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      final SessionController active = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      addTearDown(locked.dispose);
      addTearDown(active.dispose);

      expect(
        () => active.beginActivity(SessionActivity.none),
        throwsArgumentError,
      );
      expect(
        () => locked.beginActivity(SessionActivity.migrationSending),
        throwsStateError,
      );

      active.beginActivity(SessionActivity.migrationSending);

      expect(
        () => active.beginActivity(SessionActivity.migrationReceiving),
        throwsStateError,
      );
      expect(
        () => active.beginActivity(SessionActivity.passwordRecovery),
        throwsStateError,
      );
    });

    test('a stale activity lease cannot complete a newer activity', () {
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      addTearDown(controller.dispose);

      final SessionActivityLease stale = controller.beginActivity(
        SessionActivity.migrationSending,
      );
      controller.handle(SessionEvent.appBackgrounded);
      controller.unlock(AuthStrength.masterPassword);
      final SessionActivityLease current = controller.beginActivity(
        SessionActivity.migrationSending,
      );

      stale.complete();

      expect(stale.isActive, isFalse);
      expect(current.isActive, isTrue);
      expect(
        (controller.state as UnlockedSession).activity,
        SessionActivity.migrationSending,
      );
    });

    test('ignores lock events before a vault exists', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      controller.handle(SessionEvent.appBackgrounded);

      expect(controller.state, isA<VaultNotCreatedSession>());
      expect(controller.routeState, SessionRouteState.setup);
    });

    test('does not downgrade wipe or biometric-invalidation locks', () {
      final SessionController wipeController = SessionController(
        initialState: const LockedSession(reason: LockReason.wipeStarted),
      );
      final SessionController biometricController = SessionController(
        initialState: const LockedSession(
          reason: LockReason.biometricInvalidated,
        ),
      );
      addTearDown(wipeController.dispose);
      addTearDown(biometricController.dispose);

      wipeController.handle(SessionEvent.appBackgrounded);
      biometricController.handle(SessionEvent.appBackgrounded);

      expect(
        (wipeController.state as LockedSession).reason,
        LockReason.wipeStarted,
      );
      expect(
        (biometricController.state as LockedSession).reason,
        LockReason.biometricInvalidated,
      );
      expect((wipeController.state as LockedSession).canUseBiometric, isFalse);
      expect(
        (biometricController.state as LockedSession).canUseBiometric,
        isFalse,
      );
    });

    test('rejects unlock transitions that bypass the current lock reason', () {
      final SessionController noVault = SessionController();
      final SessionController wiping = SessionController(
        initialState: const LockedSession(reason: LockReason.wipeStarted),
      );
      final SessionController manual = SessionController(
        initialState: const LockedSession(reason: LockReason.manualLock),
      );
      final SessionController invalidated = SessionController(
        initialState: const LockedSession(
          reason: LockReason.biometricInvalidated,
        ),
      );
      addTearDown(noVault.dispose);
      addTearDown(wiping.dispose);
      addTearDown(manual.dispose);
      addTearDown(invalidated.dispose);

      expect(
        () => noVault.unlock(AuthStrength.masterPassword),
        throwsStateError,
      );
      expect(
        () => wiping.unlock(AuthStrength.masterPassword),
        throwsStateError,
      );
      expect(() => manual.unlock(AuthStrength.biometric), throwsStateError);
      expect(
        () => invalidated.unlock(AuthStrength.biometric),
        throwsStateError,
      );

      invalidated.unlock(AuthStrength.masterPassword);
      expect(invalidated.state, isA<UnlockedSession>());
      expect(
        (invalidated.state as UnlockedSession).authStrength,
        AuthStrength.masterPassword,
      );
    });

    test('allows vault creation only from the first-run state', () {
      final SessionController controller = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      addTearDown(controller.dispose);

      expect(controller.markVaultCreated, throwsStateError);
    });

    test('rejects starting a wipe before a vault exists', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      expect(controller.beginWipe, throwsStateError);
    });
  });
}

final class FakeSessionTimer implements SessionTimer {
  FakeSessionTimer(this._callback);

  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

final class RecordingCleaner implements SessionSecretCleaner {
  var clearCount = 0;

  @override
  void clearUnlockedSession() => clearCount++;
}
