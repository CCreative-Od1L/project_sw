import 'dart:typed_data';

/// One session-encrypted entry payload exchanged between migration endpoints.
///
/// The DEK is only held in memory while the receiver re-wraps it with its own
/// MVK. The entry ciphertext is copied byte-for-byte into the receiver block.
final class MigrationEntryPayload {
  /// Creates a validated payload and copies every byte buffer.
  MigrationEntryPayload({
    required Uint8List entryId,
    required this.sequence,
    required this.plaintextFormatId,
    required Uint8List entryCiphertext,
    required Uint8List dek,
  }) : entryId = Uint8List.fromList(entryId),
       entryCiphertext = Uint8List.fromList(entryCiphertext),
       dek = Uint8List.fromList(dek) {
    if (this.entryId.length != 16 ||
        sequence < 0 ||
        plaintextFormatId != 1 ||
        this.entryCiphertext.length < 40 ||
        this.dek.length != 32) {
      throw ArgumentError('Migration entry payload is invalid.');
    }
  }

  /// Stable entry identity.
  final Uint8List entryId;

  /// Original EntryRecord revision sequence used by entry ciphertext AAD.
  final int sequence;

  /// Inner serialization selector.
  final int plaintextFormatId;

  /// Raw `[nonce || ciphertext || tag]` preserved from the sender vault.
  final Uint8List entryCiphertext;

  /// Plaintext DEK held only for the receiver re-wrap operation.
  final Uint8List dek;

  /// Clears all copied sensitive material.
  void dispose() {
    entryId.fillRange(0, entryId.length, 0);
    entryCiphertext.fillRange(0, entryCiphertext.length, 0);
    dek.fillRange(0, dek.length, 0);
  }
}

/// Repository boundary used by the future network migration coordinator.
abstract interface class MigrationVaultPort {
  /// Exports opaque encrypted entry payloads from an unlocked vault.
  Future<List<MigrationEntryPayload>> exportMigrationEntries();

  /// Imports payloads into an unlocked vault in one atomic storage operation.
  Future<void> importMigrationEntries(List<MigrationEntryPayload> entries);
}
