import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';

void main() {
  group('SessionController', () {
    test('starts in a cold-start no-vault state', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      expect(controller.state, isA<VaultNotCreatedSession>());
      expect(
        (controller.state as VaultNotCreatedSession).startReason,
        SessionStartReason.coldStart,
      );
      expect(controller.routeState, SessionRouteState.setup);
    });

    test('moves created vaults into cold-start locked state', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      controller.markVaultCreated();

      expect(controller.state, isA<LockedSession>());
      expect((controller.state as LockedSession).reason, LockReason.coldStart);
      expect(controller.routeState, SessionRouteState.unlock);
      expect((controller.state as LockedSession).canUseBiometric, isFalse);
    });

    test('preserves authentication strength until the next lock', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      controller.unlock(AuthStrength.masterPassword);

      expect(controller.state, isA<UnlockedSession>());
      expect(
        (controller.state as UnlockedSession).authStrength,
        AuthStrength.masterPassword,
      );
      expect(controller.routeState, SessionRouteState.home);

      controller.lock(LockReason.backgroundOrTimeout);

      expect(controller.state, isA<LockedSession>());
      expect((controller.state as LockedSession).canUseBiometric, isTrue);
      expect(controller.routeState, SessionRouteState.unlock);
    });

    test('rejects an unlock without successful authentication', () {
      final SessionController controller = SessionController();
      addTearDown(controller.dispose);

      expect(() => controller.unlock(AuthStrength.none), throwsArgumentError);
    });
  });
}
