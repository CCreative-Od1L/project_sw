import 'dart:io';
import 'dart:typed_data';

/// The fixed 512-byte File Header defined by the vault format.
const int vaultFileHeaderLength = 512;

/// The fixed prefix of a Directory, before its 48-byte EntryRecords.
const int vaultDirectoryLength = 16;

/// The serialized size of one Directory EntryRecord.
const int vaultEntryRecordLength = 48;

/// Entry Blocks start after a reserved, fixed-size Directory region.
///
/// Keeping the Directory at a stable offset makes single-entry commits avoid
/// moving existing blocks. The current v0.1 capacity is deliberately bounded
/// to a personal vault's first 330 entries; compaction/directory COW owns any
/// later format expansion.
const int vaultEntryBlockRegionOffset = 16384;

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

  /// Number of active EntryRecords.
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

  /// Returns a copy for either the intent or durable half of a transaction.
  VaultFileHeader copyWith({
    int? entryCount,
    int? freeListHead,
    int? sequenceCounter,
    int? committedSequence,
    VaultJournal? journal,
  }) => VaultFileHeader(
    kdfParameters: kdfParameters,
    kdfSalt: kdfSalt,
    wrappedMasterVaultKey: wrappedMasterVaultKey,
    activeDirectoryOffset: activeDirectoryOffset,
    entryCount: entryCount ?? this.entryCount,
    freeListHead: freeListHead ?? this.freeListHead,
    sequenceCounter: sequenceCounter ?? this.sequenceCounter,
    committedSequence: committedSequence ?? this.committedSequence,
    journal: journal ?? this.journal,
    kdfAlgorithmId: kdfAlgorithmId,
    aeadAlgorithmId: aeadAlgorithmId,
    flags: flags,
  );

  /// Compatibility helper used by initial-vault creation.
  VaultFileHeader copyWithCommit({
    required int committedSequence,
    required int sequenceCounter,
  }) => copyWith(
    committedSequence: committedSequence,
    sequenceCounter: sequenceCounter,
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

  /// A block write and replacement Directory containing one new record.
  entryUpsert,
}

/// A checksummed journal intent record retained after a successful commit.
final class VaultJournal {
  /// Creates a journal record that describes the intended Directory view.
  const VaultJournal({
    required this.operation,
    required this.sequence,
    required this.directoryOffset,
    required this.directoryLength,
    this.freeListHead = 0,
  });

  /// Intended operation.
  final VaultJournalOperation operation;

  /// Log sequence number.
  final int sequence;

  /// The Directory to replay if its write reached durable storage.
  final int directoryOffset;

  /// Serialized length of the intended Directory.
  final int directoryLength;

  /// Free-list head to publish with the intended Directory view.
  final int freeListHead;
}

/// A reusable block slot read from the on-disk free list.
final class VaultFreeSlot {
  /// Creates a decoded free slot.
  const VaultFreeSlot({
    required this.offset,
    required this.capacity,
    required this.nextOffset,
    this.remainder,
  });

  /// File offset of the reusable slot.
  final int offset;

  /// Total slot capacity.
  final int capacity;

  /// Next free-list node, or zero.
  final int nextOffset;

  /// Optional tail retained as a free-list node after this slot is allocated.
  final VaultFreeSlot? remainder;

  /// Free-list head after consuming this allocation, before any other release.
  int get nextFreeListHead => remainder?.offset ?? nextOffset;
}

/// One active Directory record pointing to a sealed Entry Block.
final class VaultEntryRecord {
  /// Creates an immutable entry record.
  VaultEntryRecord({
    required Uint8List entryId,
    required this.blockOffset,
    required this.blockLength,
    required this.blockCapacity,
    required this.plaintextFormatId,
    required this.sequence,
    this.flags = 0,
  }) : entryId = Uint8List.fromList(entryId) {
    if (this.entryId.length != 16 ||
        blockOffset < vaultEntryBlockRegionOffset ||
        blockLength < 72 ||
        blockCapacity < blockLength ||
        plaintextFormatId != 1) {
      throw ArgumentError('Vault EntryRecord is invalid.');
    }
  }

