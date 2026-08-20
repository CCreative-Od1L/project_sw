import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';
import 'package:test/test.dart';

void main() {
  test('reveals recovery only after three change-password failures', () async {
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(
      _MemoryRecoveryStore(),
      clock: () => DateTime.utc(2026, 8, 20, 12),
    );

    expect(
      await gate.recordChangePasswordFailure(biometricConfigured: true),
      isA<MasterPasswordRecoveryHidden>(),
    );
    expect(
      await gate.recordChangePasswordFailure(biometricConfigured: true),
      isA<MasterPasswordRecoveryHidden>(),
    );
    expect(
      await gate.recordChangePasswordFailure(biometricConfigured: true),
      isA<MasterPasswordRecoveryAvailable>(),
    );
  });

  test('keeps recovery hidden until biometric access is configured', () async {
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(
      _MemoryRecoveryStore(),
      clock: () => DateTime.utc(2026, 8, 20, 12),
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      expect(
        await gate.recordChangePasswordFailure(biometricConfigured: false),
        isA<MasterPasswordRecoveryHidden>(),
      );
    }

    expect(
      await gate.currentState(biometricConfigured: true),
      isA<MasterPasswordRecoveryAvailable>(),
    );
  });

  test('hides recovery for one week after a successful recovery', () async {
    DateTime now = DateTime.utc(2026, 8, 20, 12);
    final _MemoryRecoveryStore store = _MemoryRecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(
      store,
      clock: () => now,
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      await gate.recordChangePasswordFailure(biometricConfigured: true);
    }

    await gate.recordRecoverySuccess();

    final MasterPasswordRecoveryState cooling = await gate.currentState(
      biometricConfigured: true,
    );
    expect(cooling, isA<MasterPasswordRecoveryCoolingDown>());
    expect(
      (cooling as MasterPasswordRecoveryCoolingDown).until,
      DateTime.utc(2026, 8, 27, 12),
    );
    expect(store.cooldownUntil, DateTime.utc(2026, 8, 27, 12));

    now = DateTime.utc(2026, 8, 27, 12);
    expect(
      await gate.currentState(biometricConfigured: true),
      isA<MasterPasswordRecoveryHidden>(),
    );
    expect(store.cooldownUntil, isNull);
  });
}

final class _MemoryRecoveryStore implements MasterPasswordRecoveryStore {
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
