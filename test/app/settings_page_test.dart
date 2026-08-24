import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/authenticated_wipe_vault.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';
import 'package:project_sw/features/auth/domain/recovery/recover_master_password.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/features/auth/presentation/authenticated_wipe_cubit.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';

void main() {
  testWidgets('settings displays read-only policy and active KDF metadata', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(
          config: const AppConfig(
            idleTimeout: Duration(minutes: 5),
            sensitiveClipboardTimeout: Duration(seconds: 20),
          ),
          vaultRepository: SettingsVaultRepository(
            const Argon2idParameters(
              memoryKiB: 64 * 1024,
              iterations: 3,
              parallelism: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Security settings'), findsOneWidget);
    expect(
      find.text('Locks after 5 minutes without interaction.'),
      findsOneWidget,
    );
    expect(
      find.text('Locks immediately when the app enters the background.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The app attempts to clear copied values after 20 seconds; '
        'Android vendor clipboards and third-party keyboard clipboards may '
        'not be cleared.',
      ),
      findsOneWidget,
    );
    expect(find.text('Argon2id: m=64 MiB, t=3, p=1'), findsOneWidget);
    expect(find.text('detail secret'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('settings explains Android clipboard limits in Chinese', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(
          config: const AppConfig(
            sensitiveClipboardTimeout: Duration(seconds: 20),
          ),
          vaultRepository: SettingsVaultRepository(
            const Argon2idParameters(
              memoryKiB: 64 * 1024,
              iterations: 3,
              parallelism: 1,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('应用将尝试在 20 秒后清除复制的值；不保证 Android 各厂商及第三方输入法的剪贴板能够被正常清除。'),
      findsOneWidget,
    );
  });

  testWidgets('changes the master password from one security dialog', (
    WidgetTester tester,
  ) async {
    final _SettingsPasswordChangeRepository changeRepository =
        _SettingsPasswordChangeRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
      timerFactory: (Duration _, void Function() _) => _SettingsSessionTimer(),
    );
    final MasterPasswordChangeCubit changeCubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(changeRepository),
      sessionController,
    );
    addTearDown(changeCubit.close);
    addTearDown(sessionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(masterPasswordChangeCubit: changeCubit),
      ),
    );

    final Finder changeButton = find.text('Change master password');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(changeButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('current-master-password')),
      'current password',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('new-master-password')),
      'new password',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('confirm-new-master-password')),
      'new password',
    );
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();

    expect(changeRepository.calls, <(String, String)>[
      ('current password', 'new password'),
    ]);
    expect(find.text('Master password changed'), findsOneWidget);
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.masterPassword,
    );
  });

  testWidgets('reveals biometric recovery with a takeover warning', (
    WidgetTester tester,
  ) async {
    final _SettingsRecoveryStore store = _SettingsRecoveryStore();
    final MasterPasswordRecoveryGate gate = MasterPasswordRecoveryGate(store);
    final _SettingsRecoveryRepository recoveryRepository =
        _SettingsRecoveryRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
      timerFactory: (Duration _, void Function() _) => _SettingsSessionTimer(),
    );
    final MasterPasswordChangeCubit changeCubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(
        _SettingsPasswordChangeRepository(
          error: const InvalidMasterPasswordException(),
        ),
      ),
      sessionController,
      recoveryGate: gate,
      hasConfiguredBiometricRecovery: () async => true,
      recoverMasterPassword: RecoverMasterPassword(
        gate: gate,
        biometricConfirmer: _SettingsRecoveryConfirmer(),
        repository: recoveryRepository,
      ),
    );
    addTearDown(changeCubit.close);
    addTearDown(sessionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(masterPasswordChangeCubit: changeCubit),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change master password'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('current-master-password')),
      'wrong password',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('new-master-password')),
      'new password',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('confirm-new-master-password')),
      'new password',
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Recover with biometrics'), findsOneWidget);
    await tester.tap(find.text('Recover with biometrics'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Anyone who passes this biometric check can take over the vault by '
        'setting a new master password. Continue only on a trusted device.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('current-master-password')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('new-master-password')),
      'recovered password',
    );
    await tester.pump();
    expect(find.text('Password strength: Strong'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('confirm-new-master-password')),
      'recovered password',
    );
    await tester.tap(find.text('Recover password'));
    await tester.pumpAndSettle();

    expect(recoveryRepository.passwords, <String>['recovered password']);
    expect(find.text('Master password recovered'), findsOneWidget);
    expect(
      find.text('Update any backup device with the new master password.'),
      findsOneWidget,
    );
  });

  testWidgets('rejects normal deletion before a current password verifies', (
    WidgetTester tester,
  ) async {
    final _SettingsWipeRepository repository = _SettingsWipeRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      timerFactory: (Duration _, void Function() _) => _SettingsSessionTimer(),
    );
    final AuthenticatedWipeCubit wipeCubit = AuthenticatedWipeCubit(
      AuthenticatedWipeVault(
        VerifyMasterPassword(
          _SettingsWipeVerifier(error: const InvalidMasterPasswordException()),
        ),
        WipeVault(repository, sessionController),
      ),
    );
    addTearDown(wipeCubit.close);
    addTearDown(sessionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(authenticatedWipeCubit: wipeCubit),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permanently delete vault'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Enter the current master password'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('authenticated-wipe-password')),
      'wrong password',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Permanently delete vault').last,
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The current master password is incorrect. Nothing was deleted.',
      ),
      findsOneWidget,
    );
    expect(repository.calls, 0);
    expect(sessionController.state, isA<UnlockedSession>());
  });
}

