import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/unlock_page.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/features/auth/presentation/deadlock_wipe_cubit.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('keeps wipe hidden until gesture and allows countdown cancel', (
    WidgetTester tester,
  ) async {
    final Completer<void> delay = Completer<void>();
    final _WidgetWipeRepository repository = _WidgetWipeRepository();
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final DeadlockWipeCubit cubit = DeadlockWipeCubit(
      WipeVault(repository, sessionController),
      delay: (_) => delay.future,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UnlockPage(
          sessionController: sessionController,
          deadlockWipeCubit: cubit,
        ),
      ),
    );

    final Finder trigger = find.byKey(
      const ValueKey<String>('deadlock-wipe-trigger'),
    );
    for (var tap = 0; tap < 6; tap++) {
      await tester.tap(trigger);
    }
    await tester.pump();
    expect(find.text('Permanently delete vault'), findsNothing);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('Permanently delete vault'), findsOneWidget);
    expect(
      find.text(
        'This permanently deletes every password and cannot be undone.',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('deadlock-wipe-confirmation')),
      'DELETE',
    );
    await tester.tap(find.text('Start 10-second countdown'));
    await tester.pump();
    expect(find.text('Deleting in 10 seconds'), findsOneWidget);

    await tester.tap(find.text('Cancel deletion'));
    delay.complete();
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
    expect(find.text('Permanently delete vault'), findsOneWidget);
  });
}

final class _WidgetWipeRepository implements VaultWipeRepository {
  var calls = 0;

  @override
  Future<void> wipeVault() async => calls++;
}
