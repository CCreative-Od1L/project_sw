import 'package:project_sw/core/crypto/argon2id_benchmark.dart';

/// Persists the first encrypted vault without exposing storage implementation.
abstract interface class VaultRepository {
  /// Creates the initial File Header and empty Directory.
  Future<void> createEmptyVault({
    required String masterPassword,
    required Argon2idParameters kdfParameters,
  });
}
