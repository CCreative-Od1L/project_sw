import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_sw/app/app_router.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

/// Root application widget that wires presentation projections and the router.
final class ProjectSwApp extends StatefulWidget {
  /// Creates the application with its already-composed session dependencies.
  const ProjectSwApp({
    super.key,
    required this.sessionController,
    required this.authCubit,
  });

  /// The global session source of truth.
  final SessionController sessionController;

  /// The UI-only projection of [sessionController].
  final AuthCubit authCubit;

  @override
  State<ProjectSwApp> createState() => _ProjectSwAppState();
}

final class _ProjectSwAppState extends State<ProjectSwApp> {
  late final GoRouter _router = buildAppRouter(widget.sessionController);

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
