import 'package:flutter/widgets.dart';
import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';
import 'package:project_sw/app/pages/generator_page.dart';
import 'package:project_sw/app/pages/settings_page.dart';

/// Starts the application after composing its process-wide dependencies.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await registerProductionAppDependencies(appServiceLocator);

  runApp(
    ProjectSwApp(
      sessionController: appServiceLocator<SessionController>(),
      authCubit: appServiceLocator<AuthCubit>(),
      setupCubit: appServiceLocator<SetupCubit>(),
      unlockCubit: appServiceLocator<UnlockCubit>(),
      biometricUnlockCubit:
          appServiceLocator.isRegistered<BiometricUnlockCubit>()
          ? appServiceLocator<BiometricUnlockCubit>()
          : null,
      vaultEntriesCubit: appServiceLocator<VaultEntriesCubit>(),
      sensitiveClipboardController:
          appServiceLocator<SensitiveClipboardController>(),
      generatePassword: appServiceLocator<GeneratePassword>(),
      passwordRandomSource: appServiceLocator<PasswordRandomSource>(),
      generatorPageBuilder: (_) => GeneratorPage(
        generatePassword: appServiceLocator<GeneratePassword>(),
        randomSource: appServiceLocator<PasswordRandomSource>(),
        sensitiveClipboardController:
            appServiceLocator<SensitiveClipboardController>(),
        sessionController: appServiceLocator<SessionController>(),
      ),
      settingsPageBuilder: (_) => SettingsPage(
        config: appServiceLocator<AppConfig>(),
        vaultRepository: appServiceLocator<VaultRepository>(),
        biometricSettingsCubit:
            appServiceLocator.isRegistered<BiometricSettingsCubit>()
            ? appServiceLocator<BiometricSettingsCubit>()
            : null,
      ),
    ),
  );
}
