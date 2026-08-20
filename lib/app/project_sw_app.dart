import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_sw/app/app_router.dart';
import 'package:project_sw/app/app_theme.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/session_lifecycle_adapter.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_scope.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/features/auth/presentation/deadlock_wipe_cubit.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

/// Root application widget that wires presentation projections and the router.
final class ProjectSwApp extends StatefulWidget {
  /// Creates the application with its already-composed session dependencies.
  const ProjectSwApp({
    super.key,
    required this.sessionController,
    required this.authCubit,
    this.setupCubit,
    this.unlockCubit,
    this.biometricUnlockCubit,
    this.deadlockWipeCubit,
    this.vaultEntriesCubit,
    this.sensitiveClipboardController,
    this.generatorPageBuilder,
    this.settingsPageBuilder,
    this.generatePassword,
    this.passwordRandomSource,
  });

  /// The global session source of truth.
  final SessionController sessionController;

  /// The UI-only projection of [sessionController].
  final AuthCubit authCubit;

  /// The optional setup flow; omitted only by route-focused widget tests.
  final SetupCubit? setupCubit;

  /// The optional unlock form; omitted only by route-focused widget tests.
  final UnlockCubit? unlockCubit;

  /// Optional biometric unlock action coordinator.
  final BiometricUnlockCubit? biometricUnlockCubit;

  /// Optional hidden deadlock-wipe escape path coordinator.
  final DeadlockWipeCubit? deadlockWipeCubit;

  /// Optional unlocked-entry projection, omitted only by route skeleton tests.
  final VaultEntriesCubit? vaultEntriesCubit;

  /// Shared sensitive clipboard cleanup coordinator.
  final SensitiveClipboardController? sensitiveClipboardController;

  /// Optional injected generator route used by the generator feature slice.
  final WidgetBuilder? generatorPageBuilder;

  /// Optional injected settings route used by the settings feature slice.
  final WidgetBuilder? settingsPageBuilder;

  /// Generator use case injected at the application composition root.
  final GeneratePassword? generatePassword;

  /// Generator CSPRNG boundary injected at the application composition root.
  final PasswordRandomSource? passwordRandomSource;

  @override
  State<ProjectSwApp> createState() => _ProjectSwAppState();
}

final class _ProjectSwAppState extends State<ProjectSwApp> {
  late final SensitiveClipboardController _fallbackClipboardController =
      SensitiveClipboardController(const FlutterClipboardPort());
  late final GoRouter _router = buildAppRouter(
    widget.sessionController,
    setupCubit: widget.setupCubit,
    unlockCubit: widget.unlockCubit,
    biometricUnlockCubit: widget.biometricUnlockCubit,
    deadlockWipeCubit: widget.deadlockWipeCubit,
    vaultEntriesCubit: widget.vaultEntriesCubit,
    generatorPageBuilder: widget.generatorPageBuilder,
    settingsPageBuilder: widget.settingsPageBuilder,
    generatePassword: widget.generatePassword,
    passwordRandomSource: widget.passwordRandomSource,
  );

  @override
  void dispose() {
    _router.dispose();
    _fallbackClipboardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>.value(
      value: widget.authCubit,
      child: SessionLifecycleAdapter(
        sessionController: widget.sessionController,
        onForegrounded: widget.sensitiveClipboardController?.onForegrounded,
        child: SensitiveClipboardScope(
          controller:
              widget.sensitiveClipboardController ??
              _fallbackClipboardController,
          child: MaterialApp.router(
            title: 'Project SW',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            localeResolutionCallback:
                (Locale? deviceLocale, Iterable<Locale> supportedLocales) {
                  return resolveAppLocale(deviceLocale);
                },
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
