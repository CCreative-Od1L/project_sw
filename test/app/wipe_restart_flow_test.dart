import 'dart:async';

import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/features/auth/domain/authenticated_wipe_vault.dart';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/presentation/authenticated_wipe_cubit.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/setup_page.dart';
import 'package:project_sw/app/pages/unlock_page.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/deadlock_wipe_cubit.dart';

void main() {
  test('concurrent wipe requests share one irreversible transaction', () async {
    final SessionController session = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    addTearDown(session.dispose);
    final Completer<void> deletion = Completer<void>();
    final _Repository repository = _Repository(waitFor: deletion.future);
    final WipeVault wipe = WipeVault(repository, session);

    final Future<WipedVault> first = wipe();
    final Future<WipedVault> second = wipe();
    expect(identical(first, second), isTrue);
    expect(repository.calls, 1);
    expect(wipe.isPending, isTrue);
    deletion.complete();
    await Future.wait(<Future<WipedVault>>[first, second]);
    expect(repository.calls, 1);
    expect(session.state, isA<VaultNotCreatedSession>());
    expect(wipe.inFlight, isNull);
  });

  test(
    'recovery cannot reveal the hidden escape path for a normal lock',
    () async {
      final SessionController session = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      final DeadlockWipeCubit cubit = DeadlockWipeCubit(
        WipeVault(_Repository(), session),
      );
      addTearDown(cubit.close);
      addTearDown(session.dispose);
      await cubit.revealPendingWipe();
      expect(cubit.state, isA<DeadlockWipeHidden>());
    },
  );

  testWidgets('restored wipe hides authentication and retries through setup', (
    WidgetTester tester,
  ) async {
    final SessionController session = SessionController(
      initialState: const LockedSession(reason: LockReason.wipeStarted),
    );
    final AuthCubit auth = AuthCubit(session);
    final _Repository repository = _Repository(failuresRemaining: 1);
    final DeadlockWipeCubit cubit = DeadlockWipeCubit(
      WipeVault(repository, session),
      delay: (_) async {},
    );
    addTearDown(cubit.close);
    addTearDown(auth.close);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      ProjectSwApp(
        sessionController: session,
        authCubit: auth,
        deadlockWipeCubit: cubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Deletion incomplete'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('continue-vault-wipe')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('deadlock-wipe-confirmation')),
      'delete',
    );
    await tester.tap(find.text('Start 10-second countdown'));
    await tester.pumpAndSettle();
    expect(repository.calls, 0);

    await tester.enterText(
      find.byKey(const ValueKey<String>('deadlock-wipe-confirmation')),
      'DELETE',
    );
    await tester.tap(find.text('Start 10-second countdown'));
    await tester.pumpAndSettle();
    expect(cubit.state, isA<DeadlockWipeFault>());
    expect(repository.calls, 1);
    expect(find.byType(SetupPage), findsNothing);
    expect(session.beginUnlockAttempt, throwsStateError);

    await tester.tap(find.text('Start 10-second countdown'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.byType(SetupPage), findsOneWidget);
    expect(find.byType(UnlockPage), findsNothing);
    expect(session.state, isA<VaultNotCreatedSession>());
  });

  testWidgets('recovery observes an ongoing wipe without a second deletion', (
    WidgetTester tester,
  ) async {
    final SessionController session = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final AuthCubit auth = AuthCubit(session);
    final Completer<void> deletion = Completer<void>();
    final _Repository repository = _Repository(waitFor: deletion.future);
    final WipeVault wipe = WipeVault(repository, session);
    final Future<WipedVault> original = wipe();
    final DeadlockWipeCubit cubit = DeadlockWipeCubit(wipe);
    addTearDown(cubit.close);
    addTearDown(auth.close);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      ProjectSwApp(
        sessionController: session,
        authCubit: auth,
        deadlockWipeCubit: cubit,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('continue-vault-wipe')));
    await tester.pump();
    expect(cubit.state, isA<DeadlockWipeWorking>());
    expect(repository.calls, 1);
    expect(find.byType(TextField), findsNothing);
    deletion.complete();
    await original;
    await tester.pumpAndSettle();
    expect(find.byType(SetupPage), findsOneWidget);
    expect(repository.calls, 1);
  });
  testWidgets(
    'authenticated deletion reaches setup through the production router',
    (WidgetTester tester) async {
      final SessionController session = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      final AuthCubit auth = AuthCubit(session);
      final _Repository repository = _Repository();
      final WipeVault wipe = WipeVault(repository, session);
      final DeadlockWipeCubit recovery = DeadlockWipeCubit(wipe);
      final AuthenticatedWipeCubit authenticated = AuthenticatedWipeCubit(
        AuthenticatedWipeVault(
          VerifyMasterPassword(_Verifier()),
          wipe,
          session,
        ),
      );
      addTearDown(auth.close);
      addTearDown(recovery.close);
      addTearDown(authenticated.close);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        ProjectSwApp(
          sessionController: session,
          authCubit: auth,
          deadlockWipeCubit: recovery,
          settingsPageBuilder: (_) => SettingsPage(
            sessionController: session,
            authenticatedWipeCubit: authenticated,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Permanently delete vault'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('authenticated-wipe-password')),
        'current password',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Permanently delete vault').last,
      );
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(find.byType(SetupPage), findsOneWidget);
      expect(session.state, isA<VaultNotCreatedSession>());
    },
  );
}

final class _Repository implements VaultWipeRepository {
  _Repository({this.failuresRemaining = 0, this.waitFor});
  int failuresRemaining;
  final Future<void>? waitFor;
  int calls = 0;
  @override
  Future<void> wipeVault() async {
    calls++;
    await waitFor;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const VaultWipeException();
    }
  }
}

final class _Verifier implements MasterPasswordVerifier {
  @override
  Future<void> verifyMasterPassword(String masterPassword) async {}
}
