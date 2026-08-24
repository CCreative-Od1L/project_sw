import 'dart:async';

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

  test(
    'session lock clears tracked state and its owned clipboard value',
    () async {
      final FakeClipboard clipboard = FakeClipboard();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(clipboard);
      addTearDown(controller.dispose);

      await controller.copySensitive('secret');
      final Future<void> cleanup = controller.clearForSessionLock();

      expect(controller.state.status, SensitiveClipboardStatus.idle);
      expect(controller.state.isActive, isFalse);

      await cleanup;
      expect(clipboard.value, isEmpty);
      expect(clipboard.clearCount, 1);
    },
  );

  test(
    'session lock preserves clipboard content replaced by another app',
    () async {
      final FakeClipboard clipboard = FakeClipboard();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(clipboard);
      addTearDown(controller.dispose);

      await controller.copySensitive('secret');
      clipboard.value = 'newer content';

      await controller.clearForSessionLock();

      expect(clipboard.value, 'newer content');
      expect(clipboard.clearCount, 0);
      expect(controller.state.status, SensitiveClipboardStatus.idle);
    },
  );

  test(
    'session lock invalidates a sensitive copy whose write is in flight',
    () async {
      final BlockingClipboard clipboard = BlockingClipboard();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(clipboard);
      addTearDown(controller.dispose);

      final Future<void> copy = controller.copySensitive('secret');
      await clipboard.writeStarted.future;

      final Future<void> cleanup = controller.clearForSessionLock();
      clipboard.releaseWrite.complete();
      await Future.wait(<Future<void>>[copy, cleanup]);

      expect(clipboard.value, isEmpty);
      expect(clipboard.clearCount, 1);
      expect(controller.state.status, SensitiveClipboardStatus.idle);
    },
  );

  test(
    'a copy started after session lock is not cleared by stale cleanup',
    () async {
      final FakeClipboard clipboard = FakeClipboard();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(clipboard);
      addTearDown(controller.dispose);

      await controller.copySensitive('old secret');
      final Future<void> cleanup = controller.clearForSessionLock();
      final Future<void> newCopy = controller.copySensitive('new secret');
      await Future.wait(<Future<void>>[cleanup, newCopy]);

      expect(clipboard.value, 'new secret');
      expect(controller.state.status, SensitiveClipboardStatus.active);
    },
  );

  test(
    'a queued copy is discarded before writing after session lock',
    () async {
      final BlockingClipboard clipboard = BlockingClipboard();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(clipboard);
      addTearDown(controller.dispose);

      final Future<void> firstCopy = controller.copySensitive('first secret');
      await clipboard.writeStarted.future;
      final Future<void> queuedCopy = controller.copySensitive('queued secret');
      final Future<void> cleanup = controller.clearForSessionLock();

      clipboard.releaseWrite.complete();
      await Future.wait(<Future<void>>[firstCopy, queuedCopy, cleanup]);

      expect(clipboard.writes, <String>['first secret']);
      expect(clipboard.value, isEmpty);
      expect(controller.state.status, SensitiveClipboardStatus.idle);
    },
  );

  test(
    'dispose discards a queued copy before it reaches the platform',
    () async {
      final FakeClipboard clipboard = FakeClipboard();
      final SensitiveClipboardController controller =
          SensitiveClipboardController(clipboard);

      final Future<void> copy = controller.copySensitive('secret');
      controller.dispose();
      await copy;

      expect(clipboard.writeCount, 0);
      expect(clipboard.value, isEmpty);
    },
  );
}

final class FakeClipboard implements ClipboardPort {
  String value = '';
  var clearCount = 0;
  var writeCount = 0;

  @override
  Future<void> writeText(String value) async {
    writeCount++;
    this.value = value;
  }

  @override
  Future<String?> readText() async => value;

  @override
  Future<void> clearText() async {
    value = '';
    clearCount++;
  }
}

final class BlockingClipboard extends FakeClipboard {
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();
  final List<String> writes = <String>[];

  @override
  Future<void> writeText(String value) async {
    writes.add(value);
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    await super.writeText(value);
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
