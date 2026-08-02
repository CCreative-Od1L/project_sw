import 'dart:io';
import 'dart:typed_data';

/// The fixed 512-byte file header defined by the vault format.
const int vaultFileHeaderLength = 512;

/// The fixed empty-directory record length used by the first vault commit.
const int vaultDirectoryLength = 16;

/// Binary magic that identifies a PROJECT_SW vault.
final Uint8List vaultMagic = Uint8List.fromList(<int>[0x50, 0x53, 0x57, 0x56]);

/// The current binary vault format version.
const int vaultFormatVersion = 1;

/// A decoded File Header.
final class VaultFileHeader {
  /// Creates a valid File Header value.
  VaultFileHeader({
    required this.kdfParameters,
    required Uint8List kdfSalt,
    required Uint8List wrappedMasterVaultKey,
    required this.activeDirectoryOffset,
    required this.entryCount,
    required this.freeListHead,
    required this.sequenceCounter,
    required this.committedSequence,
    required this.journal,
    this.kdfAlgorithmId = 1,
    this.aeadAlgorithmId = 1,
    this.flags = 0,
  }) : kdfSalt = Uint8List.fromList(kdfSalt),
       wrappedMasterVaultKey = Uint8List.fromList(wrappedMasterVaultKey) {
    if (this.kdfSalt.length != 16 || this.wrappedMasterVaultKey.length != 72) {
      throw ArgumentError('Vault header key material has an invalid length.');
    }
  }

  /// Argon2id parameters persisted in the header.
  final VaultKdfParameters kdfParameters;

  /// The unique Argon2id salt.
  final Uint8List kdfSalt;

  /// The KEK-wrapped 256-bit Master Vault Key.
  final Uint8List wrappedMasterVaultKey;

  /// Offset of the active Directory.
  final int activeDirectoryOffset;

  /// Number of active entries.
  final int entryCount;

  /// Head of the free-list, or zero when it is empty.
  final int freeListHead;

  /// Sequence number to allocate to the next operation.
  final int sequenceCounter;

  /// Sequence number of the latest durable operation.
  final int committedSequence;

  /// Retained intent log record.
  final VaultJournal journal;

  /// The KDF algorithm id; 1 is Argon2id.
  final int kdfAlgorithmId;

  /// The AEAD algorithm id; 1 is XChaCha20-Poly1305.
  final int aeadAlgorithmId;

  /// Header feature flags.
  final int flags;

  /// Returns a copy with the supplied durable sequence fields.
  VaultFileHeader copyWithCommit({
    required int committedSequence,
    required int sequenceCounter,
  }) => VaultFileHeader(
    kdfParameters: kdfParameters,
    kdfSalt: kdfSalt,
    wrappedMasterVaultKey: wrappedMasterVaultKey,
    activeDirectoryOffset: activeDirectoryOffset,
    entryCount: entryCount,
    freeListHead: freeListHead,
    sequenceCounter: sequenceCounter,
    committedSequence: committedSequence,
    journal: journal,
    kdfAlgorithmId: kdfAlgorithmId,
    aeadAlgorithmId: aeadAlgorithmId,
    flags: flags,
  );
}

