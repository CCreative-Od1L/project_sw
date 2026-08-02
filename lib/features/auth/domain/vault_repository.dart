import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';

/// Persists the first encrypted vault without exposing storage implementation.
abstract interface class VaultRepository implements SessionSecretCleaner {
  /// Creates the initial File Header and empty Directory.
  Future<void> createEmptyVault({
    required String masterPassword,
    required Argon2idParameters kdfParameters,
  });

  /// Opens the vault with its master password and retains only its MVK.
  Future<void> unlockWithMasterPassword(String masterPassword);

  /// Whether this repository currently holds unlocked vault key material.
  bool get hasUnlockedSession;
}
