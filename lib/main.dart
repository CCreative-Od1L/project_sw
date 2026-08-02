import 'package:flutter/widgets.dart';
import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';

/// Starts the application after composing its process-wide dependencies.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await registerProductionAppDependencies(appServiceLocator);

  runApp(
    ProjectSwApp(
      sessionController: appServiceLocator<SessionController>(),
      authCubit: appServiceLocator<AuthCubit>(),
      setupCubit: appServiceLocator<SetupCubit>(),
    ),
  );
}
