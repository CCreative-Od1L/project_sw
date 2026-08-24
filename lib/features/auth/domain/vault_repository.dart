import 'dart:typed_data';

import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';

/// Persists the first encrypted vault without exposing storage implementation.
abstract interface class VaultRepository implements SessionSecretCleaner {
  /// Creates the initial File Header and empty Directory.
  Future<void> createEmptyVault({
    required String masterPassword,
    required Argon2idParameters kdfParameters,
  });

  /// Opens the vault with its master password and retains only its MVK.
  ///
  /// Every asynchronous boundary and the final sensitive projection commit
  /// must still belong to [activityGuard].
  Future<void> unlockWithMasterPassword(
    String masterPassword, {
    required SessionActivityGuard activityGuard,
  });

  /// Whether this repository currently holds unlocked vault key material.
  bool get hasUnlockedSession;

  /// Adds one complete VaultEntry and returns only its safe EntrySummary.
  Future<EntrySummary> addEntry(
    NewVaultEntry entry, {
    required SessionActivityGuard activityGuard,
  });

  /// The current unlocked session's globally resident, safe EntrySummary list.
  List<EntrySummary> get entrySummaries;

  /// The active vault KDF profile, available only while the vault is unlocked.
  Argon2idParameters? get activeKdfParameters;

  /// Decrypts a complete entry only for a short-lived detail scope.
  Future<EntryDetail> getEntryDetail(
    Uint8List entryId, {
    required SessionActivityGuard activityGuard,
  });

  /// Persists a replacement complete entry and returns its safe summary.
  Future<EntrySummary> updateEntry(
    VaultEntry entry, {
    required SessionActivityGuard activityGuard,
  });

  /// Removes an entry and releases its encrypted block slot.
  Future<void> deleteEntry(
    Uint8List entryId, {
    required SessionActivityGuard activityGuard,
  });
}
