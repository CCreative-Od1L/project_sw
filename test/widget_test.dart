import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/create_vault.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
import 'package:project_sw/features/vault/domain/add_vault_entry.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';

import 'helpers/fake_crypto_service.dart';

void main() {
  testWidgets('background clears clipboard state even while already locked', (
    WidgetTester tester,
  ) async {
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final AuthCubit authCubit = AuthCubit(sessionController);
    final _WidgetClipboard clipboard = _WidgetClipboard();
    final SensitiveClipboardController clipboardController =
        SensitiveClipboardController(clipboard);
    addTearDown(clipboardController.dispose);
    addTearDown(authCubit.close);
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      ProjectSwApp(
        sessionController: sessionController,
        authCubit: authCubit,
        sensitiveClipboardController: clipboardController,
      ),
    );
    await clipboardController.copySensitive('locked generator secret');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(sessionController.state, isA<LockedSession>());
    expect(clipboardController.state.status, SensitiveClipboardStatus.idle);
    expect(clipboard.value, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('session changes drive setup, unlock, and home routes', (
    WidgetTester tester,
  ) async {
    final SessionController sessionController = SessionController();
    final AuthCubit authCubit = AuthCubit(sessionController);
    addTearDown(authCubit.close);
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      ProjectSwApp(sessionController: sessionController, authCubit: authCubit),
    );

    expect(find.text('Create your vault'), findsOneWidget);

    sessionController.markVaultCreated();
    await tester.pumpAndSettle();

    expect(find.text('Unlock your vault'), findsOneWidget);

    sessionController.unlock(AuthStrength.masterPassword);
    await tester.pumpAndSettle();

    expect(find.text('Vault unlocked'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock vault'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock your vault'), findsOneWidget);
  });

  testWidgets(
    'setup confirms the selected parameters before routing to unlock',
    (WidgetTester tester) async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'project_sw_setup_page_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final FakeCryptoService crypto = FakeCryptoService();
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: crypto,
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => '${directory.path}/vault.psw',
      );
      final SetupCubit setupCubit = SetupCubit(
        CreateVault(
          repository,
          Argon2idBenchmark(
            crypto,
            samplesPerTier: 1,
            profiles: const <Argon2idParameters>[
              Argon2idParameters(memoryKiB: 64 * 1024, iterations: 3),
            ],
          ),
        ),
      );
      final SessionController sessionController = SessionController();
      final AuthCubit authCubit = AuthCubit(sessionController);
      addTearDown(setupCubit.close);
      addTearDown(authCubit.close);
      addTearDown(sessionController.dispose);

      await tester.pumpWidget(
        ProjectSwApp(
          sessionController: sessionController,
          authCubit: authCubit,
          setupCubit: setupCubit,
        ),
      );
      await tester.enterText(
        find.bySemanticsLabel('Master password'),
        'test password',
      );
      await tester.tap(find.text('Create vault'));
      await tester.pumpAndSettle();

      expect(find.text('Vault created'), findsOneWidget);
      expect(find.text('Argon2id: m=64 MiB, t=3, p=1'), findsOneWidget);
      expect(sessionController.routeState, SessionRouteState.setup);

      await tester.tap(find.text('Continue to unlock'));
      await tester.pumpAndSettle();

      expect(sessionController.routeState, SessionRouteState.unlock);
      expect(find.text('Unlock your vault'), findsOneWidget);
    },
  );

  testWidgets('home shows an entry on demand, updates it, and deletes it', (
    WidgetTester tester,
  ) async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'project_sw_home_test_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => '${directory.path}/vault.psw',
    );
    await repository.createEmptyVault(
      masterPassword: 'correct password',
      kdfParameters: const Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
      ),
    );
    await repository.unlockWithMasterPassword('correct password');
    final VaultEntriesCubit entriesCubit = VaultEntriesCubit(
      AddVaultEntry(repository),
      repository,
    );
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      secretCleaner: SessionSecretCleaners(<SessionSecretCleaner>[
        repository,
        entriesCubit,
      ]),
    );
    final AuthCubit authCubit = AuthCubit(sessionController);
    addTearDown(entriesCubit.close);
    addTearDown(authCubit.close);
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      ProjectSwApp(
        sessionController: sessionController,
        authCubit: authCubit,
        vaultEntriesCubit: entriesCubit,
      ),
    );
    await tester.enterText(find.bySemanticsLabel('Name'), 'Example');
    await tester.enterText(find.bySemanticsLabel('Username'), 'alice');
    await tester.enterText(find.bySemanticsLabel('Password'), 'detail secret');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();

    expect(find.text('Example'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('detail secret'), findsNothing);

    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();

    final Finder detailDialog = find.byType(AlertDialog);
    expect(detailDialog, findsOneWidget);
    expect(find.text('Entry detail'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: detailDialog,
        matching: find.bySemanticsLabel('Name'),
      ),
      'Updated example',
    );
    await tester.tap(
      find.descendant(of: detailDialog, matching: find.text('Save')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Updated example'), findsOneWidget);

    await tester.tap(find.text('Updated example'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No entries have been added yet.'), findsOneWidget);

    sessionController.lock(LockReason.manualLock);
    await tester.pumpAndSettle();
    expect(entriesCubit.state.summaries, isEmpty);
  });
}

final class _WidgetClipboard implements ClipboardPort {
  String value = '';

  @override
  Future<void> writeText(String value) async => this.value = value;

  @override
  Future<String?> readText() async => value;

  @override
  Future<void> clearText() async => value = '';
}
