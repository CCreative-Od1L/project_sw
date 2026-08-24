import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';

/// Successful destruction of every local vault artifact.
final class WipedVault {
  /// Creates a successful wipe outcome.
  const WipedVault();
}

/// Blocks the session, wipes durable state, then publishes first-run setup.
final class WipeVault {
  /// Creates the wipe transaction around storage and the session truth source.
  const WipeVault(this._repository, this._sessionController);

  final VaultWipeRepository _repository;
  final SessionController _sessionController;

  /// Leaves the session blocked if any platform or filesystem step fails.
  Future<WipedVault> call() async {
    _sessionController.beginWipe();
    await _repository.wipeVault();
    _sessionController.completeWipe();
    return const WipedVault();
  }
}
