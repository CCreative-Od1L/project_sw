import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';

void main() {
  testWidgets('session changes drive setup, unlock, and home routes', (
    WidgetTester tester,
  ) async {
    final SessionController sessionController = SessionController();
    final AuthCubit authCubit = AuthCubit(sessionController);
    addTearDown(authCubit.close);
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      ProjectSwApp(sessionController: sessionController, authCubit: authCubit),
    );

    expect(find.text('Create your vault'), findsOneWidget);

    sessionController.markVaultCreated();
    await tester.pumpAndSettle();

    expect(find.text('Unlock your vault'), findsOneWidget);

    sessionController.unlock(AuthStrength.masterPassword);
    await tester.pumpAndSettle();

    expect(find.text('Vault unlocked'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock vault'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock your vault'), findsOneWidget);
  });
}