final class _SettingsPasswordChangeRepository
    implements MasterPasswordChangeRepository {
  _SettingsPasswordChangeRepository({this.error});

  final Object? error;
  final List<(String, String)> calls = <(String, String)>[];

  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    calls.add((currentMasterPassword, newMasterPassword));
    final Object? failure = error;
    if (failure != null) throw failure;
  }
}

final class _SettingsRecoveryStore implements MasterPasswordRecoveryStore {
  MasterPasswordRecoveryMetadata metadata =
      const MasterPasswordRecoveryMetadata();

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

final class _SettingsRecoveryConfirmer implements BiometricRecoveryConfirmer {
  @override
  Future<void> confirm() async {}
}

final class _SettingsRecoveryRepository
    implements MasterPasswordRecoveryRepository {
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

final class _SettingsWipeVerifier implements MasterPasswordVerifier {
  _SettingsWipeVerifier({this.error});

  final Object? error;

  @override
  Future<void> verifyMasterPassword(String masterPassword) async {
    final Object? failure = error;
    if (failure != null) throw failure;
  }
}

final class _SettingsWipeRepository implements VaultWipeRepository {
  var calls = 0;

  @override
  Future<void> wipeVault() async => calls++;
}

final class _SettingsSessionTimer implements SessionTimer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;
}

final class SettingsVaultRepository implements VaultRepository {
  SettingsVaultRepository(this._parameters);

  final Argon2idParameters _parameters;

  @override
  Argon2idParameters get activeKdfParameters => _parameters;

  @override
  Future<void> createEmptyVault({
    required String masterPassword,
    required Argon2idParameters kdfParameters,
  }) async => throw UnimplementedError();

  @override
  Future<void> unlockWithMasterPassword(String masterPassword) async =>
      throw UnimplementedError();

  @override
  bool get hasUnlockedSession => true;

  @override
  Future<EntrySummary> addEntry(NewVaultEntry entry) async =>
      throw UnimplementedError();

  @override
  List<EntrySummary> get entrySummaries => const <EntrySummary>[];

  @override
  Future<EntryDetail> getEntryDetail(Uint8List entryId) async =>
      throw UnimplementedError();

  @override
  Future<EntrySummary> updateEntry(VaultEntry entry) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteEntry(Uint8List entryId) async =>
      throw UnimplementedError();

  @override
  void clearUnlockedSession() {}
}
