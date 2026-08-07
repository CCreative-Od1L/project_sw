import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
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
