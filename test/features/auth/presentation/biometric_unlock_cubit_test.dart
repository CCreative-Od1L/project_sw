import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';

void main() {
  late FakeBiometricVaultRepository repository;
  late FakeBiometricKeyStore keyStore;
  late SessionController sessionController;
  late BiometricUnlockCubit cubit;
  late int onUnlockedCalls;

  setUp(() {
    repository = FakeBiometricVaultRepository();
    keyStore = FakeBiometricKeyStore();
    sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    onUnlockedCalls = 0;
    cubit = BiometricUnlockCubit(
      repository,
      keyStore,
      sessionController,
      onUnlocked: () => onUnlockedCalls++,
    );
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
    'ignores a biometric result after the locked session backgrounds',
    () async {
      await cubit.loadAvailability();
      final Completer<void> unlockStarted = Completer<void>();
      final Completer<void> releaseUnlock = Completer<void>();
      repository.unlockStarted = unlockStarted;
      repository.releaseUnlock = releaseUnlock;

      final Future<void> unlock = cubit.unlock();
      await unlockStarted.future;

      sessionController.handle(SessionEvent.appBackgrounded);
      releaseUnlock.complete();
      await unlock;

      expect(sessionController.state, isA<LockedSession>());
      expect(cubit.state, isA<BiometricUnlockReady>());
      expect(onUnlockedCalls, 0);
    },
  );

  test(
    'does not let a stale biometric result replace a newer session',
    () async {
      await cubit.loadAvailability();
      final Completer<void> unlockStarted = Completer<void>();
      final Completer<void> releaseUnlock = Completer<void>();
      repository.unlockStarted = unlockStarted;
      repository.releaseUnlock = releaseUnlock;

      final Future<void> unlock = cubit.unlock();
      await unlockStarted.future;
      sessionController.handle(SessionEvent.appBackgrounded);
      sessionController.unlock(AuthStrength.masterPassword);

      releaseUnlock.complete();
      await unlock;

      expect(
        (sessionController.state as UnlockedSession).authStrength,
        AuthStrength.masterPassword,
      );
      expect(cubit.state, isA<BiometricUnlockReady>());
      expect(onUnlockedCalls, 0);
    },
  );

  test('cancels a pending biometric result when the cubit closes', () async {
    await cubit.loadAvailability();
    final Completer<void> unlockStarted = Completer<void>();
    final Completer<void> releaseUnlock = Completer<void>();
    repository.unlockStarted = unlockStarted;
    repository.releaseUnlock = releaseUnlock;

    final Future<void> unlock = cubit.unlock();
    await unlockStarted.future;
    await cubit.close();

    releaseUnlock.complete();
    await unlock;

    expect(sessionController.state, isA<LockedSession>());
    expect(onUnlockedCalls, 0);
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
  Completer<void>? unlockStarted;
  Completer<void>? releaseUnlock;
  var unlockCount = 0;
  var configured = true;

  @override
  bool get hasBiometricUnlock => configured;

  @override
  Future<void> disableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  }) async => configured = false;

  @override
  Future<void> enableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  }) async => configured = true;

  @override
  Future<bool> hasConfiguredBiometricUnlock() async => configured;

  @override
  Future<void> unlockWithBiometric({
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    unlockCount++;
    unlockStarted?.complete();
    final Completer<void>? release = releaseUnlock;
    if (release != null) await release.future;
    activityGuard.ensureActive();
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
