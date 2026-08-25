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

    test('rejects an unlocked bootstrap state without authentication', () {
      expect(
        () => SessionController(
          initialState: const UnlockedSession(authStrength: AuthStrength.none),
        ),
        throwsArgumentError,
      );
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

      final MasterPasswordStepUpChallenge challenge = controller
          .beginMasterPasswordStepUp();
      expect(challenge.complete(), isTrue);

      final UnlockedSession steppedUp = controller.state as UnlockedSession;
      expect(steppedUp.authStrength, AuthStrength.masterPassword);
      expect(steppedUp.activity, SessionActivity.none);
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

    test('binds an unlock attempt to the current locked session', () {
      final SessionController controller = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      addTearDown(controller.dispose);

      final SessionUnlockAttempt attempt = controller.beginUnlockAttempt();
      expect(attempt.isActive, isTrue);
      expect(() => controller.beginUnlockAttempt(), throwsStateError);

      controller.handle(SessionEvent.appBackgrounded);

      expect(attempt.isActive, isFalse);
      expect(attempt.ensureActive, throwsA(isA<SessionUnlockInterrupted>()));
      expect(attempt.complete(AuthStrength.masterPassword), isFalse);
      expect(controller.state, isA<LockedSession>());
    });

    test('publishes an unlocked state only when the attempt still owns it', () {
      final SessionController controller = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      addTearDown(controller.dispose);

      final SessionUnlockAttempt attempt = controller.beginUnlockAttempt();

      expect(attempt.complete(AuthStrength.masterPassword), isTrue);
      expect(controller.state, isA<UnlockedSession>());
      expect(
        (controller.state as UnlockedSession).authStrength,
        AuthStrength.masterPassword,
      );
      expect(attempt.isActive, isFalse);
      expect(attempt.complete(AuthStrength.masterPassword), isFalse);
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

    test('does not overlap step-up challenges with session activities', () {
      final SessionController challenging = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      final SessionController active = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      addTearDown(challenging.dispose);
      addTearDown(active.dispose);

      challenging.beginMasterPasswordStepUp();
      active.beginActivity(SessionActivity.migrationSending);

      expect(
        () => challenging.beginActivity(SessionActivity.migrationSending),
        throwsStateError,
      );
      expect(active.beginMasterPasswordStepUp, throwsStateError);
    });

    test('a stale step-up challenge cannot upgrade a newer session', () {
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      addTearDown(controller.dispose);

      final MasterPasswordStepUpChallenge stale = controller
          .beginMasterPasswordStepUp();
      controller.lock(LockReason.manualLock);
      controller.unlock(AuthStrength.masterPassword);
      controller.lock(LockReason.backgroundOrTimeout);
      controller.unlock(AuthStrength.biometric);
      final MasterPasswordStepUpChallenge current = controller
          .beginMasterPasswordStepUp();

      expect(stale.complete(), isFalse);
      expect(stale.isActive, isFalse);
      expect(current.isActive, isTrue);
      expect(
        (controller.state as UnlockedSession).authStrength,
        AuthStrength.biometric,
      );

      expect(current.complete(), isTrue);
      expect(
        (controller.state as UnlockedSession).authStrength,
        AuthStrength.masterPassword,
      );
    });

    test('rejects challenge reentry while a lock is being published', () {
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      addTearDown(controller.dispose);
      final MasterPasswordStepUpChallenge challenge = controller
          .beginMasterPasswordStepUp();
      var reentryRejected = false;
      challenge.onInvalidated(() {
        try {
          controller.beginMasterPasswordStepUp();
        } on StateError {
          reentryRejected = true;
        }
      });

      controller.lock(LockReason.manualLock);

      expect(reentryRejected, isTrue);
      controller.unlock(AuthStrength.masterPassword);
      controller.lock(LockReason.backgroundOrTimeout);
      controller.unlock(AuthStrength.biometric);
      expect(controller.beginMasterPasswordStepUp().isActive, isTrue);
    });

    test('rejects unlock reentry while a lock is being published', () {
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      addTearDown(controller.dispose);
      var reentryRejected = false;
      final subscription = controller.states.listen((SessionState state) {
        if (state is LockedSession) {
          try {
            controller.unlock(AuthStrength.masterPassword);
          } on StateError {
            reentryRejected = true;
          }
        }
      });
      addTearDown(subscription.cancel);

      controller.lock(LockReason.manualLock);

      expect(reentryRejected, isTrue);
      expect(controller.state, isA<LockedSession>());
      expect(controller.hasActiveIdleTimer, isFalse);
    });

    test('rejects unlock reentry while a locked reason is being tightened', () {
      final SessionController controller = SessionController(
        initialState: const LockedSession(
          reason: LockReason.backgroundOrTimeout,
        ),
      );
      addTearDown(controller.dispose);
      var reentryRejected = false;
      final subscription = controller.states.listen((SessionState state) {
        if (state is LockedSession &&
            state.reason == LockReason.biometricInvalidated) {
          try {
            controller.unlock(AuthStrength.masterPassword);
          } on StateError {
            reentryRejected = true;
          }
        }
      });
      addTearDown(subscription.cancel);

      controller.handle(SessionEvent.biometricInvalidated);

      expect(reentryRejected, isTrue);
      expect(
        (controller.state as LockedSession).reason,
        LockReason.biometricInvalidated,
      );
    });

    test('keeps locking through nested locked-state notifications', () {
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      addTearDown(controller.dispose);
      var reentryRejected = false;
      final subscription = controller.states.listen((SessionState state) {
        if (state is LockedSession && state.reason == LockReason.manualLock) {
          controller.handle(SessionEvent.biometricInvalidated);
        }
        if (state is LockedSession &&
            state.reason == LockReason.biometricInvalidated) {
          try {
            controller.unlock(AuthStrength.masterPassword);
          } on StateError {
            reentryRejected = true;
          }
        }
      });
      addTearDown(subscription.cancel);

      controller.lock(LockReason.manualLock);

      expect(reentryRejected, isTrue);
      expect(
        (controller.state as LockedSession).reason,
        LockReason.biometricInvalidated,
      );
    });

    test('locks and continues cleanup when one cleaner throws', () {
      final RecordingCleaner survivor = RecordingCleaner();
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
        secretCleaner: SessionSecretCleaners(<SessionSecretCleaner>[
          ThrowingCleaner(),
          survivor,
        ]),
      );
      addTearDown(controller.dispose);

      controller.lock(LockReason.backgroundOrTimeout);

      expect(controller.state, isA<LockedSession>());
      expect(survivor.clearCount, 1);
    });

    test('cleans an unlocked session when disposed directly', () {
      final RecordingCleaner cleaner = RecordingCleaner();
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
        secretCleaner: cleaner,
      );

      controller.dispose();

      expect(cleaner.clearCount, 1);
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

    test(
      'completes a wipe through a locked state before returning to setup',
      () {
        final RecordingCleaner cleaner = RecordingCleaner();
        final List<FakeSessionTimer> timers = <FakeSessionTimer>[];
        final SessionController controller = SessionController(
          initialState: const UnlockedSession(
            authStrength: AuthStrength.masterPassword,
          ),
          secretCleaner: cleaner,
          timerFactory: (Duration duration, void Function() callback) {
            final FakeSessionTimer timer = FakeSessionTimer(callback);
            timers.add(timer);
            return timer;
          },
        );
        addTearDown(controller.dispose);

        final SessionActivityLease lease = controller.beginActivity(
          SessionActivity.authenticatedWipe,
        );
        var interruptionCount = 0;
        lease.onInterrupted(() => interruptionCount++);

        controller.beginWipe();

        expect(controller.state, isA<LockedSession>());
        expect(
          (controller.state as LockedSession).reason,
          LockReason.wipeStarted,
        );
        expect(controller.routeState, SessionRouteState.unlock);
        expect(controller.hasActiveIdleTimer, isFalse);
        expect(lease.isActive, isFalse);
        expect(interruptionCount, 1);
        expect(cleaner.clearCount, 1);
        expect(
          () => controller.unlock(AuthStrength.masterPassword),
          throwsStateError,
        );

        controller.completeWipe();

        expect(controller.state, isA<VaultNotCreatedSession>());
        expect(controller.routeState, SessionRouteState.setup);
        expect(controller.hasActiveIdleTimer, isFalse);
        expect(() => controller.completeWipe(), throwsStateError);

        controller.handle(SessionEvent.appBackgrounded);
        expect(controller.state, isA<VaultNotCreatedSession>());
        expect(
          timers.where((FakeSessionTimer timer) => timer.isActive),
          isEmpty,
        );
      },
    );

    test(
      'tightens a normal lock into a wipe lock before allowing completion',
      () {
        final SessionController controller = SessionController(
          initialState: const LockedSession(reason: LockReason.coldStart),
        );
        addTearDown(controller.dispose);

        expect(() => controller.completeWipe(), throwsStateError);

        controller.beginWipe();

        expect(
          (controller.state as LockedSession).reason,
          LockReason.wipeStarted,
        );
        expect(
          () => controller.unlock(AuthStrength.masterPassword),
          throwsStateError,
        );

        controller.completeWipe();
        expect(controller.state, isA<VaultNotCreatedSession>());
      },
    );

    test(
      'keeps lock reason capabilities consistent across all locked states',
      () {
        const List<LockReason> coveredReasons = <LockReason>[
          LockReason.coldStart,
          LockReason.backgroundOrTimeout,
          LockReason.manualLock,
          LockReason.biometricInvalidated,
          LockReason.wipeStarted,
        ];
        const Map<LockReason, bool> biometricAllowed = <LockReason, bool>{
          LockReason.coldStart: true,
          LockReason.backgroundOrTimeout: true,
          LockReason.manualLock: false,
          LockReason.biometricInvalidated: false,
          LockReason.wipeStarted: false,
        };
        const Map<LockReason, bool> masterPasswordAllowed = <LockReason, bool>{
          LockReason.coldStart: true,
          LockReason.backgroundOrTimeout: true,
          LockReason.manualLock: true,
          LockReason.biometricInvalidated: true,
          LockReason.wipeStarted: false,
        };

        for (final LockReason reason in coveredReasons) {
          final SessionController controller = SessionController(
            initialState: LockedSession(reason: reason),
          );
          addTearDown(controller.dispose);

          expect(controller.routeState, SessionRouteState.unlock);
          expect(
            (controller.state as LockedSession).canUseBiometric,
            biometricAllowed[reason],
          );

          if (biometricAllowed[reason]!) {
            controller.unlock(AuthStrength.biometric);
            expect(
              (controller.state as UnlockedSession).authStrength,
              AuthStrength.biometric,
            );
            controller.lock(reason);
          } else {
            expect(
              () => controller.unlock(AuthStrength.biometric),
              throwsStateError,
            );
          }

          if (masterPasswordAllowed[reason]!) {
            if (controller.state is LockedSession) {
              controller.unlock(AuthStrength.masterPassword);
            }
            expect(
              (controller.state as UnlockedSession).authStrength,
              AuthStrength.masterPassword,
            );
          } else {
            expect(
              () => controller.unlock(AuthStrength.masterPassword),
              throwsStateError,
            );
          }
        }
      },
    );

    test(
      'completes every concrete session activity and restores idle state',
      () {
        const List<SessionActivity> coveredActivities = <SessionActivity>[
          SessionActivity.migrationSending,
          SessionActivity.migrationReceiving,
          SessionActivity.passwordRecovery,
          SessionActivity.passwordChange,
          SessionActivity.biometricConfiguration,
          SessionActivity.authenticatedWipe,
          SessionActivity.vaultAccess,
        ];

        for (final SessionActivity activity in coveredActivities) {
          final List<FakeSessionTimer> timers = <FakeSessionTimer>[];
          final SessionController controller = SessionController(
            initialState: const UnlockedSession(
              authStrength: AuthStrength.biometric,
            ),
            timerFactory: (Duration duration, void Function() callback) {
              final FakeSessionTimer timer = FakeSessionTimer(callback);
              timers.add(timer);
              return timer;
            },
          );
          addTearDown(controller.dispose);

          final SessionActivityLease lease = controller.beginActivity(activity);
          expect((controller.state as UnlockedSession).activity, activity);
          expect(
            (controller.state as UnlockedSession).authStrength,
            AuthStrength.biometric,
          );
          expect(controller.isIdleTimeoutSuppressed, isTrue);
          expect(controller.hasActiveIdleTimer, isFalse);

          lease.complete();

          expect(
            (controller.state as UnlockedSession).activity,
            SessionActivity.none,
          );
          expect(
            (controller.state as UnlockedSession).authStrength,
            AuthStrength.biometric,
          );
          expect(controller.isIdleTimeoutSuppressed, isFalse);
          expect(controller.hasActiveIdleTimer, isTrue);
          expect(timers, hasLength(2));
        }
      },
    );

    test('cancels every concrete session activity back to an idle session', () {
      const List<SessionActivity> coveredActivities = <SessionActivity>[
        SessionActivity.migrationSending,
        SessionActivity.migrationReceiving,
        SessionActivity.passwordRecovery,
        SessionActivity.passwordChange,
        SessionActivity.biometricConfiguration,
        SessionActivity.authenticatedWipe,
        SessionActivity.vaultAccess,
      ];

      for (final SessionActivity activity in coveredActivities) {
        final List<FakeSessionTimer> timers = <FakeSessionTimer>[];
        final SessionController controller = SessionController(
          initialState: const UnlockedSession(
            authStrength: AuthStrength.masterPassword,
          ),
          timerFactory: (Duration duration, void Function() callback) {
            final FakeSessionTimer timer = FakeSessionTimer(callback);
            timers.add(timer);
            return timer;
          },
        );
        addTearDown(controller.dispose);

        final SessionActivityLease lease = controller.beginActivity(activity);
        var interruptionCount = 0;
        lease.onInterrupted(() => interruptionCount++);
        lease.cancel();

        expect(lease.isActive, isFalse);
        expect(interruptionCount, 1);
        expect(
          (controller.state as UnlockedSession).activity,
          SessionActivity.none,
        );
        expect(
          (controller.state as UnlockedSession).authStrength,
          AuthStrength.masterPassword,
        );
        expect(controller.hasActiveIdleTimer, isTrue);
        expect(timers, hasLength(2));
      }
    });

    test('interrupts every concrete session activity when the vault locks', () {
      const List<SessionActivity> coveredActivities = <SessionActivity>[
        SessionActivity.migrationSending,
        SessionActivity.migrationReceiving,
        SessionActivity.passwordRecovery,
        SessionActivity.passwordChange,
        SessionActivity.biometricConfiguration,
        SessionActivity.authenticatedWipe,
        SessionActivity.vaultAccess,
      ];

      for (final SessionActivity activity in coveredActivities) {
        final SessionController controller = SessionController(
          initialState: const UnlockedSession(
            authStrength: AuthStrength.masterPassword,
          ),
        );
        addTearDown(controller.dispose);

        final SessionActivityLease lease = controller.beginActivity(activity);
        controller.lock(LockReason.manualLock);

        expect(lease.isActive, isFalse);
        expect(
          () => lease.ensureActive(),
          throwsA(
            isA<SessionActivityInterrupted>().having(
              (SessionActivityInterrupted error) => error.activity,
              'activity',
              activity,
            ),
          ),
        );
        expect(controller.state, isA<LockedSession>());
      }
    });

    test('cancelling a step-up leaves the biometric session unchanged', () {
      final SessionController controller = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      addTearDown(controller.dispose);

      final MasterPasswordStepUpChallenge challenge = controller
          .beginMasterPasswordStepUp();
      challenge.cancel();

      expect(challenge.isActive, isFalse);
      expect(controller.requiresMasterPasswordStepUp, isTrue);
      expect(
        (controller.state as UnlockedSession).authStrength,
        AuthStrength.biometric,
      );
      expect(challenge.complete(), isFalse);
      expect(
        (controller.state as UnlockedSession).authStrength,
        AuthStrength.biometric,
      );
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

final class ThrowingCleaner implements SessionSecretCleaner {
  @override
  void clearUnlockedSession() => throw StateError('cleanup failed');
}
