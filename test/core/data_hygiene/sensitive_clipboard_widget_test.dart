import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_feedback.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('copy action uses the shared cleanup path without showing text', (
    WidgetTester tester,
  ) async {
    final FakeClipboard clipboard = FakeClipboard();
    final SensitiveClipboardController controller =
        SensitiveClipboardController(
          clipboard,
          timerFactory: (_, void Function() callback) => NoopTimer(),
        );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SensitiveCopyButton(
            value: 'widget-only-secret',
            controller: controller,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Copy sensitive value'));
    await tester.pump();
    await tester.pump();

    expect(clipboard.value, 'widget-only-secret');
    expect(find.text('widget-only-secret'), findsNothing);
    expect(find.text('Password copied to clipboard'), findsOneWidget);
  });

  testWidgets(
    'copy shows one confirmation and expires without a cleanup snackbar',
    (WidgetTester tester) async {
      final FakeClipboard clipboard = FakeClipboard();
      final MutableClock clock = MutableClock();
      final ManualTimerFactory timers = ManualTimerFactory();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(
            clipboard,
            clock: clock.now,
            timerFactory: timers.create,
          );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SensitiveCopyButton(
              value: 'widget-only-secret',
              controller: controller,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Copy sensitive value'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Password copied to clipboard'), findsOneWidget);
      expect(find.textContaining('clears in'), findsNothing);

      clock.advance(const Duration(seconds: 20));
      timers.fireLatest();
      await tester.pump();
      await tester.pump();

      expect(clipboard.value, isEmpty);
      expect(clipboard.clearCount, 1);
      expect(find.text('Password copied to clipboard'), findsOneWidget);
      expect(find.text('Clipboard cleared'), findsNothing);
    },
  );

  testWidgets('copy failure does not show a false confirmation', (
    WidgetTester tester,
  ) async {
    final SensitiveClipboardController controller =
        SensitiveClipboardController(FailingClipboard());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SensitiveCopyButton(
            value: 'widget-only-secret',
            controller: controller,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Copy sensitive value'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Password copied to clipboard'), findsNothing);
  });
}

final class FailingClipboard implements ClipboardPort {
  @override
  Future<void> writeText(String value) async => throw StateError('unavailable');

  @override
  Future<String?> readText() async => null;

  @override
  Future<void> clearText() async {}
}

final class FakeClipboard implements ClipboardPort {
  String value = '';
  var clearCount = 0;

  @override
  Future<void> writeText(String value) async => this.value = value;

  @override
  Future<String?> readText() async => value;

  @override
  Future<void> clearText() async {
    value = '';
    clearCount++;
  }
}

final class NoopTimer implements SensitiveClipboardTimer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;
}

final class MutableClock {
  DateTime value = DateTime.utc(2026, 1, 1);

  DateTime now() => value;

  void advance(Duration duration) => value = value.add(duration);
}

final class ManualTimerFactory {
  final List<ManualTimer> timers = <ManualTimer>[];

  SensitiveClipboardTimer create(Duration _, void Function() callback) {
    final ManualTimer timer = ManualTimer(callback);
    timers.add(timer);
    return timer;
  }

  void fireLatest() => timers.last.fire();
}

final class ManualTimer implements SensitiveClipboardTimer {
  ManualTimer(this._callback);

  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}
