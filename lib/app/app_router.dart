import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:project_sw/app/pages/app_shell.dart';
import 'package:project_sw/app/pages/generator_page.dart';
import 'package:project_sw/app/pages/home_page.dart';
import 'package:project_sw/app/pages/setup_page.dart';
import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/app/pages/unlock_page.dart';
import 'package:project_sw/app/route_paths.dart';
import 'package:project_sw/app/session_lifecycle_adapter.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/features/auth/presentation/deadlock_wipe_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';

/// Builds the application router from one session-derived route state source.
GoRouter buildAppRouter(
  SessionController sessionController, {
  SetupCubit? setupCubit,
  UnlockCubit? unlockCubit,
  BiometricUnlockCubit? biometricUnlockCubit,
  DeadlockWipeCubit? deadlockWipeCubit,
  VaultEntriesCubit? vaultEntriesCubit,
  WidgetBuilder? generatorPageBuilder,
  WidgetBuilder? settingsPageBuilder,
  GeneratePassword? generatePassword,
  PasswordRandomSource? passwordRandomSource,
}) {
  return GoRouter(
    initialLocation: sessionController.routeState.path,
    observers: <NavigatorObserver>[
      SessionNavigationObserver(sessionController),
    ],
    refreshListenable: sessionController,
    redirect: (BuildContext context, GoRouterState state) {
      return redirectForSessionRoute(
        routeState: sessionController.routeState,
        location: state.matchedLocation,
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: SessionRouteState.setup.path,
        builder: (BuildContext context, GoRouterState state) => SetupPage(
          sessionController: sessionController,
          setupCubit: setupCubit,
        ),
      ),
      GoRoute(
        path: SessionRouteState.unlock.path,
        builder: (BuildContext context, GoRouterState state) => UnlockPage(
          sessionController: sessionController,
          unlockCubit: unlockCubit,
          biometricUnlockCubit: biometricUnlockCubit,
          deadlockWipeCubit: deadlockWipeCubit,
        ),
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AppShell(currentLocation: state.uri.path, child: child),
        routes: <RouteBase>[
          GoRoute(
            path: vaultRoutePath,
            builder: (BuildContext context, GoRouterState state) => HomePage(
              sessionController: sessionController,
              vaultEntriesCubit: vaultEntriesCubit,
              generatePassword: generatePassword,
              passwordRandomSource: passwordRandomSource,
            ),
          ),
          GoRoute(
            path: generatorRoutePath,
            builder: (BuildContext context, GoRouterState state) =>
                generatorPageBuilder?.call(context) ?? const GeneratorPage(),
          ),
          GoRoute(
            path: settingsRoutePath,
            builder: (BuildContext context, GoRouterState state) =>
                settingsPageBuilder?.call(context) ?? const SettingsPage(),
          ),
        ],
      ),
    ],
  );
}

/// Returns a redirect using only a previously-derived [routeState].
String? redirectForSessionRoute({
  required SessionRouteState routeState,
  required String location,
}) {
  return switch (routeState) {
    SessionRouteState.setup =>
      location == SessionRouteState.setup.path
          ? null
          : SessionRouteState.setup.path,
    SessionRouteState.unlock => switch (location) {
      '/unlock' || generatorRoutePath => null,
      _ => SessionRouteState.unlock.path,
    },
    SessionRouteState.home => switch (location) {
      vaultRoutePath || generatorRoutePath || settingsRoutePath => null,
      _ => vaultRoutePath,
    },
  };
}
