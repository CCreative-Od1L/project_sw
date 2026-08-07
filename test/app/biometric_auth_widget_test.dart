import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/app/pages/unlock_page.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('shows and uses the biometric unlock action', (
    WidgetTester tester,
  ) async {
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
      timerFactory: (Duration duration, void Function() callback) =>
          FakeSessionTimer(),
    );
    final BiometricUnlockCubit biometricCubit = BiometricUnlockCubit(
      FakeBiometricVaultRepository(),
      FakeBiometricKeyStore(),
      sessionController,
    );
    addTearDown(() {
      sessionController.lock(LockReason.manualLock);
      biometricCubit.close();
      sessionController.dispose();
    });

    await tester.pumpWidget(
      _localizedApp(
        UnlockPage(
          sessionController: sessionController,
          biometricUnlockCubit: biometricCubit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlock with biometrics'), findsOneWidget);
    await tester.tap(find.text('Unlock with biometrics'));
    await tester.pumpAndSettle();

    expect(sessionController.state, isA<UnlockedSession>());
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.biometric,
    );
  });

  testWidgets('renders the Material biometric settings card', (
    WidgetTester tester,
  ) async {
    final BiometricSettingsCubit settingsCubit = BiometricSettingsCubit(
      FakeBiometricVaultRepository(configured: false),
      FakeBiometricKeyStore(),
    );
    addTearDown(settingsCubit.close);

    await tester.pumpWidget(
      _localizedApp(SettingsPage(biometricSettingsCubit: settingsCubit)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Biometric unlock'), findsOneWidget);
    expect(find.text('Enable biometric unlock'), findsOneWidget);
    expect(find.textContaining('device-protected key'), findsOneWidget);
  });
}

final class FakeSessionTimer implements SessionTimer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;
}

Widget _localizedApp(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

final class FakeBiometricVaultRepository implements BiometricVaultRepository {
  FakeBiometricVaultRepository({this.configured = true});

  bool configured;

  @override
  bool get hasBiometricUnlock => configured;

  @override
  Future<void> disableBiometricUnlock() async => configured = false;

  @override
  Future<void> enableBiometricUnlock() async => configured = true;

  @override
  Future<bool> hasConfiguredBiometricUnlock() async => configured;

  @override
  Future<void> unlockWithBiometric() async {}
}

final class FakeBiometricKeyStore implements BiometricKeyStore {
  @override
  Future<BiometricAvailability> get availability async =>
      BiometricAvailability.available;

  @override
  Future<Uint8List> createAndStoreKey() async => Uint8List(32);

  @override
  Future<void> deleteKey() async {}

  @override
  Future<Uint8List> loadKey() async => Uint8List(32);
}
