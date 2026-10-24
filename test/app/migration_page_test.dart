import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'dart:convert';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/presentation/step_up_cubit.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/pages/migration_page.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/migration/data/migration_flow.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('sender displays a short-lived QR pairing screen', (
    WidgetTester tester,
  ) async {
    final FakeMigrationFlow flow = FakeMigrationFlow();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MigrationPage(sessionController: sessionController, flow: flow),
      ),
    );

    expect(find.text('Choose this device\'s migration role'), findsOneWidget);
    await tester.tap(find.text('Show QR code'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('migration-qr-code')),
      findsOneWidget,
    );
    expect(find.text('Waiting for the other device to scan…'), findsOneWidget);
    expect(flow.senderRunStarted, isTrue);

    await tester.tap(find.text('Cancel migration'));
    await tester.pump();
    expect(find.text('Choose this device\'s migration role'), findsOneWidget);
    expect(flow.cancelCount, 1);
    await tester.pumpWidget(const SizedBox());
    sessionController.dispose();
  });
  testWidgets('biometric migration fails closed without a step-up verifier', (
    tester,
  ) async {
    final session = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    final flow = FakeMigrationFlow();
    await _pump(tester, MigrationPage(sessionController: session, flow: flow));
    await tester.tap(find.text('Show QR code'));
    await tester.pumpAndSettle();
    expect(flow.senderPrepared, isFalse);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('wrong password and cancelled step-up never open a listener', (
    tester,
  ) async {
    final session = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    final cubit = StepUpCubit(VerifyMasterPassword(_Verifier()), session);
    final flow = FakeMigrationFlow();
    await _pump(
      tester,
      MigrationPage(sessionController: session, flow: flow, stepUpCubit: cubit),
    );
    await tester.tap(find.text('Show QR code'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(flow.senderPrepared, isFalse);
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Verify master password'),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(flow.senderPrepared, isFalse);
    expect(session.requiresMasterPasswordStepUp, isTrue);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(flow.senderPrepared, isFalse);
    await tester.pumpWidget(const SizedBox());
    await cubit.close();
    session.dispose();
  });

  testWidgets(
    'verified step-up sends the selected entry instead of all entries',
    (tester) async {
      final session = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      final cubit = StepUpCubit(VerifyMasterPassword(_Verifier()), session);
      final flow = FakeMigrationFlow();
      final entry = EntrySummary(
        entryId: Uint8List.fromList(List<int>.filled(16, 5)),
        name: 'Only this entry',
        url: '',
        username: '',
        favorite: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await _pump(
        tester,
        MigrationPage(
          sessionController: session,
          flow: flow,
          stepUpCubit: cubit,
          entries: () => <EntrySummary>[entry],
        ),
      );
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey<String>('migration-selection')),
      );
      dropdown.onChanged!(base64Url.encode(entry.entryId));
      await tester.pump();
      await tester.tap(find.text('Show QR code'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(flow.senderPrepared, isFalse);
      await tester.enterText(find.byType(TextField), 'correct');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Verify master password'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(session.requiresMasterPasswordStepUp, isFalse);
      expect(flow.selection!.isAll, isFalse);
      expect(flow.selection!.includes(entry.entryId), isTrue);
      expect(
        find.byKey(const ValueKey<String>('migration-qr-code')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await cubit.close();
      session.dispose();
    },
  );

  testWidgets(
    'receiver prepares before scanning, cancels cleanly, and refreshes after import',
    (tester) async {
      final session = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      final flow = FakeMigrationFlow();
      var scans = 0;
      var refreshes = 0;
      await _pump(
        tester,
        MigrationPage(
          sessionController: session,
          flow: flow,
          scan: (_) async {
            expect(flow.receiverPrepared, isTrue);
            scans++;
            return scans == 1 ? null : flow.payload;
          },
          onImported: () => refreshes++,
        ),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pump();
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(flow.cancelCount, 1);
      expect(refreshes, 0);
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pump();
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(
        find.byKey(const ValueKey<String>('migration-complete')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets('production router exposes migration and revokes it on lock', (
    tester,
  ) async {
    final session = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    final auth = AuthCubit(session);
    final flow = FakeMigrationFlow();
    await tester.pumpWidget(
      ProjectSwApp(
        sessionController: session,
        authCubit: auth,
        migrationPageBuilder: (_) =>
            MigrationPage(sessionController: session, flow: flow),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Show QR code'), findsOneWidget);
    await tester.tap(find.text('Show QR code'));
    await tester.pump();
    session.lock(LockReason.manualLock);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('migration-qr-code')),
      findsNothing,
    );
    expect(find.text('Unlock vault'), findsWidgets);
    expect(flow.cancelCount, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    addTearDown(auth.close);
  });
}

final class FakeMigrationFlow implements MigrationFlow {
  final MigrationPairingPayload payload = MigrationPairingPayload(
    host: '192.168.1.20',
    port: 43123,
    senderPublicKey: Uint8List.fromList(List<int>.filled(32, 7)),
    issuedAtEpochSeconds: 1,
    expiresAtEpochSeconds: 9999999999,
  );
  final Completer<void> senderCompleter = Completer<void>();
  MigrationSelection? selection;
  bool receiverPrepared = false;
  var senderPrepared = false;
  var senderRunStarted = false;
  var cancelCount = 0;

  @override
  Future<MigrationPairingPayload> prepareSender({
    MigrationSelection selection = const MigrationSelection.all(),
  }) async {
    this.selection = selection;
    senderPrepared = true;
    return payload;
  }

  @override
  Future<void> runSender() async {
    if (!senderPrepared) throw StateError('sender was not prepared');
    senderRunStarted = true;
    await senderCompleter.future;
  }

  @override
  Future<void> prepareReceiver() async {
    receiverPrepared = true;
  }

  @override
  Future<void> runReceiver(MigrationPairingPayload payload) async {}

  @override
  Future<void> cancel() async {
    cancelCount++;
    if (!senderCompleter.isCompleted) senderCompleter.complete();
  }
}

Future<void> _pump(WidgetTester tester, Widget page) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: page,
  ),
);

final class _Verifier implements MasterPasswordVerifier {
  @override
  Future<void> verifyMasterPassword(String password) async {
    if (password != 'correct') throw const InvalidMasterPasswordException();
  }
}
