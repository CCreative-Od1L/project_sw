import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/app/pages/unlock_page.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/presentation/step_up_cubit.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
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
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      timerFactory: (Duration duration, void Function() callback) =>
          FakeSessionTimer(),
    );
    final BiometricSettingsCubit settingsCubit = BiometricSettingsCubit(
      FakeBiometricVaultRepository(configured: false),
      FakeBiometricKeyStore(),
      sessionController: sessionController,
    );
    addTearDown(() {
      settingsCubit.close();
      sessionController.dispose();
    });

    await tester.pumpWidget(
      _localizedApp(SettingsPage(biometricSettingsCubit: settingsCubit)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Biometric unlock'), findsOneWidget);
    expect(find.text('Enable biometric unlock'), findsOneWidget);
    expect(find.textContaining('device-protected key'), findsOneWidget);
  });

  testWidgets('requires master-password step-up before changing biometrics', (
    WidgetTester tester,
  ) async {
    final FakeBiometricVaultRepository repository =
        FakeBiometricVaultRepository(configured: false);
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
      timerFactory: (Duration duration, void Function() callback) =>
          FakeSessionTimer(),
    );
    final StepUpCubit stepUpCubit = StepUpCubit(
      VerifyMasterPassword(FakeMasterPasswordVerifier()),
      sessionController,
    );
    final BiometricSettingsCubit settingsCubit = BiometricSettingsCubit(
      repository,
      FakeBiometricKeyStore(),
      sessionController: sessionController,
    );
    addTearDown(() {
      settingsCubit.close();
      stepUpCubit.close();
      sessionController.dispose();
    });

    await tester.pumpWidget(
      _localizedApp(
        SettingsPage(
          biometricSettingsCubit: settingsCubit,
          stepUpCubit: stepUpCubit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enable biometric unlock').last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Master password required'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wrong password');
    await tester.tap(find.text('Verify master password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('session was not changed'), findsOneWidget);
    expect(repository.enableCount, 0);
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.biometric,
    );

    await tester.enterText(find.byType(TextField), 'correct password');
    await tester.tap(find.text('Verify master password'));
    await tester.pumpAndSettle();

    expect(repository.enableCount, 1);
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.masterPassword,
    );
  });

  testWidgets('lock dismisses an open biometric step-up password dialog', (
    WidgetTester tester,
  ) async {
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
      timerFactory: (Duration _, void Function() _) => FakeSessionTimer(),
    );
    final StepUpCubit stepUpCubit = StepUpCubit(
      VerifyMasterPassword(FakeMasterPasswordVerifier()),
      sessionController,
    );
    final BiometricSettingsCubit settingsCubit = BiometricSettingsCubit(
      FakeBiometricVaultRepository(configured: false),
      FakeBiometricKeyStore(),
      sessionController: sessionController,
    );
    addTearDown(settingsCubit.close);
    addTearDown(stepUpCubit.close);
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      _localizedApp(
        SettingsPage(
          sessionController: sessionController,
          biometricSettingsCubit: settingsCubit,
          stepUpCubit: stepUpCubit,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enable biometric unlock').last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'step-up residual secret');

    sessionController.lock(LockReason.manualLock);
    await tester.pumpAndSettle();

    expect(find.text('Master password required'), findsNothing);
    expect(find.byType(TextField), findsNothing);
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
  var enableCount = 0;
  var disableCount = 0;

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
    configured = true;
  }

  @override
  Future<bool> hasConfiguredBiometricUnlock() async => configured;

  @override
  Future<void> unlockWithBiometric({
    required SessionActivityGuard activityGuard,
  }) async {}
}

final class FakeMasterPasswordVerifier implements MasterPasswordVerifier {
  @override
  Future<void> verifyMasterPassword(String masterPassword) async {
    if (masterPassword != 'correct password') {
      throw const InvalidMasterPasswordException();
    }
  }
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
