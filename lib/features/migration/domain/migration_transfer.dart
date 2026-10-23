import 'dart:typed_data';

import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';

/// Explicit export scope; a missing single entry must never become a full export.
final class MigrationSelection {
  /// Selects every entry in the unlocked vault.
  const MigrationSelection.all() : _entryId = null;

  /// Selects exactly one stable entry identity, copied from the caller.
  MigrationSelection.single(Uint8List entryId)
    : _entryId = Uint8List.fromList(entryId) {
    if (entryId.length != 16) {
      throw ArgumentError('A migration entry identity must contain 16 bytes.');
    }
  }

  final Uint8List? _entryId;

  /// Whether the full vault was explicitly selected.
  bool get isAll => _entryId == null;

  /// Tests an entry identity by value.
  bool includes(Uint8List entryId) {
    final Uint8List? selected = _entryId;
    if (selected == null) return true;
    if (selected.length != entryId.length) return false;
    for (var i = 0; i < selected.length; i++) {
      if (selected[i] != entryId[i]) return false;
    }
    return true;
  }
}

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
  Future<List<MigrationEntryPayload>> exportMigrationEntries({
    required SessionActivityGuard activityGuard,
    MigrationSelection selection = const MigrationSelection.all(),
  });

  /// Imports payloads into an unlocked vault in one atomic storage operation.
  Future<void> importMigrationEntries(
    List<MigrationEntryPayload> entries, {
    required SessionActivityGuard activityGuard,
  });
}
