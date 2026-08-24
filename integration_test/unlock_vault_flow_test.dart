import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/crypto/sodium_crypto_service.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/unlock_vault.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/vault/domain/add_vault_entry.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adds an entry then locks and re-unlocks an existing vault', (
    WidgetTester tester,
  ) async {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    final String vaultPath =
        '${supportDirectory.path}/unlock-flow-'
        '${DateTime.now().microsecondsSinceEpoch}.pswv';
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: await SodiumCryptoService.initialize(),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => vaultPath,
    );
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final VaultEntriesCubit entriesCubit = VaultEntriesCubit(
      AddVaultEntry(repository),
      repository,
      sessionController,
    );
    sessionController.registerSecretCleaner(
      SessionSecretCleaners(<SessionSecretCleaner>[repository, entriesCubit]),
    );
    final UnlockCubit unlockCubit = UnlockCubit(
      UnlockVault(repository),
      sessionController,
      onUnlocked: entriesCubit.refresh,
    );

    try {
      await repository.createEmptyVault(
        masterPassword: 'correct integration password',
        kdfParameters: const Argon2idParameters(
          memoryKiB: 8192,
          iterations: 2,
          parallelism: 1,
        ),
      );

      await unlockCubit.submit('correct integration password');
      expect(repository.hasUnlockedSession, isTrue);
      expect(sessionController.routeState, SessionRouteState.home);
      await entriesCubit.add(
        const NewVaultEntry(
          name: 'Integration entry',
          username: 'integration-user',
          password: 'integration-only-secret',
          notes: 'detail-only integration notes',
        ),
      );
      expect(repository.entrySummaries, hasLength(1));
      expect(repository.entrySummaries.single.name, 'Integration entry');
      expect(entriesCubit.state.summaries, hasLength(1));
      final EntryDetail detail = await entriesCubit.detail(
        repository.entrySummaries.single.entryId,
      );
      await entriesCubit.update(detail.entry.copyWith(name: 'Updated entry'));
      expect(repository.entrySummaries.single.name, 'Updated entry');
      final EntryDetail updatedDetail = await entriesCubit.detail(
        repository.entrySummaries.single.entryId,
      );
      expect(updatedDetail.entry.name, 'Updated entry');
      expect(updatedDetail.entry.password, 'integration-only-secret');

      sessionController.lock(LockReason.manualLock);
      expect(repository.hasUnlockedSession, isFalse);
      expect(repository.entrySummaries, isEmpty);
      expect(entriesCubit.state.summaries, isEmpty);
      expect(sessionController.routeState, SessionRouteState.unlock);

      await unlockCubit.submit('correct integration password');
      expect(repository.hasUnlockedSession, isTrue);
      expect(sessionController.routeState, SessionRouteState.home);
      expect(repository.entrySummaries.single.name, 'Updated entry');
      expect(entriesCubit.state.summaries.single.name, 'Updated entry');
      final EntryDetail reloadedDetail = await entriesCubit.detail(
        repository.entrySummaries.single.entryId,
      );
      expect(reloadedDetail.entry.name, 'Updated entry');
      expect(reloadedDetail.entry.password, 'integration-only-secret');
      await entriesCubit.delete(repository.entrySummaries.single.entryId);
      expect(repository.entrySummaries, isEmpty);
      sessionController.lock(LockReason.manualLock);
      await unlockCubit.submit('correct integration password');
      expect(repository.entrySummaries, isEmpty);
      expect(entriesCubit.state.summaries, isEmpty);
    } finally {
      unlockCubit.close();
      entriesCubit.close();
      sessionController.dispose();
      repository.clearUnlockedSession();
      final File vault = File(vaultPath);
      if (vault.existsSync()) {
        vault.deleteSync();
      }
      final File backup = File('$vaultPath.bak');
      if (backup.existsSync()) {
        backup.deleteSync();
      }
    }
  });
}