/// The three Argon2id cost values encoded as uint32 fields.
final class VaultKdfParameters {
  /// Creates persisted KDF parameters.
  const VaultKdfParameters({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// Memory cost in KiB.
  final int memoryKiB;

  /// Time cost.
  final int iterations;

  /// Parallelism cost.
  final int parallelism;
}

/// Journal operation codes understood by the storage engine.
enum VaultJournalOperation {
  /// The initial File Header and empty Directory creation operation.
  create,
}

/// A checksummed journal intent record retained after a successful commit.
final class VaultJournal {
  /// Creates a journal intent record.
  const VaultJournal({
    required this.operation,
    required this.sequence,
    required this.directoryOffset,
    required this.directoryLength,
  });

  /// Intended operation.
  final VaultJournalOperation operation;

  /// Log sequence number.
  final int sequence;

  /// The directory made durable by this operation.
  final int directoryOffset;

  /// Serialized directory length.
  final int directoryLength;
}

/// The empty Directory persisted by the first vault commit.
final class VaultDirectory {
  /// Creates a Directory with no entry records.
  const VaultDirectory.empty({required this.sequence});

  /// The commit sequence that created this directory view.
  final int sequence;
}

/// A parsed vault file after recovery has finished.
final class OpenVaultFile {
  /// Creates an opened empty-vault view.
  const OpenVaultFile({required this.header, required this.directory});

  /// Validated File Header.
  final VaultFileHeader header;

  /// Validated Directory.
  final VaultDirectory directory;
}

/// A synchronous single-file storage engine for File Header and Directory data.
final class VaultFileEngine {
  /// Creates an empty vault using journal → directory → committed-seq ordering.
  void createEmptyVault(String path, VaultFileHeader header) {
    final File vault = File(path);
    RandomAccessFile? file;
    try {
      vault.parent.createSync(recursive: true);
      file = vault.openSync(mode: FileMode.write);

      // 1. Persist the journal intent in the header before its target exists.
      file.writeFromSync(VaultFileCodec.encodeHeader(header));
      file.flushSync();

      // 2. Persist the target empty Directory.
      file.setPositionSync(header.activeDirectoryOffset);
      file.writeFromSync(
        VaultFileCodec.encodeEmptyDirectory(
          VaultDirectory.empty(sequence: header.journal.sequence),
        ),
      );
      file.flushSync();

      // 3. Mark the retained journal intent committed and advance the LSN.
      final VaultFileHeader committed = header.copyWithCommit(
        committedSequence: header.journal.sequence,
        sequenceCounter: header.journal.sequence + 1,
      );
      file.setPositionSync(0);
      file.writeFromSync(VaultFileCodec.encodeHeader(committed));
      file.flushSync();
    } finally {
      file?.closeSync();
    }

    // The snapshot is a secondary recovery path, never the commit signal.
    vault.copySync('$path.bak');
  }

  /// Opens an empty vault and replays a complete pending creation if necessary.
  OpenVaultFile openVaultFile(String path) {
    try {
      return _openVaultFile(path);
    } on FormatException {
      final File backup = File('$path.bak');
      if (!backup.existsSync()) {
        rethrow;
      }
      backup.copySync(path);
      return _openVaultFile(path);
    }
  }

  OpenVaultFile _openVaultFile(String path) {
    final File vault = File(path);
    RandomAccessFile? file;
    try {
      file = vault.openSync(mode: FileMode.append);
      file.setPositionSync(0);
      final Uint8List headerBytes = file.readSync(vaultFileHeaderLength);
      VaultFileHeader header = VaultFileCodec.decodeHeader(headerBytes);
      file.setPositionSync(header.activeDirectoryOffset);
      final Uint8List directoryBytes = file.readSync(vaultDirectoryLength);
      final VaultDirectory directory = VaultFileCodec.decodeEmptyDirectory(
        directoryBytes,
      );

      if (header.journal.sequence > header.committedSequence) {
        if (header.journal.operation != VaultJournalOperation.create ||
            header.journal.directoryOffset != header.activeDirectoryOffset ||
            header.journal.directoryLength != vaultDirectoryLength ||
            directory.sequence != header.journal.sequence) {
          throw const FormatException(
            'A pending vault operation cannot replay.',
          );
        }
        header = header.copyWithCommit(
          committedSequence: header.journal.sequence,
          sequenceCounter: header.journal.sequence + 1,
        );
        file.closeSync();
        file = null;
        final BytesBuilder recovered = BytesBuilder(copy: false)
          ..add(VaultFileCodec.encodeHeader(header))
          ..add(VaultFileCodec.encodeEmptyDirectory(directory));
        vault.writeAsBytesSync(recovered.toBytes(), flush: true);
      }
      if (header.entryCount != 0 || header.freeListHead != 0) {
        throw const FormatException('The first vault Directory is not empty.');
      }
      if (directory.sequence != header.committedSequence) {
        throw const FormatException('Vault Directory and Header disagree.');
      }
      return OpenVaultFile(header: header, directory: directory);
    } on FileSystemException {
      rethrow;
    } on FormatException {
      rethrow;
    } finally {
      file?.closeSync();
    }
  }
}

/// Encodes and validates the first version of the binary file format.
abstract final class VaultFileCodec {
  static const int _formatVersionOffset = 4;
  static const int _kdfAlgorithmOffset = 6;
  static const int _aeadAlgorithmOffset = 7;
  static const int _memoryOffset = 8;
  static const int _iterationsOffset = 12;
  static const int _parallelismOffset = 16;
  static const int _saltOffset = 20;
  static const int _wrappedMvkOffset = 36;
  static const int _flagsOffset = 108;
  static const int _activeDirectoryOffset = 184;
  static const int _entryCountOffset = 192;
  static const int _freeListHeadOffset = 200;
  static const int _sequenceCounterOffset = 208;
  static const int _committedSequenceOffset = 216;
  static const int _journalOffset = 224;
  static const int _journalLength = 40;

  /// Encodes a File Header into one aligned sector.
  static Uint8List encodeHeader(VaultFileHeader header) {
    final Uint8List bytes = Uint8List(vaultFileHeaderLength);
    final ByteData data = ByteData.sublistView(bytes);
    bytes.setRange(0, vaultMagic.length, vaultMagic);
    data
      ..setUint16(_formatVersionOffset, vaultFormatVersion, Endian.big)
      ..setUint8(_kdfAlgorithmOffset, header.kdfAlgorithmId)
      ..setUint8(_aeadAlgorithmOffset, header.aeadAlgorithmId)
      ..setUint32(_memoryOffset, header.kdfParameters.memoryKiB, Endian.big)
      ..setUint32(
        _iterationsOffset,
        header.kdfParameters.iterations,
        Endian.big,
      )
      ..setUint32(
        _parallelismOffset,
        header.kdfParameters.parallelism,
        Endian.big,
      )
      ..setUint8(_flagsOffset, header.flags)
      ..setUint64(
        _activeDirectoryOffset,
        header.activeDirectoryOffset,
        Endian.big,
      )
      ..setUint64(_entryCountOffset, header.entryCount, Endian.big)
      ..setUint64(_freeListHeadOffset, header.freeListHead, Endian.big)
      ..setUint64(_sequenceCounterOffset, header.sequenceCounter, Endian.big)
      ..setUint64(
        _committedSequenceOffset,
        header.committedSequence,
        Endian.big,
      );
    bytes.setRange(_saltOffset, _saltOffset + 16, header.kdfSalt);
    bytes.setRange(
      _wrappedMvkOffset,
      _wrappedMvkOffset + 72,
      header.wrappedMasterVaultKey,
    );
    bytes.setRange(
      _journalOffset,
      _journalOffset + _journalLength,
      _encodeJournal(header.journal),
    );
    return bytes;
  }

  /// Decodes a File Header and verifies its structural invariants and journal.
  static VaultFileHeader decodeHeader(Uint8List bytes) {
    if (bytes.length != vaultFileHeaderLength ||
        !_sameBytes(bytes.sublist(0, vaultMagic.length), vaultMagic)) {
      throw const FormatException('Vault magic is invalid.');
    }
    final ByteData data = ByteData.sublistView(bytes);
    if (data.getUint16(_formatVersionOffset, Endian.big) !=
            vaultFormatVersion ||
        data.getUint8(_kdfAlgorithmOffset) != 1 ||
        data.getUint8(_aeadAlgorithmOffset) != 1) {
      throw const FormatException(
        'Vault algorithm or format version is invalid.',
      );
    }
    final VaultFileHeader header = VaultFileHeader(
      kdfParameters: VaultKdfParameters(
        memoryKiB: data.getUint32(_memoryOffset, Endian.big),
        iterations: data.getUint32(_iterationsOffset, Endian.big),
        parallelism: data.getUint32(_parallelismOffset, Endian.big),
      ),
      kdfSalt: Uint8List.fromList(bytes.sublist(_saltOffset, _saltOffset + 16)),
      wrappedMasterVaultKey: Uint8List.fromList(
        bytes.sublist(_wrappedMvkOffset, _wrappedMvkOffset + 72),
      ),
      activeDirectoryOffset: data.getUint64(_activeDirectoryOffset, Endian.big),
      entryCount: data.getUint64(_entryCountOffset, Endian.big),
      freeListHead: data.getUint64(_freeListHeadOffset, Endian.big),
      sequenceCounter: data.getUint64(_sequenceCounterOffset, Endian.big),
      committedSequence: data.getUint64(_committedSequenceOffset, Endian.big),
      journal: _decodeJournal(
        Uint8List.fromList(
          bytes.sublist(_journalOffset, _journalOffset + _journalLength),
        ),
      ),
      flags: data.getUint8(_flagsOffset),
    );
    if (header.activeDirectoryOffset != vaultFileHeaderLength ||
        header.sequenceCounter == 0 ||
        header.committedSequence > header.sequenceCounter ||
        header.kdfParameters.memoryKiB == 0 ||
        header.kdfParameters.iterations == 0 ||
        header.kdfParameters.parallelism != 1) {
      throw const FormatException('Vault header sequence fields are invalid.');
    }
    return header;
  }

  /// Encodes the first empty Directory.
  static Uint8List encodeEmptyDirectory(VaultDirectory directory) {
    final Uint8List bytes = Uint8List(vaultDirectoryLength);
    final ByteData data = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, <int>[0x50, 0x44, 0x49, 0x52]);
    data
      ..setUint16(4, vaultFormatVersion, Endian.big)
      ..setUint16(6, 0, Endian.big)
      ..setUint64(8, directory.sequence, Endian.big);
    return bytes;
  }

  /// Decodes an empty Directory and rejects any unexpected entry records.
  static VaultDirectory decodeEmptyDirectory(Uint8List bytes) {
    if (bytes.length != vaultDirectoryLength ||
        !_sameBytes(
          bytes.sublist(0, 4),
          Uint8List.fromList(<int>[0x50, 0x44, 0x49, 0x52]),
        )) {
      throw const FormatException('Vault Directory is invalid.');
    }
    final ByteData data = ByteData.sublistView(bytes);
    if (data.getUint16(4, Endian.big) != vaultFormatVersion ||
        data.getUint16(6, Endian.big) != 0) {
      throw const FormatException('Vault Directory is not empty.');
    }
    return VaultDirectory.empty(sequence: data.getUint64(8, Endian.big));
  }

  static Uint8List _encodeJournal(VaultJournal journal) {
    final Uint8List bytes = Uint8List(_journalLength);
    final ByteData data = ByteData.sublistView(bytes);
    data
      ..setUint8(0, journal.operation.index + 1)
      ..setUint64(1, journal.sequence, Endian.big)
      ..setUint64(9, journal.directoryOffset, Endian.big)
      ..setUint32(17, journal.directoryLength, Endian.big);
    data.setUint32(24, _crc32(bytes.sublist(0, 24)), Endian.big);
    return bytes;
  }

  static VaultJournal _decodeJournal(Uint8List bytes) {
    if (bytes.length != _journalLength) {
      throw const FormatException('Vault journal has an invalid length.');
    }
    final ByteData data = ByteData.sublistView(bytes);
    if (data.getUint32(24, Endian.big) != _crc32(bytes.sublist(0, 24))) {
      throw const FormatException('Vault journal CRC is invalid.');
    }
    final int operationIndex = data.getUint8(0) - 1;
    if (operationIndex < 0 ||
        operationIndex >= VaultJournalOperation.values.length) {
      throw const FormatException('Vault journal operation is invalid.');
    }
    return VaultJournal(
      operation: VaultJournalOperation.values[operationIndex],
      sequence: data.getUint64(1, Endian.big),
      directoryOffset: data.getUint64(9, Endian.big),
      directoryLength: data.getUint32(17, Endian.big),
    );
  }

  static bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final int byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        final int mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xedb88320 & mask);
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
