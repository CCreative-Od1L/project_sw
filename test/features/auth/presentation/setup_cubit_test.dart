import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/create_vault.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  test(
    'publishes the non-sensitive parameter report after creating a vault',
    () async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'project_sw_setup_cubit_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final FakeCryptoService crypto = FakeCryptoService();
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: crypto,
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => '${directory.path}/vault.psw',
      );
      final Argon2idBenchmark benchmark = Argon2idBenchmark(
        crypto,
        samplesPerTier: 1,
        profiles: const <Argon2idParameters>[
          Argon2idParameters(memoryKiB: 64 * 1024, iterations: 3),
        ],
      );
      final SetupCubit cubit = SetupCubit(CreateVault(repository, benchmark));
      addTearDown(cubit.close);

      await cubit.submit('test master password');

      expect(cubit.state, isA<SetupCompleted>());
      final SetupCompleted completed = cubit.state as SetupCompleted;
      expect(completed.result.tiers, hasLength(1));
      expect(completed.result.selectedParameters.memoryKiB, 64 * 1024);
      expect(File('${directory.path}/vault.psw').existsSync(), isTrue);
      expect(crypto.derivedKeys.every(_isCleared), isTrue);
    },
  );
}

bool _isCleared(List<int> bytes) => bytes.every((int byte) => byte == 0);
