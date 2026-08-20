import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

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
}

final class _SettingsPasswordChangeRepository
    implements MasterPasswordChangeRepository {
  final List<(String, String)> calls = <(String, String)>[];

  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    calls.add((currentMasterPassword, newMasterPassword));
  }
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
