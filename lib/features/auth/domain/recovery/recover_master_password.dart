import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/shared/result.dart';

/// Expected business failures for biometric-assisted password recovery.
enum RecoverMasterPasswordFailure {
  /// The replacement password is empty.
  invalidNewMasterPassword,

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
  });

  /// Recovery eligibility and persistent cooldown policy.
  final MasterPasswordRecoveryGate gate;

  /// Second platform biometric confirmation.
  final BiometricRecoveryConfirmer biometricConfirmer;

  /// Atomic no-old-password MVK re-wrap.
  final MasterPasswordRecoveryRepository repository;

  /// Confirms recovery eligibility, biometrics, re-wrap, and cooldown.
  Future<Result<RecoveredMasterPassword, RecoverMasterPasswordFailure>> call({
    required String newMasterPassword,
  }) async {
    if (newMasterPassword.isEmpty) {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.invalidNewMasterPassword);
    }
    final MasterPasswordRecoveryState state = await gate.currentState(
      biometricConfigured: true,
    );
    if (state is! MasterPasswordRecoveryAvailable) {
      return const Failure<
        RecoveredMasterPassword,
        RecoverMasterPasswordFailure
      >(RecoverMasterPasswordFailure.recoveryUnavailable);
    }
    try {
      await biometricConfirmer.confirm();
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
      await repository.recoverMasterPassword(
        newMasterPassword: newMasterPassword,
      );
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
