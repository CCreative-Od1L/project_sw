import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/app_router.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';

void main() {
  test('redirect uses only the supplied session route state', () {
    expect(
      redirectForSessionRoute(
        routeState: SessionRouteState.setup,
        location: '/home',
      ),
      '/setup',
    );
    expect(
      redirectForSessionRoute(
        routeState: SessionRouteState.unlock,
        location: '/setup',
      ),
      '/unlock',
    );
    expect(
      redirectForSessionRoute(
        routeState: SessionRouteState.home,
        location: '/unlock',
      ),
      '/home',
    );
    expect(
      redirectForSessionRoute(
        routeState: SessionRouteState.home,
        location: '/home',
      ),
      isNull,
    );
  });
}
