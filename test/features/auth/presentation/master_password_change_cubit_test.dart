import 'dart:async';

import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';
import 'package:project_sw/features/auth/domain/recovery/recover_master_password.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:test/test.dart';

void main() {
  test('changes the password and upgrades a biometric session', () async {
    final _PasswordChangeRepository repository = _PasswordChangeRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(repository),
      sessionController,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);

    await cubit.submit(
      currentMasterPassword: 'current password',
      newMasterPassword: 'new password',
      confirmation: 'new password',
    );

    expect(cubit.state, isA<MasterPasswordChangeCompleted>());
    expect(repository.calls, <(String, String)>[
      ('current password', 'new password'),
    ]);
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.masterPassword,
    );
  });

  test('a stale password change cannot upgrade a newer session', () async {
    final _BlockingPasswordChangeRepository repository =
        _BlockingPasswordChangeRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(repository),
      sessionController,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);

    final Future<void> submission = cubit.submit(
      currentMasterPassword: 'current password',
      newMasterPassword: 'new password',
      confirmation: 'new password',
    );
    await repository.started.future;
    sessionController.lock(LockReason.manualLock);
    sessionController.unlock(AuthStrength.masterPassword);
    sessionController.lock(LockReason.backgroundOrTimeout);
    sessionController.unlock(AuthStrength.biometric);
    repository.complete();
    await submission;

    expect(cubit.state, isA<MasterPasswordChangeFault>());
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.biometric,
    );
  });

  test('rejects a mismatched confirmation before changing the vault', () async {
    final _PasswordChangeRepository repository = _PasswordChangeRepository();
    final SessionController sessionController = SessionController();
    final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(repository),
      sessionController,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);

    await cubit.submit(
      currentMasterPassword: 'current password',
      newMasterPassword: 'first value',
      confirmation: 'different value',
    );

    expect(cubit.state, isA<MasterPasswordChangeConfirmationMismatch>());
    expect(repository.calls, isEmpty);
  });

  test(
    'keeps the session unlocked when the current password is wrong',
    () async {
      final SessionController sessionController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
        ChangeMasterPassword(
          _PasswordChangeRepository(
            error: const InvalidMasterPasswordException(),
          ),
        ),
        sessionController,
      );
      addTearDown(cubit.close);
      addTearDown(sessionController.dispose);

      await cubit.submit(
        currentMasterPassword: 'wrong password',
        newMasterPassword: 'new password',
        confirmation: 'new password',
      );

      expect(cubit.state, isA<MasterPasswordChangeInvalidCurrent>());
      expect(
        (sessionController.state as UnlockedSession).authStrength,
        AuthStrength.biometric,
      );
    },
  );

  test(
    'reveals biometric recovery only after the third rejected password',
    () async {
      final SessionController sessionController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(
        _RecoveryStore(),
      );
      final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
        ChangeMasterPassword(
          _PasswordChangeRepository(
            error: const InvalidMasterPasswordException(),
          ),
        ),
        sessionController,
        recoveryGate: gate,
        hasConfiguredBiometricRecovery: () async => true,
        recoverMasterPassword: RecoverMasterPassword(
          gate: gate,
          biometricConfirmer: _RecoveryConfirmer(),
          repository: _RecoveryRepository(),
        ),
      );
      addTearDown(cubit.close);
      addTearDown(sessionController.dispose);

      for (var attempt = 1; attempt <= 3; attempt++) {
        await cubit.submit(
          currentMasterPassword: 'wrong password',
          newMasterPassword: 'new password',
          confirmation: 'new password',
        );
        final MasterPasswordChangeInvalidCurrent state =
            cubit.state as MasterPasswordChangeInvalidCurrent;
        expect(state.recoveryAvailable, attempt == 3);
      }
    },
  );

  test('recovers without upgrading a biometric session', () async {
    final DateTime now = DateTime.utc(2026, 8, 20, 12);
    final _RecoveryStore store = _RecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(
      store,
      clock: () => now,
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      await gate.recordChangePasswordFailure(biometricConfigured: true);
    }
    final _RecoveryRepository recoveryRepository = _RecoveryRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(_PasswordChangeRepository()),
      sessionController,
      recoveryGate: gate,
      hasConfiguredBiometricRecovery: () async => true,
      recoverMasterPassword: RecoverMasterPassword(
        gate: gate,
        biometricConfirmer: _RecoveryConfirmer(),
        repository: recoveryRepository,
      ),
    );
    final List<SessionState> sessionStates = <SessionState>[];
    final sessionSubscription = sessionController.states.listen(
      sessionStates.add,
    );
    addTearDown(cubit.close);
    addTearDown(sessionSubscription.cancel);
    addTearDown(sessionController.dispose);

    await cubit.recover(
      newMasterPassword: 'recovered password',
      confirmation: 'recovered password',
    );

    expect(cubit.state, isA<MasterPasswordRecoveryCompleted>());
    expect(recoveryRepository.passwords, <String>['recovered password']);
    expect(store.cooldownUntil, DateTime.utc(2026, 8, 27, 12));
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.biometric,
    );
    expect(
      sessionStates.whereType<UnlockedSession>().map(
        (UnlockedSession state) => state.activity,
      ),
      <SessionActivity>[SessionActivity.passwordRecovery, SessionActivity.none],
    );
    expect(sessionController.isIdleTimeoutSuppressed, isFalse);
  });

  test('does not replace or release another session activity', () async {
    final _RecoveryStore store = _RecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(store);
    for (var attempt = 0; attempt < 3; attempt++) {
      await gate.recordChangePasswordFailure(biometricConfigured: true);
    }
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    final SessionActivityLease migrationLease = sessionController.beginActivity(
      SessionActivity.migrationSending,
    );
    final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(_PasswordChangeRepository()),
      sessionController,
      recoveryGate: gate,
      hasConfiguredBiometricRecovery: () async => true,
      recoverMasterPassword: RecoverMasterPassword(
        gate: gate,
        biometricConfirmer: _RecoveryConfirmer(),
        repository: _RecoveryRepository(),
      ),
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);

    await cubit.recover(
      newMasterPassword: 'recovered password',
      confirmation: 'recovered password',
    );

    expect(cubit.state, isA<MasterPasswordRecoveryFault>());
    expect(sessionController.isIdleTimeoutSuppressed, isTrue);
    expect(
      (sessionController.state as UnlockedSession).activity,
      SessionActivity.migrationSending,
    );
    migrationLease.complete();
  });

  test(
    'does not re-wrap the vault after recovery is interrupted by lock',
    () async {
      final _RecoveryStore store = _RecoveryStore();
      final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(store);
      for (var attempt = 0; attempt < 3; attempt++) {
        await gate.recordChangePasswordFailure(biometricConfigured: true);
      }
      final _BlockingRecoveryConfirmer confirmer = _BlockingRecoveryConfirmer();
      final _RecoveryRepository repository = _RecoveryRepository();
      final SessionController sessionController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
        ChangeMasterPassword(_PasswordChangeRepository()),
        sessionController,
        recoveryGate: gate,
        hasConfiguredBiometricRecovery: () async => true,
        recoverMasterPassword: RecoverMasterPassword(
          gate: gate,
          biometricConfirmer: confirmer,
          repository: repository,
        ),
      );
      addTearDown(cubit.close);
      addTearDown(sessionController.dispose);

      final Future<void> recovery = cubit.recover(
        newMasterPassword: 'recovered password',
        confirmation: 'recovered password',
      );
      await confirmer.started.future;

      sessionController.handle(SessionEvent.appBackgrounded);
      confirmer.complete();
      await recovery;

      expect(cubit.state, isA<MasterPasswordRecoveryFault>());
      expect(repository.passwords, isEmpty);
      expect(store.cooldownUntil, isNull);
      expect(sessionController.state, isA<LockedSession>());
    },
  );

  test(
    'loads a persisted recovery window without another failed attempt',
    () async {
      final _RecoveryStore store = _RecoveryStore();
      final MasterPasswordRecoveryGate firstGate = MasterPasswordRecoveryGate(
        store,
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        await firstGate.recordChangePasswordFailure(biometricConfigured: true);
      }
      final SessionController sessionController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      final MasterPasswordRecoveryGate recreatedGate =
          MasterPasswordRecoveryGate(store);
      final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
        ChangeMasterPassword(_PasswordChangeRepository()),
        sessionController,
        recoveryGate: recreatedGate,
        hasConfiguredBiometricRecovery: () async => true,
        recoverMasterPassword: RecoverMasterPassword(
          gate: recreatedGate,
          biometricConfirmer: _RecoveryConfirmer(),
          repository: _RecoveryRepository(),
        ),
      );
      addTearDown(cubit.close);
      addTearDown(sessionController.dispose);

      await cubit.reset();

      expect(
        (cubit.state as MasterPasswordChangeReady).recoveryAvailable,
        isTrue,
      );
    },
  );
}

