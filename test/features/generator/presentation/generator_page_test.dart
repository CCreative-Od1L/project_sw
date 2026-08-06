import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';
import 'package:project_sw/app/pages/generator_page.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('generates a password and displays theoretical entropy', (
    WidgetTester tester,
  ) async {
    final SensitiveClipboardController clipboard = SensitiveClipboardController(
      FakeClipboard(),
    );
    addTearDown(clipboard.dispose);

    await tester.pumpWidget(
      _localizedApp(
        PasswordGeneratorPanel(
          generatePassword: GeneratePassword(
            SequenceRandomSource(List<int>.filled(20, 0)),
          ),
          randomSource: SequenceRandomSource(const <int>[0]),
          sensitiveClipboardController: clipboard,
        ),
      ),
    );

    await tester.tap(find.text('Generate'));
    await tester.pump();

    expect(find.text('aaaaaaaaaaaaaaaaaaaa'), findsOneWidget);
    expect(find.textContaining('Theoretical entropy:'), findsOneWidget);
    expect(find.text('Very strong'), findsOneWidget);
  });

  testWidgets('generated output can be inserted into an entry form', (
    WidgetTester tester,
  ) async {
    final SensitiveClipboardController clipboard = SensitiveClipboardController(
      FakeClipboard(),
    );
    String? inserted;
    addTearDown(clipboard.dispose);

    await tester.pumpWidget(
      _localizedApp(
        PasswordGeneratorPanel(
          generatePassword: GeneratePassword(
            SequenceRandomSource(List<int>.filled(20, 0)),
          ),
          randomSource: SequenceRandomSource(const <int>[0]),
          sensitiveClipboardController: clipboard,
          onGenerated: (String value) => inserted = value,
        ),
      ),
    );

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.text('Use in entry'));

    expect(inserted, 'aaaaaaaaaaaaaaaaaaaa');
  });

  testWidgets('generated output is cleared when the session locks', (
    WidgetTester tester,
  ) async {
    final SensitiveClipboardController clipboard = SensitiveClipboardController(
      FakeClipboard(),
    );
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    addTearDown(clipboard.dispose);
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      _localizedApp(
        PasswordGeneratorPanel(
          generatePassword: GeneratePassword(
            SequenceRandomSource(List<int>.filled(20, 0)),
          ),
          randomSource: SequenceRandomSource(const <int>[0]),
          sensitiveClipboardController: clipboard,
          sessionController: sessionController,
        ),
      ),
    );

    await tester.tap(find.text('Generate'));
    await tester.pump();
    expect(find.text('aaaaaaaaaaaaaaaaaaaa'), findsOneWidget);

    sessionController.lock(LockReason.backgroundOrTimeout);
    await tester.pump();

    expect(find.text('aaaaaaaaaaaaaaaaaaaa'), findsNothing);
  });
}

Widget _localizedApp(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

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

final class FakeClipboard implements ClipboardPort {
  @override
  Future<void> writeText(String value) async {}

  @override
  Future<String?> readText() async => null;

  @override
  Future<void> clearText() async {}
}
