import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';

void main() {
  test('clears its own copied value at the deadline', () async {
    final FakeClipboard clipboard = FakeClipboard();
    final MutableClock clock = MutableClock();
    final SensitiveClipboardController controller =
        SensitiveClipboardController(
          clipboard,
          timeout: const Duration(seconds: 20),
          clock: clock.now,
          timerFactory: (_, void Function() callback) => FakeTimer(callback),
        );
    addTearDown(controller.dispose);

    await controller.copySensitive('secret');
    clock.advance(const Duration(seconds: 20));
    await controller.onForegrounded();

    expect(clipboard.value, isEmpty);
    expect(clipboard.clearCount, 1);
    expect(controller.state.status, SensitiveClipboardStatus.cleared);
  });

  test('does not clear clipboard content replaced by another app', () async {
    final FakeClipboard clipboard = FakeClipboard();
    final MutableClock clock = MutableClock();
    final SensitiveClipboardController controller =
        SensitiveClipboardController(
          clipboard,
          clock: clock.now,
          timerFactory: (_, void Function() callback) => FakeTimer(callback),
        );
    addTearDown(controller.dispose);

    await controller.copySensitive('secret');
    clipboard.value = 'newer content';
    clock.advance(const Duration(seconds: 20));
    await controller.onForegrounded();

    expect(clipboard.value, 'newer content');
    expect(clipboard.clearCount, 0);
    expect(
      controller.state.status,
      SensitiveClipboardStatus.preservedReplacement,
    );
  });

  test(
    'a later sensitive copy supersedes the earlier cleanup deadline',
    () async {
      final FakeClipboard clipboard = FakeClipboard();
      final MutableClock clock = MutableClock();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(
            clipboard,
            clock: clock.now,
            timerFactory: (_, void Function() callback) => FakeTimer(callback),
          );
      addTearDown(controller.dispose);

      await controller.copySensitive('first');
      clock.advance(const Duration(seconds: 10));
      await controller.copySensitive('second');
      clock.advance(const Duration(seconds: 10));
      await controller.onForegrounded();

      expect(clipboard.value, 'second');
      expect(clipboard.clearCount, 0);
      expect(controller.state.status, SensitiveClipboardStatus.active);

      clock.advance(const Duration(seconds: 10));
      await controller.onForegrounded();
      expect(clipboard.clearCount, 1);
      expect(controller.state.status, SensitiveClipboardStatus.cleared);
    },
  );

  test(
    'foreground catch-up cleans an expired copy after timers were suspended',
    () async {
      final FakeClipboard clipboard = FakeClipboard();
      final MutableClock clock = MutableClock();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(
            clipboard,
            clock: clock.now,
            timerFactory: (_, void Function() callback) => FakeTimer(callback),
          );
      addTearDown(controller.dispose);

      await controller.copySensitive('secret');
      clock.advance(const Duration(seconds: 21));
      await controller.onForegrounded();

      expect(clipboard.clearCount, 1);
      expect(controller.state.status, SensitiveClipboardStatus.cleared);
    },
  );
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

final class MutableClock {
  DateTime value = DateTime.utc(2026, 1, 1);

  DateTime now() => value;

  void advance(Duration duration) => value = value.add(duration);
}

final class FakeTimer implements SensitiveClipboardTimer {
  FakeTimer(this._callback);

  final void Function() _callback;
  var _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  void cancel() => _isActive = false;

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _callback();
  }
}
