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

  test(
    'resumes a revealed recovery window after recreating the gate',
    () async {
      DateTime now = DateTime.utc(2026, 8, 20, 12);
      final _MemoryRecoveryStore store = _MemoryRecoveryStore();
      final MasterPasswordRecoveryGate firstGate = MasterPasswordRecoveryGate(
        store,
        clock: () => now,
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        await firstGate.recordChangePasswordFailure(biometricConfigured: true);
      }

      final MasterPasswordRecoveryGate recreatedGate =
          MasterPasswordRecoveryGate(store, clock: () => now);
      expect(
        await recreatedGate.currentState(biometricConfigured: true),
        isA<MasterPasswordRecoveryAvailable>(),
      );

      now = DateTime.utc(2026, 8, 20, 12, 10);
      expect(
        await recreatedGate.currentState(biometricConfigured: true),
        isA<MasterPasswordRecoveryHidden>(),
      );
      expect(
        await recreatedGate.recordChangePasswordFailure(
          biometricConfigured: true,
        ),
        isA<MasterPasswordRecoveryHidden>(),
      );
    },
  );

  test(
    'a successful normal change clears a revealed recovery window',
    () async {
      final _MemoryRecoveryStore store = _MemoryRecoveryStore();
      final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(store);
      for (var attempt = 0; attempt < 3; attempt++) {
        await gate.recordChangePasswordFailure(biometricConfigured: true);
      }

      await gate.recordChangePasswordSuccess();

      expect(store.metadata.isEmpty, isTrue);
      expect(
        await MasterPasswordRecoveryGate(
          store,
        ).currentState(biometricConfigured: true),
        isA<MasterPasswordRecoveryHidden>(),
      );
    },
  );
}

final class _MemoryRecoveryStore implements MasterPasswordRecoveryStore {
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
