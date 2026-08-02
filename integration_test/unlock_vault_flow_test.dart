import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/crypto/sodium_crypto_service.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/unlock_vault.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unlocks, manually locks, and re-unlocks an existing vault', (
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
      secretCleaner: repository,
    );
    final UnlockCubit unlockCubit = UnlockCubit(
      UnlockVault(repository),
      sessionController,
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

      sessionController.lock(LockReason.manualLock);
      expect(repository.hasUnlockedSession, isFalse);
      expect(sessionController.routeState, SessionRouteState.unlock);

      await unlockCubit.submit('correct integration password');
      expect(repository.hasUnlockedSession, isTrue);
      expect(sessionController.routeState, SessionRouteState.home);
    } finally {
      unlockCubit.close();
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
