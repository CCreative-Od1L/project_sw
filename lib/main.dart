import 'package:flutter/widgets.dart';
import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

/// Starts the application after composing its process-wide dependencies.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppDependencies(appServiceLocator);

  runApp(
    ProjectSwApp(
      sessionController: appServiceLocator<SessionController>(),
      authCubit: appServiceLocator<AuthCubit>(),
    ),
  );
}
