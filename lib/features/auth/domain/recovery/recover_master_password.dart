import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/master_password_strength.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/shared/result.dart';

/// Expected business failures for biometric-assisted password recovery.
enum RecoverMasterPasswordFailure {
  /// The replacement password is empty.
  invalidNewMasterPassword,

  /// The replacement remains in the documented weak strength band.
  weakNewMasterPassword,

  /// Failure threshold, biometric configuration, or cooldown blocks recovery.
  recoveryUnavailable,

  /// The user cancelled the second biometric confirmation.
  biometricCancelled,

  /// The platform biometric path is unavailable or invalidated.
  biometricUnavailable,
}

/// Successful biometric-assisted master-password recovery.
final class RecoveredMasterPassword {
  /// Creates a successful recovery outcome.
  const RecoveredMasterPassword();
}

/// Applies every recovery gate before re-wrapping the currently unlocked MVK.
final class RecoverMasterPassword {
  /// Creates the recovery use case from its three deep module interfaces.
  const RecoverMasterPassword({
    required this.gate,
    required this.biometricConfirmer,
    required this.repository,
    this.strengthEvaluator = const MasterPasswordStrengthEvaluator(),
  });

  /// Recovery eligibility and persistent cooldown policy.
  final MasterPasswordRecoveryGate gate;

  /// Second platform biometric confirmation.
  final BiometricRecoveryConfirmer biometricConfirmer;

  /// Atomic no-old-password MVK re-wrap.
  final MasterPasswordRecoveryRepository repository;

  /// Chosen-password strength policy shared with recovery UI feedback.
  final MasterPasswordStrengthEvaluator strengthEvaluator;

  /// Confirms recovery eligibility, biometrics, re-wrap, and cooldown.
  Future<Result<RecoveredMasterPassword, RecoverMasterPasswordFailure>> call({
    required String newMasterPassword,
    required SessionActivityLease activityLease,
  }) async {
    activityLease.ensureActive();
    if (newMasterPassword.isEmpty) {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.invalidNewMasterPassword);
    }
    if (strengthEvaluator.evaluate(newMasterPassword).strength ==
        MasterPasswordStrength.weak) {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.weakNewMasterPassword);
    }
    final MasterPasswordRecoveryState state = await gate.currentState(
      biometricConfigured: true,
    );
    activityLease.ensureActive();
    if (state is! MasterPasswordRecoveryAvailable) {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.recoveryUnavailable);
    }
    try {
      await biometricConfirmer.confirm();
      activityLease.ensureActive();
    } on BiometricCancelledException {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.biometricCancelled);
    } on BiometricUnavailableException {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.biometricUnavailable);
    } on BiometricInvalidatedException {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.biometricUnavailable);
    }

    await gate.reserveRecoveryCooldown();
    try {
      activityLease.ensureActive();
      await repository.recoverMasterPassword(
        newMasterPassword: newMasterPassword,
        activityLease: activityLease,
      );
      activityLease.ensureActive();
    } on Object {
      await gate.cancelRecoveryCooldown();
      rethrow;
    }
    gate.completeRecovery();
    return const Success<RecoveredMasterPassword, RecoverMasterPasswordFailure>(
      RecoveredMasterPassword(),
    );
  }
}
