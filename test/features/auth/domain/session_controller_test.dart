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

      controller.completeMasterPasswordStepUp();

      expect(
        controller.state,
        const UnlockedSession(authStrength: AuthStrength.masterPassword),
      );
      expect(controller.requiresMasterPasswordStepUp, isFalse);
      expect(controller.hasActiveIdleTimer, isTrue);
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
