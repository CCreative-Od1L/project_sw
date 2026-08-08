import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';

void main() {
  late FakeBiometricVaultRepository repository;
  late FakeBiometricKeyStore keyStore;
  late SessionController sessionController;
  late BiometricUnlockCubit cubit;

  setUp(() {
    repository = FakeBiometricVaultRepository();
    keyStore = FakeBiometricKeyStore();
    sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    cubit = BiometricUnlockCubit(repository, keyStore, sessionController);
  });

  tearDown(() {
    cubit.close();
    sessionController.dispose();
  });

  test(
    'loads configured biometric access and publishes biometric strength',
    () async {
      await cubit.loadAvailability();
      expect(cubit.state, isA<BiometricUnlockReady>());

      await cubit.unlock();

      expect(repository.unlockCount, 1);
      expect(sessionController.state, const TypeMatcher<UnlockedSession>());
      expect(
        (sessionController.state as UnlockedSession).authStrength,
        AuthStrength.biometric,
      );
      expect(cubit.state, isA<BiometricUnlockReady>());
    },
  );

  test('does not upgrade the session when the user cancels', () async {
    await cubit.loadAvailability();
    repository.unlockFailure = const BiometricCancelledException();

    await cubit.unlock();

    expect(cubit.state, isA<BiometricUnlockCancelled>());
    expect(sessionController.state, isA<LockedSession>());
  });

  test(
    'maps biometric invalidation without hiding the master fallback',
    () async {
      await cubit.loadAvailability();
      repository.unlockFailure = const BiometricInvalidatedException();

      await cubit.unlock();

      expect(cubit.state, isA<BiometricUnlockInvalidated>());
      expect(sessionController.state, isA<LockedSession>());
      expect(
        (sessionController.state as LockedSession).reason,
        LockReason.biometricInvalidated,
      );
    },
  );

  test(
    'does not offer a biometric action when the device is unavailable',
    () async {
      keyStore.currentAvailability = BiometricAvailability.unavailable;

      await cubit.loadAvailability();

      final BiometricUnlockReady state = cubit.state as BiometricUnlockReady;
      expect(state.isConfigured, isTrue);
      expect(state.isAvailable, isFalse);
    },
  );
}

final class FakeBiometricVaultRepository implements BiometricVaultRepository {
  Object? unlockFailure;
  var unlockCount = 0;
  var configured = true;

  @override
  bool get hasBiometricUnlock => configured;

  @override
  Future<void> disableBiometricUnlock() async => configured = false;

  @override
  Future<void> enableBiometricUnlock() async => configured = true;

  @override
  Future<bool> hasConfiguredBiometricUnlock() async => configured;

  @override
  Future<void> unlockWithBiometric() async {
    unlockCount++;
    final Object? failure = unlockFailure;
    if (failure != null) throw failure;
  }
}

final class FakeBiometricKeyStore implements BiometricKeyStore {
  BiometricAvailability currentAvailability = BiometricAvailability.available;

  @override
  Future<BiometricAvailability> get availability async => currentAvailability;

  @override
  Future<Uint8List> createAndStoreKey() async => Uint8List(32);

  @override
  Future<void> deleteKey() async {}

  @override
  Future<Uint8List> loadKey() async => Uint8List(32);
}
