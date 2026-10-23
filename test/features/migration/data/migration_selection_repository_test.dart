import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  test(
    'single export reads only the selected entry; vanished selection fails closed',
    () async {
      final directory = Directory.systemTemp.createTempSync('migration_scope_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final repository = EncryptedVaultRepository(
        crypto: FakeCryptoService(),
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => '${directory.path}/vault.psw',
      );
      addTearDown(repository.clearUnlockedSession);
      await repository.createEmptyVault(
        masterPassword: 'correct password',
        kdfParameters: const Argon2idParameters(
          memoryKiB: 65536,
          iterations: 3,
        ),
      );
      await repository.unlockWithMasterPassword(
        'correct password',
        activityGuard: const _Guard(),
      );
      await repository.addEntry(
        const NewVaultEntry(name: 'Excluded', password: 'other secret'),
        activityGuard: const _Guard(),
      );
      final selected = await repository.addEntry(
        const NewVaultEntry(name: 'Selected', password: 'selected secret'),
        activityGuard: const _Guard(),
      );
      final single = await repository.exportMigrationEntries(
        activityGuard: const _Guard(),
        selection: MigrationSelection.single(selected.entryId),
      );
      expect(single, hasLength(1));
      expect(single.single.entryId, selected.entryId);
      for (final payload in single) {
        payload.dispose();
      }
      final all = await repository.exportMigrationEntries(
        activityGuard: const _Guard(),
      );
      expect(all, hasLength(2));
      for (final payload in all) {
        payload.dispose();
      }
      await expectLater(
        repository.exportMigrationEntries(
          activityGuard: const _Guard(),
          selection: MigrationSelection.single(
            Uint8List.fromList(List<int>.filled(16, 255)),
          ),
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
    },
  );
}

final class _Guard implements SessionActivityGuard {
  const _Guard();
  @override
  void ensureActive() {}
}
