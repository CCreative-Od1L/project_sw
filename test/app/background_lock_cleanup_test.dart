import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/app/pages/generator_page.dart';
import 'package:project_sw/app/session_lifecycle_adapter.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'background lifecycle locks before asynchronous secret cleanup completes',
    (WidgetTester tester) async {
      final GetIt locator = GetIt.asNewInstance();
      final _BlockingClipboard clipboard = _BlockingClipboard();
      registerAppDependencies(
        locator,
        config: const AppConfig(vaultExistsAtLaunch: true),
        clipboardPort: clipboard,
      );
      final SensitiveClipboardController clipboardController =
          locator<SensitiveClipboardController>();
      final SessionController sessionController = locator<SessionController>();
      sessionController.unlock(AuthStrength.masterPassword);
      addTearDown(() async => locator.reset());

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SessionLifecycleAdapter(
            sessionController: sessionController,
            child: GeneratorPage(
              generatePassword: GeneratePassword(
                SequenceRandomSource(List<int>.filled(20, 0)),
              ),
              randomSource: SequenceRandomSource(const <int>[0]),
              sensitiveClipboardController: clipboardController,
              sessionController: sessionController,
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pump();
      const String generatedPassword = 'aaaaaaaaaaaaaaaaaaaa';
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy generated password'));
      await tester.pumpAndSettle();
      expect(find.text(generatedPassword), findsOneWidget);
      expect(clipboard.value, generatedPassword);

      final List<SessionEvent> events = <SessionEvent>[];
      final StreamSubscription<SessionEvent> subscription = sessionController
          .events
          .listen(events.add);
      addTearDown(subscription.cancel);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      expect(sessionController.state, isA<LockedSession>());
      expect(
        (sessionController.state as LockedSession).reason,
        LockReason.backgroundOrTimeout,
      );
      expect(events, <SessionEvent>[SessionEvent.appBackgrounded]);

      await clipboard.clearStarted.future;
      expect(clipboard.value, generatedPassword);

      clipboard.releaseClear.complete();
      await clipboard.clearFinished.future;
      expect(clipboard.value, isEmpty);
      expect(clipboardController.state.status, SensitiveClipboardStatus.idle);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(events, <SessionEvent>[
        SessionEvent.appBackgrounded,
        SessionEvent.appForegrounded,
      ]);
      expect(find.byType(PasswordGeneratorPanel), findsOneWidget);
      expect(find.text(generatedPassword), findsNothing);
    },
  );
}

final class _BlockingClipboard implements ClipboardPort {
  String value = '';
  final Completer<void> clearStarted = Completer<void>();
  final Completer<void> releaseClear = Completer<void>();
  final Completer<void> clearFinished = Completer<void>();

  @override
  Future<void> writeText(String value) async => this.value = value;

  @override
  Future<String?> readText() async => value;

  @override
  Future<void> clearText() async {
    if (!clearStarted.isCompleted) clearStarted.complete();
    await releaseClear.future;
    value = '';
    if (!clearFinished.isCompleted) clearFinished.complete();
  }
}

final class SequenceRandomSource implements PasswordRandomSource {
  SequenceRandomSource(this._values);

  final List<int> _values;
  var _index = 0;

  @override
  int nextInt(int upperBound) {
    final int value = _values[_index % _values.length];
    _index++;
    return value % upperBound;
  }
}
