import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  late Directory temporaryDirectory;
  late String vaultPath;
  late FakeBiometricKeyStore keyStore;
  late EncryptedVaultRepository repository;

  setUp(() async {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_biometric_repository_test_',
    );
    vaultPath = '${temporaryDirectory.path}/vault.psw';
    keyStore = FakeBiometricKeyStore();
    repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => vaultPath,
      biometricKeyStore: keyStore,
    );
    await repository.createEmptyVault(
      masterPassword: 'correct password',
      kdfParameters: const Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
        parallelism: 1,
      ),
    );
    await repository.unlockWithMasterPassword('correct password');
    await repository.addEntry(
      const NewVaultEntry(name: 'Example', password: 'private'),
    );
  });

  tearDown(() {
    repository.clearUnlockedSession();
    temporaryDirectory.deleteSync(recursive: true);
  });

  test(
    'enables biometric access by storing only an MVK envelope in the file',
    () async {
      await repository.enableBiometricUnlock();

      final OpenVaultFile opened = VaultFileEngine().openVaultFile(vaultPath);
      expect(repository.hasBiometricUnlock, isTrue);
      expect(opened.header.flags & 0x01, 0x01);
      expect(opened.header.biometricWrappedMasterVaultKey, hasLength(72));
      expect(keyStore.createdKeys, hasLength(1));
    },
  );

  test(
    'reopens the same vault through biometric access after a restart',
    () async {
      await repository.enableBiometricUnlock();
      repository.clearUnlockedSession();

      final EncryptedVaultRepository restarted = EncryptedVaultRepository(
        crypto: FakeCryptoService(),
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => vaultPath,
        biometricKeyStore: keyStore,
      );
      addTearDown(restarted.clearUnlockedSession);

      expect(await restarted.hasConfiguredBiometricUnlock(), isTrue);
      await restarted.unlockWithBiometric();

      expect(restarted.hasUnlockedSession, isTrue);
      expect(restarted.entrySummaries.single.name, 'Example');
      expect(keyStore.loadedKeys, hasLength(1));
    },
  );

  test(
    'disabling biometric access removes the envelope and platform key',
    () async {
      await repository.enableBiometricUnlock();

      await repository.disableBiometricUnlock();

      final OpenVaultFile opened = VaultFileEngine().openVaultFile(vaultPath);
      expect(repository.hasBiometricUnlock, isFalse);
      expect(opened.header.flags & 0x01, 0);
      expect(opened.header.biometricWrappedMasterVaultKey, isNull);
      expect(keyStore.deleted, isTrue);
    },
  );

  test(
    'keeps the master-password path available when biometric access fails',
    () async {
      await repository.enableBiometricUnlock();
      repository.clearUnlockedSession();
      keyStore.loadFailure = const BiometricCancelledException();

      expect(
        repository.unlockWithBiometric(),
        throwsA(isA<BiometricCancelledException>()),
      );
      expect(repository.hasUnlockedSession, isFalse);

      await repository.unlockWithMasterPassword('correct password');
      expect(repository.hasUnlockedSession, isTrue);
    },
  );

  test('cleans unlocked key material before publishing a biometric lock', () {
    final SessionController controller = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
      secretCleaner: repository,
    );
    addTearDown(controller.dispose);

    controller.lock(LockReason.backgroundOrTimeout);

    expect(repository.hasUnlockedSession, isFalse);
    expect(controller.state, isA<LockedSession>());
  });
}

final class FakeBiometricKeyStore implements BiometricKeyStore {
  final List<Uint8List> createdKeys = <Uint8List>[];
  final List<Uint8List> loadedKeys = <Uint8List>[];
  Object? loadFailure;
  var deleted = false;
  Uint8List? _key;

  @override
  Future<BiometricAvailability> get availability async =>
      BiometricAvailability.available;

  @override
  Future<Uint8List> createAndStoreKey() async {
    _key = Uint8List.fromList(List<int>.generate(32, (int index) => index + 1));
    createdKeys.add(Uint8List.fromList(_key!));
    return Uint8List.fromList(_key!);
  }

  @override
  Future<Uint8List> loadKey() async {
    final Object? failure = loadFailure;
    if (failure != null) throw failure;
    final Uint8List? key = _key;
    if (key == null) {
      throw const BiometricUnavailableException();
    }
    loadedKeys.add(Uint8List.fromList(key));
    return Uint8List.fromList(key);
  }

  @override
  Future<void> deleteKey() async {
    _key = null;
    deleted = true;
  }
}
