import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_vault_repository.dart';

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

/// Coordinates biometric setting changes behind a small presentation seam.
final class BiometricSettingsCubit extends Cubit<BiometricSettingsViewState> {
  /// Creates the settings coordinator.
  BiometricSettingsCubit(this._repository, this._keyStore)
    : super(const BiometricSettingsLoading());

  final BiometricVaultRepository _repository;
  final BiometricKeyStore _keyStore;
  var _isConfigured = false;
  var _isAvailable = false;

  /// Loads only safe configuration and platform capability metadata.
  Future<void> load() async {
    emit(const BiometricSettingsLoading());
    try {
      _isConfigured = await _repository.hasConfiguredBiometricUnlock();
      _isAvailable =
          await _keyStore.availability == BiometricAvailability.available;
      emit(
        BiometricSettingsReady(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
    } on Object {
      emit(
        BiometricSettingsFault(isConfigured: _isConfigured, isAvailable: false),
      );
    }
  }

  /// Creates or replaces the hardware-gated key and MVK envelope.
  Future<void> enable() async {
    if (!_isAvailable || state is BiometricSettingsWorking) return;
    emit(
      BiometricSettingsWorking(
        isConfigured: _isConfigured,
        isAvailable: _isAvailable,
      ),
    );
    try {
      await _repository.enableBiometricUnlock();
      _isConfigured = true;
      emit(
        BiometricSettingsReady(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
    } on Object {
      emit(
        BiometricSettingsFault(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
    }
  }

  /// Removes the MVK envelope and platform key.
  Future<void> disable() async {
    if (!_isConfigured || state is BiometricSettingsWorking) return;
    emit(
      BiometricSettingsWorking(
        isConfigured: _isConfigured,
        isAvailable: _isAvailable,
      ),
    );
    try {
      await _repository.disableBiometricUnlock();
      _isConfigured = false;
      emit(
        BiometricSettingsReady(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
    } on Object {
      emit(
        BiometricSettingsFault(
          isConfigured: _isConfigured,
          isAvailable: _isAvailable,
        ),
      );
    }
  }
}
