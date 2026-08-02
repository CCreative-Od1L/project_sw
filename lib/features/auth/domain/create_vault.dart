import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';

/// Creates the initial encrypted vault after selecting its Argon2id costs.
final class CreateVault {
  /// Creates the use case from its repository and benchmark collaborators.
  const CreateVault(this._repository, this._benchmark);

  final VaultRepository _repository;
  final Argon2idBenchmark _benchmark;

  /// Performs the non-cancellable parameter selection and first vault commit.
  Future<void> call(
    String masterPassword, {
    void Function(Argon2idBenchmarkProgress progress)? onProgress,
  }) async {
    if (masterPassword.isEmpty) {
      throw const InvalidArgumentException('A master password is required.');
    }
    final Argon2idParameters parameters = await _benchmark.selectParameters(
      masterPassword,
      onProgress: onProgress,
    );
    await _repository.createEmptyVault(
      masterPassword: masterPassword,
      kdfParameters: parameters,
    );
  }
}
