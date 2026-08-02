import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/unlock_vault.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';

import '../../../helpers/fake_crypto_service.dart';

enum _VaultTamperTarget { header, directory, entryBlock }

void main() {
  late Directory temporaryDirectory;
  late String vaultPath;
  late EncryptedVaultRepository repository;
  late SessionController sessionController;
  late UnlockCubit unlockCubit;

  setUp(() async {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_unlock_cubit_test_',
    );
    vaultPath = '${temporaryDirectory.path}/vault.psw';
    repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => vaultPath,
    );
    await repository.createEmptyVault(
      masterPassword: 'correct password',
      kdfParameters: const Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
      ),
    );
    await repository.unlockWithMasterPassword('correct password');
    await repository.addEntry(
      const NewVaultEntry(
        name: 'Sensitive entry name',
        password: 'entry-secret-must-not-leak',
      ),
    );
    repository.clearUnlockedSession();
    sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    unlockCubit = UnlockCubit(UnlockVault(repository), sessionController);
  });

  tearDown(() {
    unlockCubit.close();
    sessionController.dispose();
    repository.clearUnlockedSession();
    temporaryDirectory.deleteSync(recursive: true);
  });

  for (final _VaultTamperTarget target in _VaultTamperTarget.values) {
    test(
      'presents a safe unlock fault for a tampered ${target.name}',
      () async {
        final VaultEntryRecord record = VaultFileEngine()
            .openVaultFile(vaultPath)
            .directory
            .records
            .single;
        final int offset = switch (target) {
          _VaultTamperTarget.header => 0,
          _VaultTamperTarget.directory => vaultFileHeaderLength,
          _VaultTamperTarget.entryBlock =>
            record.blockOffset + record.blockLength - 1,
        };
        _tamperByte(vaultPath, offset);
        _tamperByte('$vaultPath.bak', offset);

        await unlockCubit.submit('correct password');

        expect(unlockCubit.state, isA<UnlockFault>());
        expect(unlockCubit.state, isNot(isA<UnlockInvalidPassword>()));
        expect(unlockCubit.state.toString(), isNot(contains('entry-secret')));
        expect(repository.hasUnlockedSession, isFalse);
        expect(repository.entrySummaries, isEmpty);
        expect(sessionController.routeState, SessionRouteState.unlock);
      },
    );
  }
}

void _tamperByte(String path, int offset) {
  final File file = File(path);
  final List<int> bytes = file.readAsBytesSync();
  bytes[offset] ^= 0xff;
  file.writeAsBytesSync(bytes, flush: true);
  bytes.fillRange(0, bytes.length, 0);
}