  /// CSPRNG entry identity used by both AAD bindings.
  final Uint8List entryId;

  /// File offset of the Entry Block.
  final int blockOffset;

  /// Actual encrypted block size.
  final int blockLength;

  /// Allocated slot capacity.
  final int blockCapacity;

  /// Inner serialization selector; 1 is JSON.
  final int plaintextFormatId;

  /// Reserved per-entry flags.
  final int flags;

  /// Entry revision bound into entry-ciphertext AAD.
  final int sequence;
}

/// The active Directory and only its non-sensitive records.
final class VaultDirectory {
  /// Creates a decoded Directory.
  VaultDirectory({
    required this.sequence,
    List<VaultEntryRecord> records = const [],
  }) : records = List<VaultEntryRecord>.unmodifiable(records);

  /// Creates an empty initial Directory.
  const VaultDirectory.empty({required this.sequence}) : records = const [];

  /// Commit sequence that created this Directory view.
  final int sequence;

  /// Active EntryRecords.
  final List<VaultEntryRecord> records;
}

/// A parsed vault file after recovery has finished.
final class OpenVaultFile {
  /// Creates an opened vault view.
  const OpenVaultFile({required this.header, required this.directory});

  /// Validated File Header.
  final VaultFileHeader header;

  /// Validated active Directory.
  final VaultDirectory directory;
}

/// Fault boundaries used solely to prove commit recovery in tests.
enum VaultFileCommitStage {
  /// The retained journal intent was flushed.
  afterJournal,

  /// The new Entry Block was flushed.
  afterEntryBlock,

  /// The replacement Directory was flushed.
  afterDirectory,

  /// The committed sequence and replacement header were flushed.
  afterCommittedSequence,
}

/// A test-only hook that can simulate a crash immediately after [stage].
typedef VaultFileFaultInjector = void Function(VaultFileCommitStage stage);

/// A synchronous single-file storage engine for headers, records, and blocks.
final class VaultFileEngine {
  /// Creates the engine with an optional fault injector for recovery tests.
  VaultFileEngine({this.faultInjector});

  /// Test-only hook invoked after each durable transaction boundary.
  final VaultFileFaultInjector? faultInjector;