final class _PasswordChangeRepository
    implements MasterPasswordChangeRepository {
  _PasswordChangeRepository({this.error});

  final List<(String, String)> calls = <(String, String)>[];
  final Object? error;

  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    calls.add((currentMasterPassword, newMasterPassword));
    if (error != null) throw error!;
  }
}

final class _BlockingPasswordChangeRepository
    implements MasterPasswordChangeRepository {
  final Completer<void> started = Completer<void>();
  final Completer<void> _completion = Completer<void>();

  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    started.complete();
    await _completion.future;
  }

  void complete() => _completion.complete();
}

final class _RecoveryStore implements MasterPasswordRecoveryStore {
  MasterPasswordRecoveryMetadata metadata =
      const MasterPasswordRecoveryMetadata();

  DateTime? get cooldownUntil => metadata.cooldownUntil;

  @override
  Future<void> clear() async {
    metadata = const MasterPasswordRecoveryMetadata();
  }

  @override
  Future<MasterPasswordRecoveryMetadata> read() async => metadata;

  @override
  Future<void> write(MasterPasswordRecoveryMetadata value) async {
    metadata = value;
  }
}

final class _RecoveryConfirmer implements BiometricRecoveryConfirmer {
  @override
  Future<void> confirm() async {}
}

final class _BlockingRecoveryConfirmer implements BiometricRecoveryConfirmer {
  final Completer<void> started = Completer<void>();
  final Completer<void> _completion = Completer<void>();

  @override
  Future<void> confirm() {
    started.complete();
    return _completion.future;
  }

  void complete() => _completion.complete();
}

final class _RecoveryRepository implements MasterPasswordRecoveryRepository {
  final List<String> passwords = <String>[];

  @override
  Future<void> recoverMasterPassword({
    required String newMasterPassword,
    required SessionActivityLease activityLease,
  }) async {
    activityLease.ensureActive();
    passwords.add(newMasterPassword);
  }
}
