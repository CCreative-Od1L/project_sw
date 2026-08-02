import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_sw/app/app_router.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';

/// Root application widget that wires presentation projections and the router.
final class ProjectSwApp extends StatefulWidget {
  /// Creates the application with its already-composed session dependencies.
  const ProjectSwApp({
    super.key,
    required this.sessionController,
    required this.authCubit,
    this.setupCubit,
    this.unlockCubit,
    this.vaultEntriesCubit,
  });

  /// The global session source of truth.
  final SessionController sessionController;

  /// The UI-only projection of [sessionController].
  final AuthCubit authCubit;

  /// The optional setup flow; omitted only by route-focused widget tests.
  final SetupCubit? setupCubit;

  /// The optional unlock form; omitted only by route-focused widget tests.
  final UnlockCubit? unlockCubit;

  /// Optional unlocked-entry projection, omitted only by route skeleton tests.
  final VaultEntriesCubit? vaultEntriesCubit;

  @override
  State<ProjectSwApp> createState() => _ProjectSwAppState();
}

final class _ProjectSwAppState extends State<ProjectSwApp> {
  late final GoRouter _router = buildAppRouter(
    widget.sessionController,
    setupCubit: widget.setupCubit,
    unlockCubit: widget.unlockCubit,
    vaultEntriesCubit: widget.vaultEntriesCubit,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>.value(
      value: widget.authCubit,
      child: MaterialApp.router(
        title: 'Project SW',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        routerConfig: _router,
      ),
    );
  }
}
