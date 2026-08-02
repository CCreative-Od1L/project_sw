import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/vault/domain/add_vault_entry.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';

/// UI projection of the unlocked session's safe EntrySummary collection.
sealed class VaultEntriesViewState {
  /// Creates an entries view state.
  const VaultEntriesViewState(this.summaries);

  /// Safe, globally resident list data.
  final List<EntrySummary> summaries;
}

/// Entries are ready for display and another add action.
final class VaultEntriesReady extends VaultEntriesViewState {
  /// Creates a ready state with an optional safe form error.
  const VaultEntriesReady(super.summaries, {this.errorMessage});

  /// Generic error that deliberately contains no entry plaintext.
  final String? errorMessage;
}

/// A complete entry is being encrypted and committed.
final class VaultEntriesSaving extends VaultEntriesViewState {
  /// Creates the saving state.
  const VaultEntriesSaving(super.summaries);
}

/// Owns entry-list interaction state, not unlocked key material.
final class VaultEntriesCubit extends Cubit<VaultEntriesViewState>
    implements SessionSecretCleaner {
  /// Creates the list projection from the repository's safe snapshot.
  VaultEntriesCubit(this._addVaultEntry, this._repository)
    : super(VaultEntriesReady(_repository.entrySummaries));

  final AddVaultEntry _addVaultEntry;
  final VaultRepository _repository;

  /// Pulls the repository's current safe snapshot after a successful unlock.
  void refresh() => emit(VaultEntriesReady(_repository.entrySummaries));

  /// Drops the Cubit's duplicate summary projection on every session lock.
  @override
  void clearUnlockedSession() =>
      emit(const VaultEntriesReady(<EntrySummary>[]));

  /// Encrypts and commits a complete entry before publishing its summary.
  Future<void> add(NewVaultEntry entry) async {
    if (state is VaultEntriesSaving) {
      return;
    }
    emit(VaultEntriesSaving(state.summaries));
    try {
      final EntrySummary summary = await _addVaultEntry(entry);
      emit(VaultEntriesReady(<EntrySummary>[...state.summaries, summary]));
    } on Object {
      emit(
        VaultEntriesReady(
          state.summaries,
          errorMessage: 'The entry could not be saved.',
        ),
      );
    }
  }

  /// Loads one complete entry for a page-local detail presentation.
  Future<EntryDetail> detail(Uint8List entryId) =>
      _repository.getEntryDetail(entryId);

  /// Persists an edited detail and refreshes only its safe summary projection.
  Future<void> update(VaultEntry entry) async {
    final EntrySummary summary = await _repository.updateEntry(entry);
    emit(
      VaultEntriesReady(
        state.summaries
            .map(
              (EntrySummary current) =>
                  _sameBytes(current.entryId, summary.entryId)
                  ? summary
                  : current,
            )
            .toList(),
      ),
    );
  }

  /// Deletes an entry and removes its safe summary projection.
  Future<void> delete(Uint8List entryId) async {
    await _repository.deleteEntry(entryId);
    refresh();
  }

  bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
