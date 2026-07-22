import 'package:get_it/get_it.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/observability/logger.dart';
import 'package:project_sw/core/observability/redaction_filter.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

/// The production dependency container used by the application composition root.
final GetIt appServiceLocator = GetIt.instance;

/// Registers the initial application dependencies in [serviceLocator].
void registerAppDependencies(
  GetIt serviceLocator, {
  AppConfig config = const AppConfig(),
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

  final SessionState initialState = config.vaultExistsAtLaunch
      ? const LockedSession(reason: LockReason.coldStart)
      : const VaultNotCreatedSession();
  serviceLocator.registerSingleton<SessionController>(
    SessionController(initialState: initialState),
    dispose: (SessionController controller) => controller.dispose(),
  );
  serviceLocator.registerFactory<AuthCubit>(
    () => AuthCubit(serviceLocator<SessionController>()),
  );
}
