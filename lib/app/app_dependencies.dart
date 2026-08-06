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
import 'package:project_sw/features/auth/domain/create_vault.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/unlock_vault.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
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
  ClipboardPort? clipboardPort,
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
    serviceLocator.registerSingleton<CryptoService>(cryptoService);
    serviceLocator.registerSingleton<VaultFileEngine>(VaultFileEngine());
    serviceLocator.registerSingleton<EncryptedVaultRepository>(
      EncryptedVaultRepository(
        crypto: serviceLocator<CryptoService>(),
        vaultFileEngine: serviceLocator<VaultFileEngine>(),
        vaultPathResolver: vaultPathResolver,
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
  }
}

/// Initializes native crypto and the application-support vault location.
Future<void> registerProductionAppDependencies(GetIt serviceLocator) async {
  final Directory appSupportDirectory = await getApplicationSupportDirectory();
  final String vaultPath =
      '${appSupportDirectory.path}${Platform.pathSeparator}vault.psw';
  final CryptoService cryptoService = await SodiumCryptoService.initialize();
  registerAppDependencies(
    serviceLocator,
    config: AppConfig(vaultExistsAtLaunch: File(vaultPath).existsSync()),
    cryptoService: cryptoService,
    vaultPathResolver: () async => vaultPath,
  );
}
