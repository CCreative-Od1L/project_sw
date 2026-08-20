import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';

/// Clock seam used to make cooldown decisions deterministic in tests.
typedef RecoveryClock = DateTime Function();

/// The authoritative visibility state for the hidden recovery entry.
sealed class MasterPasswordRecoveryState {
  /// Creates a recovery gate state.
  const MasterPasswordRecoveryState();
}

/// Recovery must not be offered to the user.
final class MasterPasswordRecoveryHidden extends MasterPasswordRecoveryState {
  /// Creates a hidden state.
  const MasterPasswordRecoveryHidden();
}

/// Recovery may be offered after all preconditions are met.
final class MasterPasswordRecoveryAvailable
    extends MasterPasswordRecoveryState {
  /// Creates an available state.
  const MasterPasswordRecoveryAvailable();
}

/// Recovery remains hidden until [until] after a previous success.
final class MasterPasswordRecoveryCoolingDown
    extends MasterPasswordRecoveryState {
  /// Creates a cooldown state with its UTC deadline.
  const MasterPasswordRecoveryCoolingDown(this.until);

  /// UTC instant when recovery may become available again.
  final DateTime until;
}

/// Owns failure counting, biometric eligibility, and recovery cooldown policy.
final class MasterPasswordRecoveryGate {
  /// Creates the gate around persistent cooldown state and an injectable clock.
  MasterPasswordRecoveryGate(
    this._store, {
    RecoveryClock? clock,
    this.failureThreshold = 3,
    this.cooldown = const Duration(days: 7),
  }) : _clock = clock ?? DateTime.now;

  final MasterPasswordRecoveryStore _store;
  final RecoveryClock _clock;

  /// Consecutive change-password failures required to reveal recovery.
  final int failureThreshold;

  /// Cooldown applied after a successful recovery.
  final Duration cooldown;

  var _consecutiveChangePasswordFailures = 0;

  /// Records only a failure from the change-password flow.
  Future<MasterPasswordRecoveryState> recordChangePasswordFailure({
    required bool biometricConfigured,
  }) {
    _consecutiveChangePasswordFailures++;
    return currentState(biometricConfigured: biometricConfigured);
  }

  /// Computes recovery visibility without changing the failure count.
  Future<MasterPasswordRecoveryState> currentState({
    required bool biometricConfigured,
  }) async {
    final DateTime now = _clock().toUtc();
    final DateTime? storedDeadline = await _store.readCooldownUntil();
    if (storedDeadline != null) {
      final DateTime deadline = storedDeadline.toUtc();
      if (now.isBefore(deadline)) {
        return MasterPasswordRecoveryCoolingDown(deadline);
      }
      await _store.clearCooldown();
    }
    if (_consecutiveChangePasswordFailures >= failureThreshold &&
        biometricConfigured) {
      return const MasterPasswordRecoveryAvailable();
    }
    return const MasterPasswordRecoveryHidden();
  }

  /// Clears consecutive failures after a successful normal password change.
  void recordChangePasswordSuccess() {
    _consecutiveChangePasswordFailures = 0;
  }

  /// Starts a fresh cooldown after a successful biometric recovery.
  Future<void> recordRecoverySuccess() async {
    await reserveRecoveryCooldown();
    completeRecovery();
  }

  /// Persists cooldown before the Vault mutation so failures remain fail-safe.
  Future<void> reserveRecoveryCooldown() async {
    final DateTime deadline = _clock().toUtc().add(cooldown);
    await _store.writeCooldownUntil(deadline);
  }

  /// Removes a reservation when the Vault mutation did not complete.
  Future<void> cancelRecoveryCooldown() => _store.clearCooldown();

  /// Resets the in-memory trigger only after recovery commits successfully.
  void completeRecovery() {
    _consecutiveChangePasswordFailures = 0;
  }
}
