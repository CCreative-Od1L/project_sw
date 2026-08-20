import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';
import 'package:project_sw/features/auth/domain/recovery/recover_master_password.dart';
import 'package:project_sw/shared/result.dart';
import 'package:test/test.dart';

void main() {
  test('confirms biometrics, re-wraps the MVK, and starts cooldown', () async {
    final DateTime now = DateTime.utc(2026, 8, 20, 12);
    final _RecoveryStore store = _RecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(
      store,
      clock: () => now,
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      await gate.recordChangePasswordFailure(biometricConfigured: true);
    }
    final _RecoveryConfirmer confirmer = _RecoveryConfirmer();
    final _RecoveryRepository repository = _RecoveryRepository();
    final RecoverMasterPassword recoverMasterPassword = RecoverMasterPassword(
      gate: gate,
      biometricConfirmer: confirmer,
      repository: repository,
    );

    final Result<RecoveredMasterPassword, RecoverMasterPasswordFailure> result =
        await recoverMasterPassword(newMasterPassword: 'new password');

    expect(
      result,
      isA<Success<RecoveredMasterPassword, RecoverMasterPasswordFailure>>(),
    );
    expect(confirmer.confirmations, 1);
    expect(repository.passwords, <String>['new password']);
    expect(store.cooldownUntil, DateTime.utc(2026, 8, 27, 12));
  });

  test('does not prompt when the recovery gate is unavailable', () async {
    final _RecoveryStore store = _RecoveryStore();
    final _RecoveryConfirmer confirmer = _RecoveryConfirmer();
    final _RecoveryRepository repository = _RecoveryRepository();
    final RecoverMasterPassword recoverMasterPassword = RecoverMasterPassword(
      gate: MasterPasswordRecoveryGate(store),
      biometricConfirmer: confirmer,
      repository: repository,
    );

    final Result<RecoveredMasterPassword, RecoverMasterPasswordFailure> result =
        await recoverMasterPassword(newMasterPassword: 'new password');

    expect(
      result,
      isA<Failure<RecoveredMasterPassword, RecoverMasterPasswordFailure>>()
          .having(
            (
              Failure<RecoveredMasterPassword, RecoverMasterPasswordFailure>
              failure,
            ) => failure.failure,
            'failure',
            RecoverMasterPasswordFailure.recoveryUnavailable,
          ),
    );
    expect(confirmer.confirmations, 0);
    expect(repository.passwords, isEmpty);
    expect(store.cooldownUntil, isNull);
  });

  test('rejects a weak replacement before biometric confirmation', () async {
    final _RecoveryStore store = _RecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(store);
    for (var attempt = 0; attempt < 3; attempt++) {
      await gate.recordChangePasswordFailure(biometricConfigured: true);
    }
    final _RecoveryConfirmer confirmer = _RecoveryConfirmer();
    final _RecoveryRepository repository = _RecoveryRepository();
    final RecoverMasterPassword recoverMasterPassword = RecoverMasterPassword(
      gate: gate,
      biometricConfirmer: confirmer,
      repository: repository,
    );

    final Result<RecoveredMasterPassword, RecoverMasterPasswordFailure> result =
        await recoverMasterPassword(newMasterPassword: 'short');

    expect(
      result,
      isA<Failure<RecoveredMasterPassword, RecoverMasterPasswordFailure>>()
          .having(
            (
              Failure<RecoveredMasterPassword, RecoverMasterPasswordFailure>
              failure,
            ) => failure.failure,
            'failure',
            RecoverMasterPasswordFailure.weakNewMasterPassword,
          ),
    );
    expect(confirmer.confirmations, 0);
    expect(repository.passwords, isEmpty);
  });

  test('maps biometric cancellation without reserving cooldown', () async {
    final _RecoveryStore store = _RecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(store);
    for (var attempt = 0; attempt < 3; attempt++) {
      await gate.recordChangePasswordFailure(biometricConfigured: true);
    }
    final _RecoveryConfirmer confirmer = _RecoveryConfirmer(
      error: const BiometricCancelledException(),
    );
    final _RecoveryRepository repository = _RecoveryRepository();
    final RecoverMasterPassword recoverMasterPassword = RecoverMasterPassword(
      gate: gate,
      biometricConfirmer: confirmer,
      repository: repository,
    );

    final Result<RecoveredMasterPassword, RecoverMasterPasswordFailure> result =
        await recoverMasterPassword(newMasterPassword: 'new password');

    expect(
      result,
      isA<Failure<RecoveredMasterPassword, RecoverMasterPasswordFailure>>()
          .having(
            (
              Failure<RecoveredMasterPassword, RecoverMasterPasswordFailure>
              failure,
            ) => failure.failure,
            'failure',
            RecoverMasterPasswordFailure.biometricCancelled,
          ),
    );
    expect(repository.passwords, isEmpty);
    expect(store.cooldownUntil, isNull);
  });

  test('clears reserved cooldown when the vault re-wrap fails', () async {
    final _RecoveryStore store = _RecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(store);
    for (var attempt = 0; attempt < 3; attempt++) {
      await gate.recordChangePasswordFailure(biometricConfigured: true);
    }
    final _RecoveryRepository repository = _RecoveryRepository(
      error: StateError('commit failed'),
    );
    final RecoverMasterPassword recoverMasterPassword = RecoverMasterPassword(
      gate: gate,
      biometricConfirmer: _RecoveryConfirmer(),
      repository: repository,
    );

    await expectLater(
      recoverMasterPassword(newMasterPassword: 'new password'),
      throwsStateError,
    );

    expect(store.cooldownUntil, isNull);
    expect(
      await gate.currentState(biometricConfigured: true),
      isA<MasterPasswordRecoveryAvailable>(),
    );
  });
}

final class _RecoveryStore implements MasterPasswordRecoveryStore {
  DateTime? cooldownUntil;

  @override
  Future<void> clearCooldown() async => cooldownUntil = null;

  @override
  Future<DateTime?> readCooldownUntil() async => cooldownUntil;

  @override
  Future<void> writeCooldownUntil(DateTime value) async {
    cooldownUntil = value;
  }
}

final class _RecoveryConfirmer implements BiometricRecoveryConfirmer {
  _RecoveryConfirmer({this.error});

  final Object? error;
  var confirmations = 0;

  @override
  Future<void> confirm() async {
    confirmations++;
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

final class _RecoveryRepository implements MasterPasswordRecoveryRepository {
  _RecoveryRepository({this.error});

  final Object? error;
  final List<String> passwords = <String>[];

  @override
  Future<void> recoverMasterPassword({
    required String newMasterPassword,
  }) async {
    passwords.add(newMasterPassword);
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}
