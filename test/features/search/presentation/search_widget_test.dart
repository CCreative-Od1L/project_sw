import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/home_page.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_timer.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/vault/domain/add_vault_entry.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('searches safe summary fields and clears with a lock', (
    WidgetTester tester,
  ) async {
    final InMemoryVaultRepository repository =
        InMemoryVaultRepository(<EntrySummary>[
          _summary(
            id: 1,
            name: 'Work portal',
            url: 'https://portal.test',
            username: 'Alice',
            favorite: true,
          ),
          _summary(
            id: 2,
            name: 'Documentation',
            url: 'https://docs.test',
            username: 'Bob',
          ),
        ]);
    final VaultEntriesCubit entriesCubit = VaultEntriesCubit(
      AddVaultEntry(repository),
      repository,
    );
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      secretCleaner: entriesCubit,
      timerFactory: (Duration _, void Function() _) =>
          const InactiveSessionTimer(),
    );
    addTearDown(entriesCubit.close);
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      _localizedApp(
        HomePage(
          sessionController: sessionController,
          vaultEntriesCubit: entriesCubit,
        ),
      ),
    );

    final Finder searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'ALICE');
    await tester.pump();
    expect(find.text('Work portal'), findsOneWidget);
    expect(find.text('Documentation'), findsNothing);

    await tester.enterText(searchField, 'detail-password');
    await tester.pump();
    expect(find.text('No entries match your search.'), findsOneWidget);

    await tester.enterText(searchField, '');
    await tester.tap(find.text('Favorites only'));
    await tester.pump();
    expect(find.text('Work portal'), findsOneWidget);
    expect(find.text('Documentation'), findsNothing);

    sessionController.lock(LockReason.backgroundOrTimeout);
    await tester.pump();
    expect(find.text('No entries have been added yet.'), findsOneWidget);

    sessionController.unlock(AuthStrength.masterPassword);
    entriesCubit.refresh();
    await tester.pump();
    expect(find.text('Work portal'), findsOneWidget);
    expect(find.text('Documentation'), findsOneWidget);
  });
}

Widget _localizedApp(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  localeResolutionCallback: (Locale? locale, Iterable<Locale> supported) =>
      resolveAppLocale(locale),
  home: child,
);

EntrySummary _summary({
  required int id,
  required String name,
  required String url,
  required String username,
  bool favorite = false,
}) => EntrySummary(
  entryId: Uint8List.fromList(<int>[...List<int>.filled(15, 0), id]),
  name: name,
  url: url,
  username: username,
  favorite: favorite,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

final class InMemoryVaultRepository implements VaultRepository {
  InMemoryVaultRepository(this._summaries);

  final List<EntrySummary> _summaries;

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
  List<EntrySummary> get entrySummaries =>
      List<EntrySummary>.unmodifiable(_summaries);

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

final class InactiveSessionTimer implements SessionTimer {
  const InactiveSessionTimer();

  @override
  bool get isActive => false;

  @override
  void cancel() {}
}
