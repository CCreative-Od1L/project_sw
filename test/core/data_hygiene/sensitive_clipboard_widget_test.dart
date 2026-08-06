import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_feedback.dart';

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
        home: Scaffold(
          body: SensitiveClipboardFeedback(
            controller: controller,
            child: SensitiveCopyButton(
              value: 'widget-only-secret',
              controller: controller,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Copy sensitive value'));
    await tester.pump();
    await tester.pump();

    expect(clipboard.value, 'widget-only-secret');
    expect(find.text('widget-only-secret'), findsNothing);
    expect(find.textContaining('Sensitive value copied'), findsOneWidget);
  });
}

final class FakeClipboard implements ClipboardPort {
  String value = '';

  @override
  Future<void> writeText(String value) async => this.value = value;

  @override
  Future<String?> readText() async => value;

  @override
  Future<void> clearText() async => value = '';
}

final class NoopTimer implements SensitiveClipboardTimer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;
}