  /// Creates an empty vault using journal → directory → committed-seq ordering.
  void createEmptyVault(String path, VaultFileHeader header) {
    final File vault = File(path);
    RandomAccessFile? file;
    try {
      vault.parent.createSync(recursive: true);
      file = vault.openSync(mode: FileMode.write);
      file.writeFromSync(VaultFileCodec.encodeHeader(header));
      file.flushSync();
      file.setPositionSync(header.activeDirectoryOffset);
      file.writeFromSync(
        VaultFileCodec.encodeDirectory(
          VaultDirectory.empty(sequence: header.journal.sequence),
        ),
      );
      file.flushSync();
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
    vault.copySync('$path.bak');
  }

  /// Opens a vault and resolves a valid pending journal before exposing data.
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

  /// Reads one opaque Entry Block with its bounds validated by [record].
  Uint8List readEntryBlock(String path, VaultEntryRecord record) {
    final RandomAccessFile file = File(path).openSync();
    try {
      file.setPositionSync(record.blockOffset);
      final Uint8List bytes = file.readSync(record.blockLength);
      if (bytes.length != record.blockLength) {
        throw const FormatException('Entry Block is truncated.');
      }
      return bytes;
    } finally {
      file.closeSync();
    }
  }

  /// Allocates an append-only block offset for the current v0.1 Directory.
  int allocateEntryBlockOffset(VaultDirectory directory) {
    var nextOffset = vaultEntryBlockRegionOffset;
    for (final VaultEntryRecord record in directory.records) {
      final int end = record.blockOffset + record.blockCapacity;
      if (end > nextOffset) {
        nextOffset = end;
      }
    }
    return nextOffset;
  }

  /// Selects the free-list head when it has enough capacity, splitting a
  /// meaningful tail; otherwise selects a non-overlapping append position.
  VaultFreeSlot allocateEntryBlockSlot({
    required String path,
    required OpenVaultFile opened,
    required int requiredLength,
  }) {
    if (opened.header.freeListHead == 0) {
      return VaultFreeSlot(
        offset: allocateEntryBlockOffset(opened.directory),
        capacity: requiredLength,
        nextOffset: 0,
      );
    }
    final RandomAccessFile file = File(path).openSync();
    try {
      file.setPositionSync(opened.header.freeListHead);
      final Uint8List bytes = file.readSync(12);
      if (bytes.length != 12) {
        throw const FormatException('Free slot is truncated.');
      }
      final ByteData data = ByteData.sublistView(bytes);
      final int next = data.getUint64(0, Endian.big);
      final int capacity = data.getUint32(8, Endian.big);
      if (capacity >= requiredLength) {
        final int remainderCapacity = capacity - requiredLength;
        return VaultFreeSlot(
          offset: opened.header.freeListHead,
          capacity: remainderCapacity >= 12 ? requiredLength : capacity,
          nextOffset: next,
          remainder: remainderCapacity >= 12
              ? VaultFreeSlot(
                  offset: opened.header.freeListHead + requiredLength,
                  capacity: remainderCapacity,
                  nextOffset: next,
                )
              : null,
        );
      }
    } finally {
      file.closeSync();
    }
    return VaultFreeSlot(
      // Active records do not describe released tails, so their maximum end
      // is not a safe append position once the free list is non-empty.
      offset: File(path).lengthSync(),
      capacity: requiredLength,
      nextOffset: opened.header.freeListHead,
    );
  }

  /// Commits an already-encrypted block and its new record as one transaction.
  ///
  /// The caller owns entry semantics and cryptography; this engine owns the
  /// journal, block, Directory, header order, and crash recovery invariant.
  void commitEntryBlock({
    required String path,
    required OpenVaultFile opened,
    required VaultEntryRecord record,
    required Uint8List block,
    VaultEntryRecord? replacedRecord,
    VaultEntryRecord? freedRecord,
    int? nextFreeListHead,
    int? freedNextOffset,
    VaultFreeSlot? splitFreeSlot,
  }) {
    if (block.length != record.blockLength ||
        record.sequence != opened.header.sequenceCounter) {
      throw ArgumentError('Entry transaction does not match the active vault.');
    }
    final List<VaultEntryRecord> records = <VaultEntryRecord>[
      ...opened.directory.records,
    ];
    final int existing = records.indexWhere(
      (VaultEntryRecord current) => _sameBytes(current.entryId, record.entryId),
    );
    if (replacedRecord == null && existing >= 0) {
      throw ArgumentError('Entry identity already exists.');
    }
    if (replacedRecord != null) {
      if (existing < 0 || !_sameBytes(replacedRecord.entryId, record.entryId)) {
        throw ArgumentError(
          'Replacement record does not match the active Directory.',
        );
      }
      records[existing] = record;
    } else {
      records.add(record);
    }
    final VaultDirectory nextDirectory = VaultDirectory(
      sequence: record.sequence,
      records: records,
    );
    final Uint8List encodedDirectory = VaultFileCodec.encodeDirectory(
      nextDirectory,
    );
    if (encodedDirectory.length >
        vaultEntryBlockRegionOffset - vaultFileHeaderLength) {
      throw const FormatException('Vault Directory capacity is exhausted.');
    }
    final VaultJournal journal = VaultJournal(
      operation: VaultJournalOperation.entryUpsert,
      sequence: record.sequence,
      directoryOffset: opened.header.activeDirectoryOffset,
      directoryLength: encodedDirectory.length,
      freeListHead: nextFreeListHead ?? opened.header.freeListHead,
    );
    final VaultFileHeader pending = opened.header.copyWith(journal: journal);
    final File vault = File(path);
    _overwriteRange(vault, 0, VaultFileCodec.encodeHeader(pending));
    faultInjector?.call(VaultFileCommitStage.afterJournal);

    _overwriteRange(vault, record.blockOffset, block);
    if (splitFreeSlot != null) {
      _overwriteRange(
        vault,
        splitFreeSlot.offset,
        _encodeFreeSlot(
          nextOffset: splitFreeSlot.nextOffset,
          capacity: splitFreeSlot.capacity,
        ),
      );
    }
    if (freedRecord != null) {
      _overwriteRange(
        vault,
        freedRecord.blockOffset,
        _encodeFreeSlot(
          nextOffset: freedNextOffset ?? opened.header.freeListHead,
          capacity: freedRecord.blockCapacity,
        ),
      );
    }
    faultInjector?.call(VaultFileCommitStage.afterEntryBlock);

    _overwriteRange(
      vault,
      opened.header.activeDirectoryOffset,
      encodedDirectory,
    );
    faultInjector?.call(VaultFileCommitStage.afterDirectory);

    final VaultFileHeader committed = pending.copyWith(
      entryCount: nextDirectory.records.length,
      committedSequence: record.sequence,
      sequenceCounter: record.sequence + 1,
      freeListHead: journal.freeListHead,
    );
    _overwriteRange(vault, 0, VaultFileCodec.encodeHeader(committed));
    faultInjector?.call(VaultFileCommitStage.afterCommittedSequence);
    vault.copySync('$path.bak');
  }

  /// Removes one record and turns its slot into the new free-list head.
  void commitEntryDeletion({
    required String path,
    required OpenVaultFile opened,
    required VaultEntryRecord record,
  }) {
    final List<VaultEntryRecord> records =
        <VaultEntryRecord>[...opened.directory.records]..removeWhere(
          (VaultEntryRecord current) =>
              _sameBytes(current.entryId, record.entryId),
        );
    if (records.length + 1 != opened.directory.records.length) {
      throw ArgumentError('Entry record is not active.');
    }
    final int sequence = opened.header.sequenceCounter;
    final VaultDirectory directory = VaultDirectory(
      sequence: sequence,
      records: records,
    );
    final Uint8List encoded = VaultFileCodec.encodeDirectory(directory);
    final VaultJournal journal = VaultJournal(
      operation: VaultJournalOperation.entryUpsert,
      sequence: sequence,
      directoryOffset: opened.header.activeDirectoryOffset,
      directoryLength: encoded.length,
      freeListHead: record.blockOffset,
    );
    final File vault = File(path);
    _overwriteRange(
      vault,
      0,
      VaultFileCodec.encodeHeader(opened.header.copyWith(journal: journal)),
    );
    faultInjector?.call(VaultFileCommitStage.afterJournal);
    _overwriteRange(
      vault,
      record.blockOffset,
      _encodeFreeSlot(
        nextOffset: opened.header.freeListHead,
        capacity: record.blockCapacity,
      ),
    );
    faultInjector?.call(VaultFileCommitStage.afterEntryBlock);
    _overwriteRange(vault, opened.header.activeDirectoryOffset, encoded);
    faultInjector?.call(VaultFileCommitStage.afterDirectory);
    _overwriteRange(
      vault,
      0,
      VaultFileCodec.encodeHeader(
        opened.header.copyWith(
          entryCount: records.length,
          freeListHead: record.blockOffset,
          committedSequence: sequence,
          sequenceCounter: sequence + 1,
          journal: journal,
        ),
      ),
    );
    faultInjector?.call(VaultFileCommitStage.afterCommittedSequence);
    vault.copySync('$path.bak');
  }

  OpenVaultFile _openVaultFile(String path) {
    final File vault = File(path);
    RandomAccessFile? file;
    try {
      file = vault.openSync(mode: FileMode.append);
      file.setPositionSync(0);
      VaultFileHeader header = VaultFileCodec.decodeHeader(
        file.readSync(vaultFileHeaderLength),
      );
      VaultDirectory directory;

      if (header.journal.sequence > header.committedSequence) {
        final VaultDirectory? pendingDirectory = _tryReadPendingDirectory(
          file,
          header.journal,
        );
        if (pendingDirectory != null &&
            pendingDirectory.sequence == header.journal.sequence) {
          header = header.copyWith(
            entryCount: pendingDirectory.records.length,
            freeListHead: header.journal.freeListHead,
            committedSequence: header.journal.sequence,
            sequenceCounter: header.journal.sequence + 1,
          );
          directory = pendingDirectory;
        } else {
          // No Directory reached disk. Resolve the intent as a rolled-back,
          // stale journal so subsequent opens do not reinterpret it as pending.
          // The committed Directory stays at its previous sequence; only the
          // next allocatable LSN advances, avoiding a false header/directory
          // disagreement after a clean rollback.
          header = header.copyWith(
            sequenceCounter: header.journal.sequence + 1,
            journal: VaultJournal(
              operation: VaultJournalOperation.create,
              sequence: header.committedSequence,
              directoryOffset: header.activeDirectoryOffset,
              directoryLength:
                  vaultDirectoryLength +
                  header.entryCount * vaultEntryRecordLength,
              freeListHead: header.freeListHead,
            ),
          );
          directory = _readDirectory(
            file,
            header.activeDirectoryOffset,
            header.entryCount,
          );
        }
        file.closeSync();
        file = null;
        _overwriteRange(vault, 0, VaultFileCodec.encodeHeader(header));
        vault.copySync('$path.bak');
      } else {
        directory = _readDirectory(
          file,
          header.activeDirectoryOffset,
          header.entryCount,
        );
      }
      if (directory.records.length != header.entryCount ||
          directory.sequence != header.committedSequence) {
        throw const FormatException('Vault Directory and Header disagree.');
      }
      return OpenVaultFile(header: header, directory: directory);
    } finally {
      file?.closeSync();
    }
  }

  VaultDirectory _readDirectory(RandomAccessFile file, int offset, int count) {
    final int length = vaultDirectoryLength + count * vaultEntryRecordLength;
    file.setPositionSync(offset);
    final Uint8List bytes = file.readSync(length);
    if (bytes.length != length) {
      throw const FormatException('Vault Directory is truncated.');
    }
    return VaultFileCodec.decodeDirectory(bytes);
  }

  VaultDirectory? _tryReadPendingDirectory(
    RandomAccessFile file,
    VaultJournal journal,
  ) {
    if (journal.directoryOffset != vaultFileHeaderLength ||
        journal.directoryLength < vaultDirectoryLength ||
        journal.directoryLength >
            vaultEntryBlockRegionOffset - vaultFileHeaderLength) {
      throw const FormatException('A pending vault operation is invalid.');
    }
    file.setPositionSync(journal.directoryOffset);
    final Uint8List bytes = file.readSync(journal.directoryLength);
    if (bytes.length != journal.directoryLength) {
      return null;
    }
    try {
      return VaultFileCodec.decodeDirectory(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Applies an in-place byte patch without opening the file in truncating or
  /// append-only mode. Each call is synchronously flushed as a commit boundary.
  void _overwriteRange(File vault, int offset, Uint8List replacement) {
    final Uint8List current = vault.readAsBytesSync();
    final int targetLength = offset + replacement.length;
    final Uint8List next = Uint8List(
      current.length > targetLength ? current.length : targetLength,
    )..setRange(0, current.length, current);
    next.setRange(offset, targetLength, replacement);
    try {
      vault.writeAsBytesSync(next, flush: true);
    } finally {
      current.fillRange(0, current.length, 0);
      next.fillRange(0, next.length, 0);
    }
  }

  Uint8List _encodeFreeSlot({required int nextOffset, required int capacity}) {
    final Uint8List bytes = Uint8List(12);
    ByteData.sublistView(bytes)
      ..setUint64(0, nextOffset, Endian.big)
      ..setUint32(8, capacity, Endian.big);
    return bytes;
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

  /// Decodes a File Header and verifies structural invariants and journal CRC.
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
        header.entryCount >
            (vaultEntryBlockRegionOffset -
                    vaultFileHeaderLength -
                    vaultDirectoryLength) ~/
                vaultEntryRecordLength ||
        header.sequenceCounter == 0 ||
        header.committedSequence > header.sequenceCounter ||
        header.kdfParameters.memoryKiB == 0 ||
        header.kdfParameters.iterations == 0 ||
        header.kdfParameters.parallelism != 1) {
      throw const FormatException('Vault header sequence fields are invalid.');
    }
    return header;
  }

  /// Encodes a Directory prefix and its fixed-size EntryRecords.
  static Uint8List encodeDirectory(VaultDirectory directory) {
    final Uint8List bytes = Uint8List(
      vaultDirectoryLength + directory.records.length * vaultEntryRecordLength,
    );
    final ByteData data = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, <int>[0x50, 0x44, 0x49, 0x52]);
    data
      ..setUint16(4, vaultFormatVersion, Endian.big)
      ..setUint16(6, directory.records.length, Endian.big)
      ..setUint64(8, directory.sequence, Endian.big);
    var offset = vaultDirectoryLength;
    for (final VaultEntryRecord record in directory.records) {
      bytes.setRange(offset, offset + 16, record.entryId);
      data
        ..setUint64(offset + 16, record.blockOffset, Endian.big)
        ..setUint32(offset + 24, record.blockLength, Endian.big)
        ..setUint32(offset + 28, record.blockCapacity, Endian.big)
        ..setUint8(offset + 32, record.plaintextFormatId)
        ..setUint8(offset + 33, record.flags)
        ..setUint64(offset + 34, record.sequence, Endian.big);
      offset += vaultEntryRecordLength;
    }
    return bytes;
  }

  /// Compatibility name for the initial empty Directory encoding.
  static Uint8List encodeEmptyDirectory(VaultDirectory directory) =>
      encodeDirectory(directory);

  /// Decodes a Directory and each EntryRecord's bounds.
  static VaultDirectory decodeDirectory(Uint8List bytes) {
    if (bytes.length < vaultDirectoryLength ||
        !_sameBytes(
          bytes.sublist(0, 4),
          Uint8List.fromList(<int>[0x50, 0x44, 0x49, 0x52]),
        )) {
      throw const FormatException('Vault Directory is invalid.');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int count = data.getUint16(6, Endian.big);
    if (data.getUint16(4, Endian.big) != vaultFormatVersion ||
        bytes.length != vaultDirectoryLength + count * vaultEntryRecordLength) {
      throw const FormatException('Vault Directory length is invalid.');
    }
    final List<VaultEntryRecord> records = <VaultEntryRecord>[];
    var offset = vaultDirectoryLength;
    for (var index = 0; index < count; index++) {
      try {
        records.add(
          VaultEntryRecord(
            entryId: Uint8List.fromList(bytes.sublist(offset, offset + 16)),
            blockOffset: data.getUint64(offset + 16, Endian.big),
            blockLength: data.getUint32(offset + 24, Endian.big),
            blockCapacity: data.getUint32(offset + 28, Endian.big),
            plaintextFormatId: data.getUint8(offset + 32),
            flags: data.getUint8(offset + 33),
            sequence: data.getUint64(offset + 34, Endian.big),
          ),
        );
      } on ArgumentError {
        throw const FormatException('Vault EntryRecord is invalid.');
      }
      offset += vaultEntryRecordLength;
    }
    return VaultDirectory(
      sequence: data.getUint64(8, Endian.big),
      records: records,
    );
  }

  /// Compatibility decoder that rejects a non-empty Directory.
  static VaultDirectory decodeEmptyDirectory(Uint8List bytes) {
    final VaultDirectory directory = decodeDirectory(bytes);
    if (directory.records.isNotEmpty) {
      throw const FormatException('Vault Directory is not empty.');
    }
    return directory;
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
    data.setUint64(28, journal.freeListHead, Endian.big);
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
      freeListHead: data.getUint64(28, Endian.big),
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

bool _sameBytes(Uint8List first, Uint8List second) {
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
