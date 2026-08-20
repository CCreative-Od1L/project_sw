import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/core/crypto/sodium_crypto_service.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/observability/logger.dart';
import 'package:project_sw/core/observability/redaction_filter.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/data/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/data/file_master_password_recovery_store.dart';
import 'package:project_sw/features/auth/data/file_vault_wipe_repository.dart';
import 'package:project_sw/features/auth/data/method_channel_biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/create_vault.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/recovery/biometric_recovery_confirmer.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_gate.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_repository.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';
import 'package:project_sw/features/auth/domain/recovery/recover_master_password.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/unlock_vault.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
import 'package:project_sw/features/auth/presentation/step_up_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';
import 'package:project_sw/features/vault/domain/add_vault_entry.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';
import 'package:path_provider/path_provider.dart';

/// The production dependency container used by the application composition root.
final GetIt appServiceLocator = GetIt.instance;

/// Registers the initial application dependencies in [serviceLocator].
void registerAppDependencies(
  GetIt serviceLocator, {
  AppConfig config = const AppConfig(),
  CryptoService? cryptoService,
  VaultPathResolver? vaultPathResolver,
  RecoveryStatePathResolver? recoveryStatePathResolver,
  VaultWipeTargetPathsResolver? vaultWipeTargetPathsResolver,
  ClipboardPort? clipboardPort,
  BiometricKeyStore? biometricKeyStore,
}) {
  serviceLocator.registerSingleton<AppConfig>(config);
  serviceLocator.registerSingleton<RedactionFilter>(const RedactionFilter());
  serviceLocator.registerSingleton<LogSink>(const DeveloperLogSink());
  serviceLocator.registerSingleton<Logger>(
    RedactingLogger(
      serviceLocator<LogSink>(),
      serviceLocator<RedactionFilter>(),
    ),
  );
  serviceLocator.registerSingleton<EventTracker>(const NoopEventTracker());
  serviceLocator.registerSingleton<MetricsRecorder>(
    const NoopMetricsRecorder(),
  );
  serviceLocator.registerSingleton<SensitiveClipboardController>(
    SensitiveClipboardController(
      clipboardPort ?? const FlutterClipboardPort(),
      timeout: config.sensitiveClipboardTimeout,
    ),
    dispose: (SensitiveClipboardController controller) => controller.dispose(),
  );

  if (cryptoService != null && vaultPathResolver != null) {
    if (biometricKeyStore != null) {
      serviceLocator.registerSingleton<BiometricKeyStore>(biometricKeyStore);
    }
    serviceLocator.registerSingleton<CryptoService>(cryptoService);
    serviceLocator.registerSingleton<VaultFileEngine>(VaultFileEngine());
    serviceLocator.registerSingleton<EncryptedVaultRepository>(
      EncryptedVaultRepository(
        crypto: serviceLocator<CryptoService>(),
        vaultFileEngine: serviceLocator<VaultFileEngine>(),
        vaultPathResolver: vaultPathResolver,
        biometricKeyStore: serviceLocator.isRegistered<BiometricKeyStore>()
            ? serviceLocator<BiometricKeyStore>()
            : null,
      ),
    );
    serviceLocator.registerSingleton<VaultRepository>(
      serviceLocator<EncryptedVaultRepository>(),
    );
    serviceLocator.registerSingleton<Argon2idBenchmark>(
      Argon2idBenchmark(serviceLocator<CryptoService>()),
    );
    serviceLocator.registerSingleton<CreateVault>(
      CreateVault(
        serviceLocator<VaultRepository>(),
        serviceLocator<Argon2idBenchmark>(),
      ),
    );
    serviceLocator.registerFactory<SetupCubit>(
      () => SetupCubit(serviceLocator<CreateVault>()),
    );
    serviceLocator.registerSingleton<AddVaultEntry>(
      AddVaultEntry(serviceLocator<VaultRepository>()),
    );
    serviceLocator.registerSingleton<VaultEntriesCubit>(
      VaultEntriesCubit(
        serviceLocator<AddVaultEntry>(),
        serviceLocator<VaultRepository>(),
      ),
      dispose: (VaultEntriesCubit cubit) => cubit.close(),
    );
    serviceLocator.registerSingleton<SessionSecretCleaner>(
      SessionSecretCleaners(<SessionSecretCleaner>[
        serviceLocator<EncryptedVaultRepository>(),
        serviceLocator<VaultEntriesCubit>(),
      ]),
    );
  }

  if (cryptoService != null) {
    serviceLocator.registerSingleton<PasswordRandomSource>(
      CryptoPasswordRandomSource(cryptoService),
    );
    serviceLocator.registerSingleton<GeneratePassword>(
      GeneratePassword(serviceLocator<PasswordRandomSource>()),
    );
  }

  final SessionState initialState = config.vaultExistsAtLaunch
      ? const LockedSession(reason: LockReason.coldStart)
      : const VaultNotCreatedSession();
  serviceLocator.registerSingleton<SessionController>(
    SessionController(
      initialState: initialState,
      secretCleaner: serviceLocator.isRegistered<SessionSecretCleaner>()
          ? serviceLocator<SessionSecretCleaner>()
          : null,
    ),
    dispose: (SessionController controller) => controller.dispose(),
  );
  if (serviceLocator.isRegistered<BiometricKeyStore>()) {
    serviceLocator.registerSingleton<BiometricSettingsCubit>(
      BiometricSettingsCubit(
        serviceLocator<EncryptedVaultRepository>(),
        serviceLocator<BiometricKeyStore>(),
        sessionController: serviceLocator<SessionController>(),
      ),
      dispose: (BiometricSettingsCubit cubit) => cubit.close(),
    );
  }
  if (serviceLocator.isRegistered<EncryptedVaultRepository>()) {
    if (serviceLocator.isRegistered<BiometricKeyStore>() &&
        vaultPathResolver != null &&
        recoveryStatePathResolver != null) {
      final VaultWipeTargetPathsResolver wipeTargets =
          vaultWipeTargetPathsResolver ??
          () async {
            final String vaultPath = await vaultPathResolver();
            final String recoveryPath = await recoveryStatePathResolver();
            return <String>[
              vaultPath,
              '$vaultPath.bak',
              '$vaultPath.tmp',
              '$vaultPath.migration.tmp',
              recoveryPath,
              '$recoveryPath.tmp',
            ];
          };
      serviceLocator.registerSingleton<VaultWipeRepository>(
        FileVaultWipeRepository(
          biometricKeyStore: serviceLocator<BiometricKeyStore>(),
          targetPathsResolver: wipeTargets,
        ),
      );
      serviceLocator.registerSingleton<WipeVault>(
        WipeVault(
          serviceLocator<VaultWipeRepository>(),
          serviceLocator<SessionController>(),
        ),
      );
    }
    if (serviceLocator.isRegistered<BiometricKeyStore>() &&
        recoveryStatePathResolver != null) {
      serviceLocator.registerSingleton<MasterPasswordRecoveryStore>(
        FileMasterPasswordRecoveryStore(
          pathResolver: recoveryStatePathResolver,
        ),
      );
      serviceLocator.registerSingleton<MasterPasswordRecoveryGate>(
        MasterPasswordRecoveryGate(
          serviceLocator<MasterPasswordRecoveryStore>(),
        ),
      );
      serviceLocator.registerSingleton<BiometricRecoveryConfirmer>(
        BiometricKeyStoreRecoveryConfirmer(serviceLocator<BiometricKeyStore>()),
      );
      serviceLocator.registerSingleton<MasterPasswordRecoveryRepository>(
        serviceLocator<EncryptedVaultRepository>(),
      );
      serviceLocator.registerSingleton<RecoverMasterPassword>(
        RecoverMasterPassword(
          gate: serviceLocator<MasterPasswordRecoveryGate>(),
          biometricConfirmer: serviceLocator<BiometricRecoveryConfirmer>(),
          repository: serviceLocator<MasterPasswordRecoveryRepository>(),
        ),
      );
    }
    serviceLocator.registerSingleton<MasterPasswordChangeRepository>(
      serviceLocator<EncryptedVaultRepository>(),
    );
    serviceLocator.registerSingleton<ChangeMasterPassword>(
      ChangeMasterPassword(serviceLocator<MasterPasswordChangeRepository>()),
    );
    serviceLocator.registerSingleton<MasterPasswordChangeCubit>(
      MasterPasswordChangeCubit(
        serviceLocator<ChangeMasterPassword>(),
        serviceLocator<SessionController>(),
        recoveryGate: serviceLocator.isRegistered<MasterPasswordRecoveryGate>()
            ? serviceLocator<MasterPasswordRecoveryGate>()
            : null,
        hasConfiguredBiometricRecovery:
            serviceLocator.isRegistered<RecoverMasterPassword>()
            ? serviceLocator<EncryptedVaultRepository>()
                  .hasConfiguredBiometricUnlock
            : null,
        recoverMasterPassword:
            serviceLocator.isRegistered<RecoverMasterPassword>()
            ? serviceLocator<RecoverMasterPassword>()
            : null,
      ),
      dispose: (MasterPasswordChangeCubit cubit) => cubit.close(),
    );
    serviceLocator.registerSingleton<MasterPasswordVerifier>(
      serviceLocator<EncryptedVaultRepository>(),
    );
    serviceLocator.registerSingleton<VerifyMasterPassword>(
      VerifyMasterPassword(serviceLocator<MasterPasswordVerifier>()),
    );
    serviceLocator.registerSingleton<StepUpCubit>(
      StepUpCubit(
        serviceLocator<VerifyMasterPassword>(),
        serviceLocator<SessionController>(),
      ),
      dispose: (StepUpCubit cubit) => cubit.close(),
    );
  }
  serviceLocator.registerFactory<AuthCubit>(
    () => AuthCubit(serviceLocator<SessionController>()),
  );
  if (serviceLocator.isRegistered<VaultRepository>()) {
    serviceLocator.registerSingleton<UnlockVault>(
      UnlockVault(serviceLocator<VaultRepository>()),
    );
    serviceLocator.registerFactory<UnlockCubit>(
      () => UnlockCubit(
        serviceLocator<UnlockVault>(),
        serviceLocator<SessionController>(),
        onUnlocked: serviceLocator<VaultEntriesCubit>().refresh,
      ),
    );
    if (serviceLocator.isRegistered<BiometricKeyStore>()) {
      serviceLocator.registerSingleton<BiometricUnlockCubit>(
        BiometricUnlockCubit(
          serviceLocator<EncryptedVaultRepository>(),
          serviceLocator<BiometricKeyStore>(),
          serviceLocator<SessionController>(),
          onUnlocked: serviceLocator<VaultEntriesCubit>().refresh,
        ),
        dispose: (BiometricUnlockCubit cubit) => cubit.close(),
      );
    }
  }
}

