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
    this.resumeWindow = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now;

  final MasterPasswordRecoveryStore _store;
  final RecoveryClock _clock;

  /// Consecutive change-password failures required to reveal recovery.
  final int failureThreshold;

  /// Cooldown applied after a successful recovery.
  final Duration cooldown;

  /// Window for resuming an already revealed recovery flow after a lock.
  final Duration resumeWindow;

  var _consecutiveChangePasswordFailures = 0;
  MasterPasswordRecoveryMetadata? _metadataBeforeReservation;

  /// Records only a failure from the change-password flow.
  Future<MasterPasswordRecoveryState> recordChangePasswordFailure({
    required bool biometricConfigured,
  }) async {
    final MasterPasswordRecoveryState existing = await currentState(
      biometricConfigured: biometricConfigured,
    );
    if (existing is MasterPasswordRecoveryAvailable ||
        existing is MasterPasswordRecoveryCoolingDown) {
      return existing;
    }
    _consecutiveChangePasswordFailures++;
    return currentState(biometricConfigured: biometricConfigured);
  }

  /// Computes recovery visibility without changing the failure count.
  Future<MasterPasswordRecoveryState> currentState({
    required bool biometricConfigured,
  }) async {
    final DateTime now = _clock().toUtc();
    final MasterPasswordRecoveryMetadata metadata = await _store.read();
    final DateTime? cooldownUntil = metadata.cooldownUntil;
    if (cooldownUntil != null) {
      final DateTime deadline = cooldownUntil.toUtc();
      if (now.isBefore(deadline)) {
        return MasterPasswordRecoveryCoolingDown(deadline);
      }
      await _clearTrigger();
      return const MasterPasswordRecoveryHidden();
    }
    final DateTime? availableUntil = metadata.availableUntil;
    if (availableUntil != null) {
      if (now.isBefore(availableUntil.toUtc())) {
        return biometricConfigured
            ? const MasterPasswordRecoveryAvailable()
            : const MasterPasswordRecoveryHidden();
      }
      await _clearTrigger();
      return const MasterPasswordRecoveryHidden();
    }
    if (_consecutiveChangePasswordFailures >= failureThreshold &&
        biometricConfigured) {
      await _store.write(
        MasterPasswordRecoveryMetadata(availableUntil: now.add(resumeWindow)),
      );
      return const MasterPasswordRecoveryAvailable();
    }
    return const MasterPasswordRecoveryHidden();
  }

  /// Clears consecutive failures after a successful normal password change.
  Future<void> recordChangePasswordSuccess() => _clearTrigger();

  Future<void> _clearTrigger() async {
    _consecutiveChangePasswordFailures = 0;
    await _store.clear();
  }

  /// Starts a fresh cooldown after a successful biometric recovery.
  Future<void> recordRecoverySuccess() async {
    await reserveRecoveryCooldown();
    completeRecovery();
  }

  /// Persists cooldown before the Vault mutation so failures remain fail-safe.
  Future<void> reserveRecoveryCooldown() async {
    _metadataBeforeReservation = await _store.read();
    final DateTime deadline = _clock().toUtc().add(cooldown);
    await _store.write(MasterPasswordRecoveryMetadata(cooldownUntil: deadline));
  }

  /// Restores the revealed window when the Vault mutation did not complete.
  Future<void> cancelRecoveryCooldown() async {
    final MasterPasswordRecoveryMetadata metadata =
        _metadataBeforeReservation ?? const MasterPasswordRecoveryMetadata();
    _metadataBeforeReservation = null;
    if (metadata.isEmpty) {
      await _store.clear();
    } else {
      await _store.write(metadata);
    }
  }

  /// Resets the in-memory trigger only after recovery commits successfully.
  void completeRecovery() {
    _consecutiveChangePasswordFailures = 0;
    _metadataBeforeReservation = null;
  }
}
