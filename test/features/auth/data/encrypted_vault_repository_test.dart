import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
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

  test('exposes active KDF parameters only while unlocked', () async {
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async =>
          '${temporaryDirectory.path}/kdf-settings.psw',
    );
    const Argon2idParameters parameters = Argon2idParameters(
      memoryKiB: 64 * 1024,
      iterations: 3,
      parallelism: 1,
    );

    expect(repository.activeKdfParameters, isNull);
    await repository.createEmptyVault(
      masterPassword: 'correct password',
      kdfParameters: parameters,
    );
    expect(repository.activeKdfParameters, isNull);

    await repository.unlockWithMasterPassword('correct password');
    expect(repository.activeKdfParameters?.memoryKiB, parameters.memoryKiB);
    expect(repository.activeKdfParameters?.iterations, parameters.iterations);
    expect(repository.activeKdfParameters?.parallelism, parameters.parallelism);

    repository.clearUnlockedSession();
    expect(repository.activeKdfParameters, isNull);
  });

  test(
    'verifies a master password without clearing the unlocked session',
    () async {
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: FakeCryptoService(),
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => '${temporaryDirectory.path}/step-up.psw',
      );
      const Argon2idParameters parameters = Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
        parallelism: 1,
      );

      await repository.createEmptyVault(
        masterPassword: 'correct password',
        kdfParameters: parameters,
      );
      await repository.unlockWithMasterPassword('correct password');

      await repository.verifyMasterPassword('correct password');
      expect(repository.hasUnlockedSession, isTrue);
      expect(repository.activeKdfParameters, isNotNull);

      await expectLater(
        repository.verifyMasterPassword('wrong password'),
        throwsA(isA<InvalidMasterPasswordException>()),
      );
      expect(repository.hasUnlockedSession, isTrue);
      expect(repository.activeKdfParameters, isNotNull);
    },
  );

  test(
    'changes only the master-password envelope and keeps vault data readable',
    () async {
      final FakeCryptoService crypto = FakeCryptoService();
      final VaultFileEngine engine = VaultFileEngine();
      final String path = '${temporaryDirectory.path}/change-password.psw';
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: crypto,
        vaultFileEngine: engine,
        vaultPathResolver: () async => path,
      );
      const Argon2idParameters parameters = Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
        parallelism: 1,
      );
      await repository.createEmptyVault(
        masterPassword: 'current password',
        kdfParameters: parameters,
      );
      await repository.unlockWithMasterPassword('current password');
      final EntrySummary summary = await repository.addEntry(
        const NewVaultEntry(
          name: 'Envelope test',
          password: 'entry ciphertext must not change',
        ),
      );
      final OpenVaultFile beforeBiometric = engine.openVaultFile(path);
      final Uint8List biometricEnvelope = Uint8List.fromList(
        List<int>.filled(72, 0x5a),
      );
      engine.commitHeaderUpdate(
        path: path,
        opened: beforeBiometric,
        header: beforeBiometric.header.copyWithBiometric(biometricEnvelope),
      );
      final Uint8List beforeBytes = File(path).readAsBytesSync();
      final Uint8List beforeSalt = Uint8List.fromList(
        beforeBiometric.header.kdfSalt,
      );
      final int derivedKeyCount = crypto.derivedKeys.length;
      final int decryptedKeyCount = crypto.decryptedKeys.length;

      await repository.changeMasterPassword(
        currentMasterPassword: 'current password',
        newMasterPassword: 'new password',
      );

      final OpenVaultFile changed = engine.openVaultFile(path);
      final Uint8List afterBytes = File(path).readAsBytesSync();
      expect(changed.header.kdfSalt, isNot(orderedEquals(beforeSalt)));
      expect(
        changed.header.biometricWrappedMasterVaultKey,
        orderedEquals(biometricEnvelope),
      );
      expect(
        afterBytes.sublist(vaultFileHeaderLength),
        orderedEquals(beforeBytes.sublist(vaultFileHeaderLength)),
      );
      expect(repository.hasUnlockedSession, isTrue);
      expect(repository.entrySummaries.single.name, 'Envelope test');
      expect(
        crypto.derivedKeys.skip(derivedKeyCount).every(_isCleared),
        isTrue,
      );
      expect(
        crypto.decryptedKeys.skip(decryptedKeyCount).every(_isCleared),
        isTrue,
      );

      await expectLater(
        repository.unlockWithMasterPassword('current password'),
        throwsA(isA<InvalidMasterPasswordException>()),
      );
      await repository.unlockWithMasterPassword('new password');
      final EntryDetail detail = await repository.getEntryDetail(
        summary.entryId,
      );
      expect(detail.entry.password, 'entry ciphertext must not change');
    },
  );

  test(
    'keeps the vault byte-for-byte unchanged after a wrong password',
    () async {
      final String path = '${temporaryDirectory.path}/rejected-change.psw';
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: FakeCryptoService(),
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => path,
      );
      await repository.createEmptyVault(
        masterPassword: 'current password',
        kdfParameters: const Argon2idParameters(
          memoryKiB: 64 * 1024,
          iterations: 3,
        ),
      );
      await repository.unlockWithMasterPassword('current password');
      final Uint8List before = File(path).readAsBytesSync();

      await expectLater(
        repository.changeMasterPassword(
          currentMasterPassword: 'wrong password',
          newMasterPassword: 'new password',
        ),
        throwsA(isA<InvalidMasterPasswordException>()),
      );

      expect(File(path).readAsBytesSync(), orderedEquals(before));
      expect(repository.hasUnlockedSession, isTrue);
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
  test('reads, updates, deletes, and reuses a released entry block', () async {
    final String path = '${temporaryDirectory.path}/crud.psw';
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
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
    final EntrySummary first = await repository.addEntry(
      const NewVaultEntry(name: 'Before', password: 'secret'),
    );
    final VaultEntryRecord initial = VaultFileEngine()
        .openVaultFile(path)
        .directory
        .records
        .single;
    final EntryDetail detail = await repository.getEntryDetail(first.entryId);
    expect(detail.entry.password, 'secret');
    await repository.updateEntry(
      detail.entry.copyWith(name: 'After', password: 'new secret'),
    );
    expect(repository.entrySummaries.single.name, 'After');
    final VaultEntryRecord updated = VaultFileEngine()
        .openVaultFile(path)
        .directory
        .records
        .single;
    expect(updated.sequence, initial.sequence + 1);
    await repository.deleteEntry(first.entryId);
    expect(repository.entrySummaries, isEmpty);
    expect(
      VaultFileEngine().openVaultFile(path).header.freeListHead,
      updated.blockOffset,
    );
    await repository.addEntry(const NewVaultEntry(name: 'Reused'));
    expect(
      VaultFileEngine()
          .openVaultFile(path)
          .directory
          .records
          .single
          .blockOffset,
      updated.blockOffset,
    );
    repository.clearUnlockedSession();
    await repository.unlockWithMasterPassword('correct password');
    expect(repository.entrySummaries.single.name, 'Reused');
  });

  test('exports DEKs and raw ciphertext and re-wraps them on import', () async {
    final String senderPath = '${temporaryDirectory.path}/sender.psw';
    final String receiverPath = '${temporaryDirectory.path}/receiver.psw';
    final EncryptedVaultRepository sender = _repository(
      senderPath,
      FakeCryptoService(),
    );
    final EncryptedVaultRepository receiver = _repository(
      receiverPath,
      FakeCryptoService(),
    );
    await sender.createEmptyVault(
      masterPassword: 'sender password',
      kdfParameters: _testKdfParameters,
    );
    await receiver.createEmptyVault(
      masterPassword: 'receiver password',
      kdfParameters: _testKdfParameters,
    );
    await sender.unlockWithMasterPassword('sender password');
    await receiver.unlockWithMasterPassword('receiver password');
    final EntrySummary source = await sender.addEntry(
      const NewVaultEntry(name: 'Migrated', password: 'secret'),
    );
    final List<MigrationEntryPayload> payloads = await sender
        .exportMigrationEntries();
    final Uint8List sourceCiphertext = Uint8List.fromList(
      payloads.single.entryCiphertext,
    );
    try {
      await receiver.importMigrationEntries(payloads);
      expect(receiver.entrySummaries.single.entryId, source.entryId);
      final EntryDetail imported = await receiver.getEntryDetail(
        source.entryId,
      );
      expect(imported.entry.password, 'secret');
      final VaultEntryRecord importedRecord = VaultFileEngine()
          .openVaultFile(receiverPath)
          .directory
          .records
          .single;
      expect(
        VaultFileEngine()
            .readEntryBlock(receiverPath, importedRecord)
            .sublist(72),
        sourceCiphertext,
      );
    } finally {
      for (final MigrationEntryPayload payload in payloads) {
        payload.dispose();
      }
      sourceCiphertext.fillRange(0, sourceCiphertext.length, 0);
    }
  });

  test(
    'uses whole-entry updated_at conflict resolution and stays atomic',
    () async {
      final String senderPath =
          '${temporaryDirectory.path}/conflict-sender.psw';
      final String receiverPath =
          '${temporaryDirectory.path}/conflict-receiver.psw';
      final EncryptedVaultRepository sender = _repository(
        senderPath,
        FakeCryptoService(),
      );
      final EncryptedVaultRepository receiver = _repository(
        receiverPath,
        FakeCryptoService(),
      );
      await sender.createEmptyVault(
        masterPassword: 'sender password',
        kdfParameters: _testKdfParameters,
      );
      await receiver.createEmptyVault(
        masterPassword: 'receiver password',
        kdfParameters: _testKdfParameters,
      );
      await sender.unlockWithMasterPassword('sender password');
      await receiver.unlockWithMasterPassword('receiver password');
      final EntrySummary source = await sender.addEntry(
        const NewVaultEntry(name: 'Before', password: 'secret'),
      );
      final List<MigrationEntryPayload> first = await sender
          .exportMigrationEntries();
      await receiver.importMigrationEntries(first);
      for (final MigrationEntryPayload payload in first) {
        payload.dispose();
      }

      await Future<void>.delayed(const Duration(milliseconds: 2));
      final EntryDetail sourceDetail = await sender.getEntryDetail(
        source.entryId,
      );
      await sender.updateEntry(sourceDetail.entry.copyWith(name: 'After'));
      final List<MigrationEntryPayload> newer = await sender
          .exportMigrationEntries();
      try {
        await receiver.importMigrationEntries(newer);
        expect(receiver.entrySummaries.single.name, 'After');
        await receiver.importMigrationEntries(newer);
        expect(receiver.entrySummaries.single.name, 'After');
      } finally {
        for (final MigrationEntryPayload payload in newer) {
          payload.dispose();
        }
      }
    },
  );

  test('rejects a bad payload before publishing a partial batch', () async {
    final String senderPath = '${temporaryDirectory.path}/partial-sender.psw';
    final String receiverPath =
        '${temporaryDirectory.path}/partial-receiver.psw';
    final EncryptedVaultRepository sender = _repository(
      senderPath,
      FakeCryptoService(),
    );
    final EncryptedVaultRepository receiver = _repository(
      receiverPath,
      FakeCryptoService(),
    );
    await sender.createEmptyVault(
      masterPassword: 'sender password',
      kdfParameters: _testKdfParameters,
    );
    await receiver.createEmptyVault(
      masterPassword: 'receiver password',
      kdfParameters: _testKdfParameters,
    );
    await sender.unlockWithMasterPassword('sender password');
    await receiver.unlockWithMasterPassword('receiver password');
    await sender.addEntry(const NewVaultEntry(name: 'First'));
    await sender.addEntry(const NewVaultEntry(name: 'Second'));
    final List<MigrationEntryPayload> sourcePayloads = await sender
        .exportMigrationEntries();
    final MigrationEntryPayload invalid = MigrationEntryPayload(
      entryId: sourcePayloads.last.entryId,
      sequence: sourcePayloads.last.sequence,
      plaintextFormatId: sourcePayloads.last.plaintextFormatId,
      entryCiphertext: sourcePayloads.last.entryCiphertext,
      dek: Uint8List.fromList(sourcePayloads.last.dek)..[0] ^= 0xff,
    );
    try {
      expect(
        receiver.importMigrationEntries(<MigrationEntryPayload>[
          sourcePayloads.first,
          invalid,
        ]),
        throwsA(isA<VaultCorruptedException>()),
      );
      expect(receiver.entrySummaries, isEmpty);
      expect(
        VaultFileEngine().openVaultFile(receiverPath).directory.records,
        isEmpty,
      );
    } finally {
      invalid.dispose();
      for (final MigrationEntryPayload payload in sourcePayloads) {
        payload.dispose();
      }
    }
  });

  test('rejects a detail whose authenticated entry block is damaged', () async {
    final String path = '${temporaryDirectory.path}/damaged-detail.psw';
    final EncryptedVaultRepository repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
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
    final EntrySummary summary = await repository.addEntry(
      const NewVaultEntry(name: 'Damaged', password: 'secret'),
    );
    final VaultEntryRecord record = VaultFileEngine()
        .openVaultFile(path)
        .directory
        .records
        .single;
    final Uint8List bytes = File(path).readAsBytesSync();
    bytes[record.blockOffset + record.blockLength - 1] ^= 0xff;
    File(path).writeAsBytesSync(bytes, flush: true);
    bytes.fillRange(0, bytes.length, 0);

    expect(
      repository.getEntryDetail(summary.entryId),
      throwsA(isA<VaultCorruptedException>()),
    );
  });

  test(
    'splits a large free slot and appends beyond a too-small remainder',
    () async {
      final String path = '${temporaryDirectory.path}/free-list-boundary.psw';
      final EncryptedVaultRepository repository = EncryptedVaultRepository(
        crypto: FakeCryptoService(),
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
      final EntrySummary large = await repository.addEntry(
        NewVaultEntry(
          name: 'Large',
          password: List<String>.filled(512, 'x').join(),
        ),
      );
      final VaultEntryRecord released = VaultFileEngine()
          .openVaultFile(path)
          .directory
          .records
          .single;
      await repository.deleteEntry(large.entryId);
      final EntrySummary small = await repository.addEntry(
        const NewVaultEntry(name: 'Small'),
      );
      final OpenVaultFile afterSplit = VaultFileEngine().openVaultFile(path);
      final VaultEntryRecord reused = afterSplit.directory.records.single;
      expect(reused.entryId, small.entryId);
      expect(reused.blockOffset, released.blockOffset);
      expect(
        afterSplit.header.freeListHead,
        reused.blockOffset + reused.blockCapacity,
      );

      final int appendOffset = File(path).lengthSync();
      final EntrySummary oversized = await repository.addEntry(
        NewVaultEntry(
          name: 'Oversized',
          password: List<String>.filled(1024, 'y').join(),
        ),
      );
      final OpenVaultFile afterAppend = VaultFileEngine().openVaultFile(path);
      final VaultEntryRecord appended = afterAppend.directory.records
          .firstWhere(
            (VaultEntryRecord record) =>
                _sameBytes(record.entryId, oversized.entryId),
          );
      expect(appended.blockOffset, appendOffset);
      expect(afterAppend.header.freeListHead, afterSplit.header.freeListHead);
    },
  );
}

const Argon2idParameters _testKdfParameters = Argon2idParameters(
  memoryKiB: 64 * 1024,
  iterations: 3,
);

EncryptedVaultRepository _repository(String path, FakeCryptoService crypto) =>
    EncryptedVaultRepository(
      crypto: crypto,
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => path,
    );

bool _isCleared(List<int> bytes) => bytes.every((int byte) => byte == 0);

bool _sameBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
