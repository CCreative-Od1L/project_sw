import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_repository_test_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test(
    'writes a decryptable empty-vault header and clears temporary keys',
    () async {
      final FakeCryptoService crypto = FakeCryptoService();
      final String path = '${temporaryDirectory.path}/vault.psw';
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: crypto,
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => path,
      );

      await repository.createEmptyVault(
        masterPassword: 'not logged',
        kdfParameters: const Argon2idParameters(
          memoryKiB: 64 * 1024,
          iterations: 3,
        ),
      );

      final OpenVaultFile opened = VaultFileEngine().openVaultFile(path);
      expect(opened.header.kdfParameters.memoryKiB, 64 * 1024);
      expect(opened.header.wrappedMasterVaultKey, hasLength(72));
      final Uint8List unwrappedMvk = crypto.decryptWithAead(
        Uint8List(32),
        Uint8List.fromList(opened.header.wrappedMasterVaultKey.sublist(0, 24)),
        Uint8List.fromList(opened.header.wrappedMasterVaultKey.sublist(24)),
        Uint8List(0),
      );
      expect(unwrappedMvk, List<int>.generate(32, (int index) => index + 1));
      expect(crypto.derivedKeys.every(_isCleared), isTrue);
      expect(crypto.generatedKeys.every(_isCleared), isTrue);
    },
  );

  test('normalizes a storage location failure as VaultIoException', () async {
    final File blocker = File('${temporaryDirectory.path}/blocker')
      ..createSync();
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => '${blocker.path}/vault.psw',
    );

    expect(
      repository.createEmptyVault(
        masterPassword: 'not logged',
        kdfParameters: const Argon2idParameters(
          memoryKiB: 64 * 1024,
          iterations: 3,
        ),
      ),
      throwsA(isA<VaultIoException>()),
    );
  });

  test('preserves a normalized crypto initialization failure', () async {
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(
        derivationFailure: const CryptoInitializationException(),
      ),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => '${temporaryDirectory.path}/vault.psw',
    );

    expect(
      repository.createEmptyVault(
        masterPassword: 'not logged',
        kdfParameters: const Argon2idParameters(
          memoryKiB: 64 * 1024,
          iterations: 3,
        ),
      ),
      throwsA(isA<CryptoInitializationException>()),
    );
  });
}

bool _isCleared(List<int> bytes) => bytes.every((int byte) => byte == 0);
