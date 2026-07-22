import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/observability/logger.dart';
import 'package:project_sw/core/observability/redaction_filter.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

void main() {
  test(
    'dependency registration resolves every initial application contract',
    () async {
      final GetIt serviceLocator = GetIt.asNewInstance();
      addTearDown(() => serviceLocator.reset(dispose: true));

      registerAppDependencies(serviceLocator);

      expect(serviceLocator<AppConfig>(), isA<AppConfig>());
      expect(serviceLocator<RedactionFilter>(), isA<RedactionFilter>());
      expect(serviceLocator<LogSink>(), isA<DeveloperLogSink>());
      expect(serviceLocator<Logger>(), isA<RedactingLogger>());
      expect(serviceLocator<EventTracker>(), isA<NoopEventTracker>());
      expect(serviceLocator<MetricsRecorder>(), isA<NoopMetricsRecorder>());
      expect(serviceLocator<SessionController>(), isA<SessionController>());
      expect(serviceLocator<AuthCubit>(), isA<AuthCubit>());
    },
  );

  test(
    'bootstrap maps an existing vault to the cold-start locked state',
    () async {
      final GetIt serviceLocator = GetIt.asNewInstance();
      addTearDown(() => serviceLocator.reset(dispose: true));

      registerAppDependencies(
        serviceLocator,
        config: const AppConfig(vaultExistsAtLaunch: true),
      );

      final SessionController controller = serviceLocator<SessionController>();

      expect(controller.state, isA<LockedSession>());
      expect((controller.state as LockedSession).reason, LockReason.coldStart);
    },
  );
}