/// Initializes native crypto and the application-support vault location.
Future<void> registerProductionAppDependencies(GetIt serviceLocator) async {
  final Directory appSupportDirectory = await getApplicationSupportDirectory();
  final Directory appDocumentsDirectory =
      await getApplicationDocumentsDirectory();
  final String vaultPath =
      '${appSupportDirectory.path}${Platform.pathSeparator}vault.psw';
  final String recoveryStatePath =
      '${appSupportDirectory.path}${Platform.pathSeparator}'
      'master_password_recovery.json';
  final CryptoService cryptoService = await SodiumCryptoService.initialize();
  registerAppDependencies(
    serviceLocator,
    config: AppConfig(vaultExistsAtLaunch: File(vaultPath).existsSync()),
    cryptoService: cryptoService,
    vaultPathResolver: () async => vaultPath,
    recoveryStatePathResolver: () async => recoveryStatePath,
    vaultWipeTargetPathsResolver: () async => <String>[
      vaultPath,
      '$vaultPath.bak',
      '$vaultPath.tmp',
      '$vaultPath.migration.tmp',
      recoveryStatePath,
      '$recoveryStatePath.tmp',
      '${appDocumentsDirectory.path}${Platform.pathSeparator}logs',
    ],
    biometricKeyStore: const MethodChannelBiometricKeyStore(),
  );
}
