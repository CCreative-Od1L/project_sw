import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/observability/logger.dart';
import 'package:project_sw/core/observability/redaction_filter.dart';
import 'package:project_sw/features/auth/domain/authenticated_wipe_vault.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';
import 'package:project_sw/features/auth/domain/recovery/recover_master_password.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/authenticated_wipe_cubit.dart';
import 'package:project_sw/features/auth/presentation/deadlock_wipe_cubit.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';

import '../helpers/fake_crypto_service.dart';

void main() {
  test(
    'dependency registration resolves every initial application contract',
    () async {
      final GetIt serviceLocator = GetIt.asNewInstance();
      addTearDown(() => serviceLocator.reset(dispose: true));

      registerAppDependencies(serviceLocator);

      expect(serviceLocator<AppConfig>(), isA<AppConfig>());
      expect(serviceLocator<RedactionFilter>(), isA<RedactionFilter>());
      expect(serviceLocator<LogSink>(), isA<DeveloperLogSink>());
      expect(serviceLocator<Logger>(), isA<RedactingLogger>());
      expect(serviceLocator<EventTracker>(), isA<NoopEventTracker>());
      expect(serviceLocator<MetricsRecorder>(), isA<NoopMetricsRecorder>());
      expect(serviceLocator<SessionController>(), isA<SessionController>());
      expect(serviceLocator<AuthCubit>(), isA<AuthCubit>());
    },
  );

  test(
    'bootstrap maps an existing vault to the cold-start locked state',
    () async {
      final GetIt serviceLocator = GetIt.asNewInstance();
      addTearDown(() => serviceLocator.reset(dispose: true));

      registerAppDependencies(
        serviceLocator,
        config: const AppConfig(vaultExistsAtLaunch: true),
      );

      final SessionController controller = serviceLocator<SessionController>();

      expect(controller.state, isA<LockedSession>());
      expect((controller.state as LockedSession).reason, LockReason.coldStart);
    },
  );

  test('session lock clears the shared sensitive clipboard state', () async {
    final GetIt serviceLocator = GetIt.asNewInstance();
    final _DependencyClipboard clipboard = _DependencyClipboard();
    addTearDown(() => serviceLocator.reset(dispose: true));

    registerAppDependencies(
      serviceLocator,
      config: const AppConfig(vaultExistsAtLaunch: true),
      clipboardPort: clipboard,
    );
    final SessionController sessionController =
        serviceLocator<SessionController>();
    final SensitiveClipboardController clipboardController =
        serviceLocator<SensitiveClipboardController>();
    sessionController.unlock(AuthStrength.masterPassword);
    await clipboardController.copySensitive('secret');

    sessionController.lock(LockReason.manualLock);

    expect(clipboardController.state.status, SensitiveClipboardStatus.idle);
    await clipboard.clearCalled.future.timeout(const Duration(seconds: 1));
    expect(clipboard.value, isEmpty);
  });

  test('registers the complete biometric recovery graph together', () async {
    final GetIt serviceLocator = GetIt.asNewInstance();
    addTearDown(() => serviceLocator.reset(dispose: true));

    registerAppDependencies(
      serviceLocator,
      cryptoService: FakeCryptoService(),
      vaultPathResolver: () async => '/tmp/test-vault.psw',
      recoveryStatePathResolver: () async => '/tmp/test-recovery.json',
      biometricKeyStore: _DependencyBiometricKeyStore(),
    );

    expect(
      serviceLocator<MasterPasswordRecoveryStore>(),
      isA<MasterPasswordRecoveryStore>(),
    );
    expect(
      serviceLocator<MasterPasswordRecoveryGate>(),
      isA<MasterPasswordRecoveryGate>(),
    );
    expect(
      serviceLocator<BiometricRecoveryConfirmer>(),
      isA<BiometricRecoveryConfirmer>(),
    );
    expect(
      serviceLocator<MasterPasswordRecoveryRepository>(),
      isA<MasterPasswordRecoveryRepository>(),
    );
    expect(
      serviceLocator<RecoverMasterPassword>(),
      isA<RecoverMasterPassword>(),
    );
    expect(
      serviceLocator<MasterPasswordChangeCubit>(),
      isA<MasterPasswordChangeCubit>(),
    );
    expect(serviceLocator<VaultWipeRepository>(), isA<VaultWipeRepository>());
    expect(serviceLocator<WipeVault>(), isA<WipeVault>());
    expect(serviceLocator<DeadlockWipeCubit>(), isA<DeadlockWipeCubit>());
    expect(
      serviceLocator<AuthenticatedWipeVault>(),
      isA<AuthenticatedWipeVault>(),
    );
    expect(
      serviceLocator<AuthenticatedWipeCubit>(),
      isA<AuthenticatedWipeCubit>(),
    );
  });
}

final class _DependencyClipboard implements ClipboardPort {
  String value = '';
  final Completer<void> clearCalled = Completer<void>();

  @override
  Future<void> writeText(String value) async => this.value = value;

  @override
  Future<String?> readText() async => value;

  @override
  Future<void> clearText() async {
    value = '';
    if (!clearCalled.isCompleted) clearCalled.complete();
  }
}

final class _DependencyBiometricKeyStore implements BiometricKeyStore {
  @override
  Future<BiometricAvailability> get availability async =>
      BiometricAvailability.available;

  @override
  Future<Uint8List> createAndStoreKey() async => Uint8List(32);

  @override
  Future<void> deleteKey() async {}

  @override
  Future<Uint8List> loadKey() async => Uint8List(32);
}
