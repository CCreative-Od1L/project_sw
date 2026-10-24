import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/home_page.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

void main() {
  testWidgets('application routes preserve platform Material page behavior', (
    WidgetTester tester,
  ) async {
    final session = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    final auth = AuthCubit(session);
    addTearDown(auth.close);
    await tester.pumpWidget(
      ProjectSwApp(sessionController: session, authCubit: auth),
    );
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(HomePage)));
    final settings = route?.settings;
    // A WidgetsApp fallback silently loses Material platform transitions.
    // Unmount and end the session before asserting, including on failure.
    session.lock(LockReason.manualLock);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    expect(settings, isA<MaterialPage<dynamic>>());
  });
}
