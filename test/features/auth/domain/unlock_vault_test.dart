import 'dart:io';

import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/unlock_vault.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/shared/result.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  late Directory temporaryDirectory;
  late FakeCryptoService crypto;
  late EncryptedVaultRepository repository;

  setUp(() async {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_unlock_test_',
    );
    crypto = FakeCryptoService();
    repository = EncryptedVaultRepository(
      crypto: crypto,
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => '${temporaryDirectory.path}/vault.psw',
    );
    await repository.createEmptyVault(
      masterPassword: 'correct password',
      kdfParameters: const Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
      ),
    );
  });

  tearDown(() {
    repository.clearUnlockedSession();
    temporaryDirectory.deleteSync(recursive: true);
  });

  test(
    'returns success for a correct password and retains only the MVK',
    () async {
      final Result<UnlockedVault, UnlockFailure> result = await UnlockVault(
        repository,
      )('correct password');

      expect(result, isA<Success<UnlockedVault, UnlockFailure>>());
      expect(repository.hasUnlockedSession, isTrue);
    },
  );

  test('maps only a wrong password to invalidMasterPassword', () async {
    final Result<UnlockedVault, UnlockFailure> result = await UnlockVault(
      repository,
    )('wrong password');

    expect(result, isA<Failure<UnlockedVault, UnlockFailure>>());
    expect(
      (result as Failure<UnlockedVault, UnlockFailure>).failure,
      UnlockFailure.invalidMasterPassword,
    );
    expect(repository.hasUnlockedSession, isFalse);
  });

  test('does not turn a damaged header into a password failure', () async {
    final File vault = File('${temporaryDirectory.path}/vault.psw');
    final RandomAccessFile file = vault.openSync(mode: FileMode.write);
    file.writeByteSync(0);
    file.closeSync();
    File('${vault.path}.bak').deleteSync();

    expect(
      UnlockVault(repository)('correct password'),
      throwsA(isA<VaultCorruptedException>()),
    );
  });
}
