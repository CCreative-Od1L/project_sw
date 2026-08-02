import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/vault/domain/add_vault_entry.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';

import 'helpers/fake_crypto_service.dart';

void main() {
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

  testWidgets('home saves and displays only an EntrySummary', (
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

    sessionController.lock(LockReason.manualLock);
    await tester.pumpAndSettle();
    expect(entriesCubit.state.summaries, isEmpty);
  });
}
