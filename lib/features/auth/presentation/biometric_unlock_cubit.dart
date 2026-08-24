import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';

/// UI state for the optional biometric unlock action.
sealed class BiometricUnlockViewState {
  /// Creates a biometric unlock view state.
  const BiometricUnlockViewState({required this.isConfigured});

  /// Whether the vault header has a biometric MVK envelope.
  final bool isConfigured;
}

/// The biometric button may be rendered according to [isAvailable].
final class BiometricUnlockReady extends BiometricUnlockViewState {
  /// Creates an idle biometric state.
  const BiometricUnlockReady({
    required super.isConfigured,
    required this.isAvailable,
  });

  /// Whether the platform currently offers strong biometric auth.
  final bool isAvailable;
}

/// The cubit is reading the vault header and platform capability.
final class BiometricUnlockChecking extends BiometricUnlockViewState {
  /// Creates the checking state.
  const BiometricUnlockChecking() : super(isConfigured: false);
}

/// The OS biometric prompt is active.
final class BiometricUnlocking extends BiometricUnlockViewState {
  /// Creates the loading state.
  const BiometricUnlocking({required super.isConfigured});
}

/// The user dismissed the prompt.
final class BiometricUnlockCancelled extends BiometricUnlockViewState {
  /// Creates the cancelled state.
  const BiometricUnlockCancelled({required super.isConfigured});
}

/// The enrolled biometric set no longer matches the platform key.
final class BiometricUnlockInvalidated extends BiometricUnlockViewState {
  /// Creates the invalidated state.
  const BiometricUnlockInvalidated({required super.isConfigured});
}

/// The platform cannot currently offer biometric unlock.
final class BiometricUnlockUnavailable extends BiometricUnlockViewState {
  /// Creates the unavailable state.
  const BiometricUnlockUnavailable({required super.isConfigured});
}

/// A non-user biometric fault that should receive generic UI treatment.
final class BiometricUnlockFault extends BiometricUnlockViewState {
  /// Creates the generic fault state.
  const BiometricUnlockFault({required super.isConfigured});
}

/// Coordinates the biometric action while the session source owns strength.
final class BiometricUnlockCubit extends Cubit<BiometricUnlockViewState> {
  /// Creates the biometric action coordinator.
  BiometricUnlockCubit(
    this._repository,
    this._keyStore,
    this._sessionController, {
    this.onUnlocked,
  }) : super(const BiometricUnlockChecking());

  final BiometricVaultRepository _repository;
  final BiometricKeyStore _keyStore;
  final SessionController _sessionController;

  /// Refreshes safe header/platform metadata before displaying the action.
  final void Function()? onUnlocked;

  bool _isConfigured = false;
  bool _isAvailable = false;
  SessionUnlockAttempt? _activeUnlockAttempt;

  /// Reads only non-sensitive configuration and platform availability.
  Future<void> loadAvailability() async {
    emit(const BiometricUnlockChecking());
    try {
      _isConfigured = await _repository.hasConfiguredBiometricUnlock();
      _isAvailable =
          await _keyStore.availability == BiometricAvailability.available;
      emit(
        BiometricUnlockReady(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
    } on BiometricKeyStoreException {
      _isAvailable = false;
      emit(
        BiometricUnlockReady(isConfigured: _isConfigured, isAvailable: false),
      );
    } on Object {
      emit(const BiometricUnlockUnavailable(isConfigured: false));
    }
  }

  /// Authenticates and upgrades the global session only after repository success.
  Future<void> unlock() async {
    if (!_isConfigured || !_isAvailable || state is BiometricUnlocking) {
      return;
    }
    final SessionState currentSession = _sessionController.state;
    if (currentSession is! LockedSession || !currentSession.canUseBiometric) {
      return;
    }
    final SessionUnlockAttempt attempt;
    try {
      attempt = _sessionController.beginUnlockAttempt();
    } on StateError {
      return;
    }
    _activeUnlockAttempt = attempt;
    emit(BiometricUnlocking(isConfigured: _isConfigured));
    try {
      await _repository.unlockWithBiometric(activityGuard: attempt);
      if (!attempt.complete(AuthStrength.biometric)) {
        if (!isClosed) {
          emit(_readyState());
        }
        return;
      }
      onUnlocked?.call();
      if (!isClosed) {
        emit(_readyState());
      }
    } on BiometricCancelledException {
      final bool stillActive = attempt.isActive;
      attempt.cancel();
      if (!isClosed) {
        emit(
          stillActive
              ? BiometricUnlockCancelled(isConfigured: _isConfigured)
              : _readyState(),
        );
      }
    } on BiometricInvalidatedException {
      final bool stillActive = attempt.isActive;
      attempt.cancel();
      if (stillActive) {
        _sessionController.handle(SessionEvent.biometricInvalidated);
      }
      if (!isClosed) {
        emit(
          stillActive
              ? BiometricUnlockInvalidated(isConfigured: _isConfigured)
              : _readyState(),
        );
      }
    } on BiometricUnavailableException {
      final bool stillActive = attempt.isActive;
      attempt.cancel();
      if (stillActive) {
        _isAvailable = false;
      }
      if (!isClosed) {
        emit(
          stillActive
              ? BiometricUnlockUnavailable(isConfigured: _isConfigured)
              : _readyState(),
        );
      }
    } on BiometricKeyStoreException {
      final bool stillActive = attempt.isActive;
      attempt.cancel();
      if (!isClosed) {
        emit(
          stillActive
              ? BiometricUnlockFault(isConfigured: _isConfigured)
              : _readyState(),
        );
      }
    } on Object {
      final bool stillActive = attempt.isActive;
      attempt.cancel();
      if (!isClosed) {
        emit(
          stillActive
              ? BiometricUnlockFault(isConfigured: _isConfigured)
              : _readyState(),
        );
      }
    }
  }

  BiometricUnlockReady _readyState() => BiometricUnlockReady(
    isConfigured: _isConfigured,
    isAvailable: _isAvailable,
  );

  @override
  Future<void> close() {
    _activeUnlockAttempt?.cancel();
    return super.close();
  }
}
