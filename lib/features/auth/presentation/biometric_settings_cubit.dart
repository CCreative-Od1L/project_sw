import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';

/// UI state for enabling, disabling, and replacing biometric access.
sealed class BiometricSettingsViewState {
  /// Creates a settings state.
  const BiometricSettingsViewState();
}

/// Configuration metadata is being loaded.
final class BiometricSettingsLoading extends BiometricSettingsViewState {
  /// Creates the loading state.
  const BiometricSettingsLoading();
}

/// Configuration metadata is ready for rendering.
final class BiometricSettingsReady extends BiometricSettingsViewState {
  /// Creates the ready state.
  const BiometricSettingsReady({
    required this.isConfigured,
    required this.isAvailable,
  });

  /// Whether the vault contains a biometric MVK envelope.
  final bool isConfigured;

  /// Whether the platform can currently authenticate biometrically.
  final bool isAvailable;
}

/// A platform key operation is in progress.
final class BiometricSettingsWorking extends BiometricSettingsViewState {
  /// Creates the working state.
  const BiometricSettingsWorking({
    required this.isConfigured,
    required this.isAvailable,
  });

  /// The last known configuration flag.
  final bool isConfigured;

  /// The last known platform capability.
  final bool isAvailable;
}

/// A generic settings operation failed without exposing platform details.
final class BiometricSettingsFault extends BiometricSettingsViewState {
  /// Creates the fault state.
  const BiometricSettingsFault({
    required this.isConfigured,
    required this.isAvailable,
  });

  /// The last known configuration flag.
  final bool isConfigured;

  /// The last known platform capability.
  final bool isAvailable;
}

/// The enrolled biometric set changed while changing biometric settings.
final class BiometricSettingsInvalidated extends BiometricSettingsViewState {
  /// Creates the invalidated state.
  const BiometricSettingsInvalidated({
    required this.isConfigured,
    required this.isAvailable,
  });

  /// The last known configuration flag.
  final bool isConfigured;

  /// The last known platform capability.
  final bool isAvailable;
}

/// Coordinates biometric setting changes behind a small presentation seam.
final class BiometricSettingsCubit extends Cubit<BiometricSettingsViewState> {
  /// Creates the settings coordinator.
  BiometricSettingsCubit(
    this._repository,
    this._keyStore, {
    required this._sessionController,
  }) : super(const BiometricSettingsLoading());

  final BiometricVaultRepository _repository;
  final BiometricKeyStore _keyStore;
  final SessionController _sessionController;
  var _isConfigured = false;
  var _isAvailable = false;
  var _requestGeneration = 0;

  /// Loads only safe configuration and platform capability metadata.
  Future<void> load() async {
    if (isClosed) return;
    final int generation = ++_requestGeneration;
    final SessionState owner = _sessionController.state;
    emit(const BiometricSettingsLoading());
    try {
      final bool configured = await _repository.hasConfiguredBiometricUnlock();
      final bool available =
          await _keyStore.availability == BiometricAvailability.available;
      if (!_ownsRequest(generation, owner)) return;
      _isConfigured = configured;
      _isAvailable = available;
      emit(
        BiometricSettingsReady(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
    } on Object {
      if (!_ownsRequest(generation, owner)) return;
      emit(
        BiometricSettingsFault(isConfigured: _isConfigured, isAvailable: false),
      );
    }
  }

  /// Creates or replaces the hardware-gated key and MVK envelope.
  Future<void> enable() => _configure(enable: true);

  /// Removes the MVK envelope and platform key.
  Future<void> disable() => _configure(enable: false);

  Future<void> _configure({required bool enable}) async {
    if ((enable && !_isAvailable) ||
        (!enable && !_isConfigured) ||
        state is BiometricSettingsWorking) {
      return;
    }
    _requestGeneration++;
    final SessionState session = _sessionController.state;
    if (session is! UnlockedSession ||
        session.authStrength != AuthStrength.masterPassword) {
      emit(
        BiometricSettingsFault(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
      return;
    }
    SessionActivityLease? activityLease;
    try {
      activityLease = _sessionController.beginActivity(
        SessionActivity.biometricConfiguration,
      );
    } on StateError {
      emit(
        BiometricSettingsFault(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
      return;
    }
    try {
      if (isClosed) return;
      emit(
        BiometricSettingsWorking(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
      if (enable) {
        await _repository.enableBiometricUnlock(activityGuard: activityLease);
      } else {
        await _repository.disableBiometricUnlock(activityGuard: activityLease);
      }
      activityLease.ensureActive();
      _isConfigured = _repository.hasBiometricUnlock;
      activityLease.complete();
      activityLease = null;
      if (!isClosed) {
        emit(
          BiometricSettingsReady(
            isConfigured: _isConfigured,
            isAvailable: _isAvailable,
          ),
        );
      }
    } on BiometricInvalidatedException {
      _isConfigured = _repository.hasBiometricUnlock;
      _sessionController.handle(SessionEvent.biometricInvalidated);
      if (!isClosed) {
        emit(
          BiometricSettingsInvalidated(
            isConfigured: _isConfigured,
            isAvailable: _isAvailable,
          ),
        );
      }
    } on SessionActivityInterrupted {
      _isConfigured = _repository.hasBiometricUnlock;
      if (!isClosed) emit(const BiometricSettingsLoading());
    } on Object {
      _isConfigured = _repository.hasBiometricUnlock;
      if (isClosed) {
        return;
      } else if (_sessionController.state is UnlockedSession) {
        emit(
          BiometricSettingsFault(
            isConfigured: _isConfigured,
            isAvailable: _isAvailable,
          ),
        );
      } else {
        emit(const BiometricSettingsLoading());
      }
    } finally {
      activityLease?.complete();
    }
  }

  bool _ownsRequest(int generation, SessionState owner) =>
      !isClosed &&
      generation == _requestGeneration &&
      identical(_sessionController.state, owner);
}
