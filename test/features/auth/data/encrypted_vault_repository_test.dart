import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
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
      final Uint8List kek = await crypto.deriveKek(
        'not logged',
        opened.header.kdfSalt,
        memoryKiB: 64 * 1024,
        iterations: 3,
        parallelism: 1,
      );
      try {
        final Uint8List unwrappedMvk = crypto.decryptWithAead(
          kek,
          Uint8List.fromList(
            opened.header.wrappedMasterVaultKey.sublist(0, 24),
          ),
          Uint8List.fromList(opened.header.wrappedMasterVaultKey.sublist(24)),
          Uint8List(0),
        );
        expect(unwrappedMvk, List<int>.generate(32, (int index) => index + 1));
      } finally {
        kek.fillRange(0, kek.length, 0);
      }
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

  test('clears the unlocked MVK before the session publishes a lock', () async {
    final FakeCryptoService crypto = FakeCryptoService();
    final String path = '${temporaryDirectory.path}/unlockable.psw';
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: crypto,
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => path,
    );
    await repository.createEmptyVault(
      masterPassword: 'correct password',
      kdfParameters: const Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
      ),
    );
    await repository.unlockWithMasterPassword('correct password');
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      secretCleaner: repository,
    );
    addTearDown(sessionController.dispose);

    sessionController.lock(LockReason.manualLock);

    expect(repository.hasUnlockedSession, isFalse);
    expect(crypto.decryptedKeys.every(_isCleared), isTrue);
    expect(sessionController.state, isA<LockedSession>());
  });

  test(
    'persists an encrypted entry and retains only its summary after unlock',
    () async {
      final FakeCryptoService crypto = FakeCryptoService();
      final String path = '${temporaryDirectory.path}/entries.psw';
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: crypto,
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => path,
      );
      await repository.createEmptyVault(
        masterPassword: 'correct password',
        kdfParameters: const Argon2idParameters(
          memoryKiB: 64 * 1024,
          iterations: 3,
        ),
      );
      await repository.unlockWithMasterPassword('correct password');

      final EntrySummary added = await repository.addEntry(
        const NewVaultEntry(
          name: 'Example',
          url: 'https://example.test',
          username: 'alice',
          password: 'never-in-summary',
          notes: 'also detail-only',
          favorite: true,
          customFields: <CustomField>[
            CustomField(label: 'PIN', value: '1234', secret: true),
          ],
        ),
      );

      expect(added.name, 'Example');
      expect(added.url, 'https://example.test');
      expect(added.username, 'alice');
      expect(added.favorite, isTrue);
      expect(repository.entrySummaries, hasLength(1));
      expect(
        VaultFileEngine().openVaultFile(path).directory.records,
        hasLength(1),
      );

      repository.clearUnlockedSession();
      expect(repository.entrySummaries, isEmpty);
      await repository.unlockWithMasterPassword('correct password');
      expect(repository.entrySummaries, hasLength(1));
      expect(repository.entrySummaries.single.name, 'Example');
      expect(repository.entrySummaries.single.favorite, isTrue);
    },
  );
}

bool _isCleared(List<int> bytes) => bytes.every((int byte) => byte == 0);
