import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';

void main() {
  late FakeBiometricVaultRepository repository;
  late FakeBiometricKeyStore keyStore;
  late BiometricSettingsCubit cubit;

  setUp(() {
    repository = FakeBiometricVaultRepository();
    keyStore = FakeBiometricKeyStore();
    cubit = BiometricSettingsCubit(repository, keyStore);
  });

  tearDown(() => cubit.close());

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
}

final class FakeBiometricVaultRepository implements BiometricVaultRepository {
  var configured = false;
  var enableCount = 0;
  var disableCount = 0;

  @override
  bool get hasBiometricUnlock => configured;

  @override
  Future<void> disableBiometricUnlock() async {
    disableCount++;
    configured = false;
  }

  @override
  Future<void> enableBiometricUnlock() async {
    enableCount++;
    configured = true;
  }

  @override
  Future<bool> hasConfiguredBiometricUnlock() async => configured;

  @override
  Future<void> unlockWithBiometric() async {}
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
