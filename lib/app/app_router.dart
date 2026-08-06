import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:project_sw/app/pages/home_page.dart';
import 'package:project_sw/app/pages/setup_page.dart';
import 'package:project_sw/app/pages/unlock_page.dart';
import 'package:project_sw/app/session_lifecycle_adapter.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';

/// Builds the application router from one session-derived route state source.
GoRouter buildAppRouter(
  SessionController sessionController, {
  SetupCubit? setupCubit,
  UnlockCubit? unlockCubit,
  VaultEntriesCubit? vaultEntriesCubit,
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
        ),
      ),
      GoRoute(
        path: SessionRouteState.home.path,
        builder: (BuildContext context, GoRouterState state) => HomePage(
          sessionController: sessionController,
          vaultEntriesCubit: vaultEntriesCubit,
        ),
      ),
    ],
  );
}

/// Returns a redirect using only a previously-derived [routeState].
String? redirectForSessionRoute({
  required SessionRouteState routeState,
  required String location,
}) {
  final String expectedPath = routeState.path;
  return location == expectedPath ? null : expectedPath;
}
