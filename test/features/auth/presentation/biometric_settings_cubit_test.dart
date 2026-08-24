import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';

void main() {
  late FakeBiometricVaultRepository repository;
  late FakeBiometricKeyStore keyStore;
  late SessionController sessionController;
  late BiometricSettingsCubit cubit;

  setUp(() {
    repository = FakeBiometricVaultRepository();
    keyStore = FakeBiometricKeyStore();
    sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    cubit = BiometricSettingsCubit(
      repository,
      keyStore,
      sessionController: sessionController,
    );
  });

  tearDown(() {
    cubit.close();
    sessionController.dispose();
  });

  test(
    'loads the configured state and enables, disables, and resets access',
    () async {
      await cubit.load();
      expect((cubit.state as BiometricSettingsReady).isConfigured, isFalse);

      await cubit.enable();
      expect((cubit.state as BiometricSettingsReady).isConfigured, isTrue);
      expect(repository.enableCount, 1);

      await cubit.disable();
      expect((cubit.state as BiometricSettingsReady).isConfigured, isFalse);
      expect(repository.disableCount, 1);

      await cubit.enable();
      expect(repository.enableCount, 2);
    },
  );

  test('reports unavailable hardware without attempting setup', () async {
    keyStore.currentAvailability = BiometricAvailability.unavailable;

    await cubit.load();

    final BiometricSettingsReady state = cubit.state as BiometricSettingsReady;
    expect(state.isAvailable, isFalse);
    await cubit.enable();
    expect(repository.enableCount, 0);
  });

  test('locks the session when biometric enrollment is invalidated', () async {
    final SessionController invalidationController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    addTearDown(invalidationController.dispose);
    repository.enableFailure = const BiometricInvalidatedException();
    final BiometricSettingsCubit invalidationCubit = BiometricSettingsCubit(
      repository,
      keyStore,
      sessionController: invalidationController,
    );
    addTearDown(invalidationCubit.close);

    await invalidationCubit.load();
    await invalidationCubit.enable();

    expect(invalidationCubit.state, isA<BiometricSettingsInvalidated>());
    expect(invalidationController.state, isA<LockedSession>());
    expect(
      (invalidationController.state as LockedSession).reason,
      LockReason.biometricInvalidated,
    );
  });

  test('does not publish configuration after lock interruption', () async {
    repository.blockNextEnable();
    await cubit.load();

    final Future<void> enable = cubit.enable();
    await repository.enableStarted.future;
    expect(
      (sessionController.state as UnlockedSession).activity,
      SessionActivity.biometricConfiguration,
    );

    sessionController.lock(LockReason.backgroundOrTimeout);
    repository.completeEnable();
    await enable;

    expect(cubit.state, isA<BiometricSettingsLoading>());
    expect(repository.configured, isFalse);
    expect(sessionController.state, isA<LockedSession>());
  });

  test('drops a metadata load owned by an older session', () async {
    keyStore.blockNextAvailability();
    final Future<void> load = cubit.load();
    await keyStore.availabilityStarted.future;

    sessionController.lock(LockReason.backgroundOrTimeout);
    sessionController.unlock(AuthStrength.masterPassword);
    keyStore.completeAvailability();
    await load;

    expect(cubit.state, isA<BiometricSettingsLoading>());
  });

  test('releases its activity when a session listener closes it', () async {
    await cubit.load();
    final subscription = sessionController.states.listen((SessionState state) {
      if (state case UnlockedSession(
        activity: SessionActivity.biometricConfiguration,
      )) {
        unawaited(cubit.close());
      }
    });
    addTearDown(subscription.cancel);

    await cubit.enable();

    expect(
      (sessionController.state as UnlockedSession).activity,
      SessionActivity.none,
    );
  });
}

final class FakeBiometricVaultRepository implements BiometricVaultRepository {
  var configured = false;
  var enableCount = 0;
  var disableCount = 0;
  Object? enableFailure;
  final Completer<void> enableStarted = Completer<void>();
  Completer<void>? _enableCompletion;

  void blockNextEnable() => _enableCompletion = Completer<void>();

  void completeEnable() => _enableCompletion?.complete();

  @override
  bool get hasBiometricUnlock => configured;

  @override
  Future<void> disableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    disableCount++;
    configured = false;
  }

  @override
  Future<void> enableBiometricUnlock({
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    enableCount++;
    final Object? failure = enableFailure;
    if (failure != null) throw failure;
    final Completer<void>? pending = _enableCompletion;
    if (pending != null) {
      if (!enableStarted.isCompleted) enableStarted.complete();
      await pending.future;
    }
    activityGuard.ensureActive();
    configured = true;
  }

  @override
  Future<bool> hasConfiguredBiometricUnlock() async => configured;

  @override
  Future<void> unlockWithBiometric({
    required SessionActivityGuard activityGuard,
  }) async {}
}

final class FakeBiometricKeyStore implements BiometricKeyStore {
  BiometricAvailability currentAvailability = BiometricAvailability.available;
  final Completer<void> availabilityStarted = Completer<void>();
  Completer<void>? _availabilityCompletion;

  void blockNextAvailability() => _availabilityCompletion = Completer<void>();

  void completeAvailability() => _availabilityCompletion?.complete();

  @override
  Future<BiometricAvailability> get availability async {
    final Completer<void>? pending = _availabilityCompletion;
    if (pending != null) {
      if (!availabilityStarted.isCompleted) availabilityStarted.complete();
      await pending.future;
    }
    return currentAvailability;
  }

  @override
  Future<Uint8List> createAndStoreKey() async => Uint8List(32);

  @override
  Future<void> deleteKey() async {}

  @override
  Future<Uint8List> loadKey() async => Uint8List(32);
}
