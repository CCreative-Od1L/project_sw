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
    final SessionController sessionController = SessionController();
    addTearDown(sessionController.dispose);

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
  var senderPrepared = false;
  var senderRunStarted = false;
  var cancelCount = 0;

  @override
  Future<MigrationPairingPayload> prepareSender() async {
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
  Future<void> runReceiver(MigrationPairingPayload payload) async {}

  @override
  Future<void> cancel() async {
    cancelCount++;
    if (!senderCompleter.isCompleted) senderCompleter.complete();
  }
}
