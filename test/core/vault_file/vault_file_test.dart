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
