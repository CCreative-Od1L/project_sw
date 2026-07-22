import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

void main() {
  test(
    'projects session state without owning route or strength rules',
    () async {
      final SessionController controller = SessionController();
      final AuthCubit cubit = AuthCubit(controller);
      addTearDown(cubit.close);
      addTearDown(controller.dispose);

      expect(cubit.state.routeState, SessionRouteState.setup);
      expect(cubit.state.isLocked, isTrue);
      expect(cubit.state.authStrength, AuthStrength.none);

      controller.lock(LockReason.backgroundOrTimeout);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.routeState, SessionRouteState.unlock);
      expect(cubit.state.canUseBiometric, isTrue);
      expect(cubit.state.lockReason, LockReason.backgroundOrTimeout);

      controller.unlock(AuthStrength.biometric);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.routeState, SessionRouteState.home);
      expect(cubit.state.isLocked, isFalse);
      expect(cubit.state.authStrength, AuthStrength.biometric);
    },
  );
}
