import 'dart:async';

import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';

/// Successful destruction of every local vault artifact.
final class WipedVault {
  /// Creates a successful wipe outcome.
  const WipedVault();
}

/// Blocks the session, wipes durable state, then publishes first-run setup.
final class WipeVault {
  /// Creates the shared wipe coordinator around storage and session truth.
  WipeVault(this._repository, this._sessionController);

  final VaultWipeRepository _repository;
  final SessionController _sessionController;
  Future<WipedVault>? _inFlight;

  /// Whether session truth blocks normal access until deletion completes.
  bool get isPending => switch (_sessionController.state) {
    LockedSession(reason: LockReason.wipeStarted) => true,
    _ => false,
  };

  /// The ongoing operation, allowing recovery UI to observe without restarting.
  Future<WipedVault>? get inFlight => _inFlight;

  /// Shares concurrent attempts and keeps any failed wipe blocked for retry.
  Future<WipedVault> call() {
    final Future<WipedVault>? running = _inFlight;
    if (running != null) return running;
    final Completer<WipedVault> completion = Completer<WipedVault>();
    _inFlight = completion.future;
    unawaited(_perform(completion));
    return completion.future;
  }

  Future<void> _perform(Completer<WipedVault> completion) async {
    try {
      _sessionController.beginWipe();
      await _repository.wipeVault();
      _sessionController.completeWipe();
      completion.complete(const WipedVault());
    } on Object catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      _inFlight = null;
    }
  }
}
