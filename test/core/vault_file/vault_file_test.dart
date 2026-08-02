import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_vault_test_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test(
    'creates and reopens an empty vault with a committed create journal',
    () {
      final String path = '${temporaryDirectory.path}/vault.psw';
      final VaultFileEngine engine = VaultFileEngine();

      engine.createEmptyVault(path, _header());
      final OpenVaultFile opened = engine.openVaultFile(path);

      expect(File(path).existsSync(), isTrue);
      expect(File('$path.bak').existsSync(), isTrue);
      expect(opened.header.entryCount, 0);
      expect(opened.header.freeListHead, 0);
      expect(opened.header.committedSequence, 1);
      expect(opened.header.sequenceCounter, 2);
      expect(opened.directory.sequence, 1);
    },
  );

  test(
    'replays a valid pending initial create without losing the directory',
    () {
      final String path = '${temporaryDirectory.path}/pending.psw';
      final RandomAccessFile file = File(path).openSync(mode: FileMode.write);
      file.writeFromSync(VaultFileCodec.encodeHeader(_header()));
      file.setPositionSync(vaultFileHeaderLength);
      file.writeFromSync(
        VaultFileCodec.encodeEmptyDirectory(
          const VaultDirectory.empty(sequence: 1),
        ),
      );
      file.closeSync();

      final OpenVaultFile opened = VaultFileEngine().openVaultFile(path);

      expect(opened.header.committedSequence, 1);
      expect(opened.header.sequenceCounter, 2);
      expect(opened.directory.sequence, 1);
    },
  );

  test('rejects a header whose journal checksum was torn', () {
    final Uint8List bytes = VaultFileCodec.encodeHeader(_header());
    bytes[224] ^= 0xff;

    expect(() => VaultFileCodec.decodeHeader(bytes), throwsFormatException);
  });

  test(
    'falls back to the latest successful snapshot after header corruption',
    () {
      final String path = '${temporaryDirectory.path}/snapshot.psw';
      final VaultFileEngine engine = VaultFileEngine()
        ..createEmptyVault(path, _header());
      final RandomAccessFile file = File(path).openSync(mode: FileMode.write);
      file.writeByteSync(0);
      file.closeSync();

      final OpenVaultFile opened = engine.openVaultFile(path);

      expect(opened.header.committedSequence, 1);
      expect(opened.directory.sequence, 1);
    },
  );

  for (final VaultFileCommitStage stage in VaultFileCommitStage.values) {
    test('recovers an interrupted entry update after ${stage.name}', () {
      final String path = '${temporaryDirectory.path}/${stage.name}.psw';
      final VaultFileEngine setup = VaultFileEngine()
        ..createEmptyVault(path, _header());
      final OpenVaultFile initial = setup.openVaultFile(path);
      final Uint8List entryId = Uint8List.fromList(
        List<int>.generate(16, (int index) => index),
      );
      final VaultEntryRecord original = VaultEntryRecord(
        entryId: entryId,
        blockOffset: setup.allocateEntryBlockOffset(initial.directory),
        blockLength: 112,
        blockCapacity: 112,
        plaintextFormatId: 1,
        sequence: initial.header.sequenceCounter,
      );
      setup.commitEntryBlock(
        path: path,
        opened: initial,
        record: original,
        block: Uint8List(112),
      );
      final OpenVaultFile opened = setup.openVaultFile(path);
      final VaultEntryRecord replacement = VaultEntryRecord(
        entryId: entryId,
        blockOffset: original.blockOffset,
        blockLength: 112,
        blockCapacity: 112,
        plaintextFormatId: 1,
        sequence: opened.header.sequenceCounter,
      );
      final VaultFileEngine interrupted = VaultFileEngine(
        faultInjector: (VaultFileCommitStage current) {
          if (current == stage) {
            throw StateError('simulated interruption');
          }
        },
      );

      expect(
        () => interrupted.commitEntryBlock(
          path: path,
          opened: opened,
          record: replacement,
          block: Uint8List(112),
          replacedRecord: original,
        ),
        throwsStateError,
      );

      final OpenVaultFile recovered = VaultFileEngine().openVaultFile(path);
      final bool directoryWasPublished =
          stage == VaultFileCommitStage.afterDirectory ||
          stage == VaultFileCommitStage.afterCommittedSequence;
      expect(recovered.header.entryCount, 1);
      expect(recovered.directory.records, hasLength(1));
      expect(recovered.header.committedSequence, directoryWasPublished ? 3 : 2);
      expect(recovered.header.sequenceCounter, 4);
      expect(
        recovered.directory.records.single.sequence,
        directoryWasPublished ? replacement.sequence : original.sequence,
      );
    });
  }

  test('ignores the retained stale journal after a durable entry commit', () {
    final String path = '${temporaryDirectory.path}/stale-journal.psw';
    final VaultFileEngine engine = VaultFileEngine()
      ..createEmptyVault(path, _header());
    final OpenVaultFile opened = engine.openVaultFile(path);
    final VaultEntryRecord record = VaultEntryRecord(
      entryId: Uint8List.fromList(List<int>.filled(16, 4)),
      blockOffset: engine.allocateEntryBlockOffset(opened.directory),
      blockLength: 112,
      blockCapacity: 112,
      plaintextFormatId: 1,
      sequence: opened.header.sequenceCounter,
    );

    engine.commitEntryBlock(
      path: path,
      opened: opened,
      record: record,
      block: Uint8List(112),
    );

    final OpenVaultFile reopened = engine.openVaultFile(path);
    expect(reopened.header.committedSequence, 2);
    expect(reopened.directory.records, hasLength(1));
  });

  test('uses the .bak snapshot when a committed journal CRC is damaged', () {
    final String path = '${temporaryDirectory.path}/journal-crc.psw';
    final VaultFileEngine engine = VaultFileEngine()
      ..createEmptyVault(path, _header());
    final OpenVaultFile opened = engine.openVaultFile(path);
    final VaultEntryRecord record = VaultEntryRecord(
      entryId: Uint8List.fromList(List<int>.filled(16, 7)),
      blockOffset: engine.allocateEntryBlockOffset(opened.directory),
      blockLength: 112,
      blockCapacity: 112,
      plaintextFormatId: 1,
      sequence: opened.header.sequenceCounter,
    );
    engine.commitEntryBlock(
      path: path,
      opened: opened,
      record: record,
      block: Uint8List(112),
    );

    final Uint8List bytes = File(path).readAsBytesSync();
    bytes[224] ^= 0xff;
    File(path).writeAsBytesSync(bytes, flush: true);
    bytes.fillRange(0, bytes.length, 0);

    final OpenVaultFile recovered = engine.openVaultFile(path);
    expect(recovered.header.committedSequence, 2);
    expect(recovered.directory.records, hasLength(1));
  });
}

VaultFileHeader _header() => VaultFileHeader(
  kdfParameters: const VaultKdfParameters(
    memoryKiB: 64 * 1024,
    iterations: 3,
    parallelism: 1,
  ),
  kdfSalt: Uint8List.fromList(List<int>.filled(16, 1)),
  wrappedMasterVaultKey: Uint8List.fromList(List<int>.filled(72, 2)),
  activeDirectoryOffset: vaultFileHeaderLength,
  entryCount: 0,
  freeListHead: 0,
  sequenceCounter: 1,
  committedSequence: 0,
  journal: const VaultJournal(
    operation: VaultJournalOperation.create,
    sequence: 1,
    directoryOffset: vaultFileHeaderLength,
    directoryLength: vaultDirectoryLength,
  ),
);
