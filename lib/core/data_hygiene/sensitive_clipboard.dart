import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform boundary for clipboard operations.
abstract interface class ClipboardPort {
  /// Writes [value] to the platform clipboard.
  Future<void> writeText(String value);

  /// Reads plain text from the platform clipboard.
  Future<String?> readText();

  /// Replaces the current clipboard value with an empty value.
  Future<void> clearText();
}

/// Flutter implementation of [ClipboardPort].
final class FlutterClipboardPort implements ClipboardPort {
  /// Creates the production clipboard adapter.
  const FlutterClipboardPort();

  @override
  Future<void> writeText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  @override
  Future<String?> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Future<void> clearText() async {
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}

/// A controllable timer boundary for sensitive clipboard expiry.
abstract interface class SensitiveClipboardTimer {
  /// Whether the timer can still invoke its callback.
  bool get isActive;

  /// Cancels the timer.
  void cancel();
}

/// Factory used to test expiry without waiting in real time.
typedef SensitiveClipboardTimerFactory =
    SensitiveClipboardTimer Function(
      Duration duration,
      void Function() callback,
    );

/// Production one-shot timer for clipboard countdown updates.
final class DartSensitiveClipboardTimer implements SensitiveClipboardTimer {
  /// Creates a timer for [duration].
  DartSensitiveClipboardTimer(Duration duration, void Function() callback)
    : _timer = Timer(duration, callback);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}

/// Creates the production clipboard timer.
SensitiveClipboardTimer createDartSensitiveClipboardTimer(
  Duration duration,
  void Function() callback,
) => DartSensitiveClipboardTimer(duration, callback);

/// The only status information exposed to UI state.
enum SensitiveClipboardStatus {
  /// No sensitive copy is currently tracked.
  idle,

  /// The app owns a clipboard value that has not expired.
  active,

  /// The app cleared its own clipboard value at expiry.
  cleared,

  /// The clipboard was replaced, so the newer value was preserved.
  preservedReplacement,
}

/// Non-sensitive state for copy feedback and countdown rendering.
final class SensitiveClipboardState {
  /// Creates a clipboard state without retaining clipboard text.
  const SensitiveClipboardState({
    required this.status,
    this.remaining = Duration.zero,
  });

  /// Creates the initial idle state.
  const SensitiveClipboardState.idle()
    : status = SensitiveClipboardStatus.idle,
      remaining = Duration.zero;

  /// Current lifecycle status.
  final SensitiveClipboardStatus status;

  /// Approximate time remaining for an active copy.
  final Duration remaining;

  /// Whether the UI should display an active countdown.
  bool get isActive => status == SensitiveClipboardStatus.active;
}

/// Owns sensitive clipboard timing, replacement protection, and foreground
/// catch-up without exposing copied plaintext in view state.
final class SensitiveClipboardController extends ChangeNotifier {
  /// Creates a controller with injectable platform, time, and timer seams.
  SensitiveClipboardController(
    this._clipboard, {
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
    this.timerFactory = createDartSensitiveClipboardTimer,
  }) : _clock = clock ?? DateTime.now;

  final ClipboardPort _clipboard;
  final DateTime Function() _clock;

  /// Timer implementation used for countdown and expiry.
  final SensitiveClipboardTimerFactory timerFactory;
  SensitiveClipboardTimer? _timer;
  String? _lastCopiedValue;
  DateTime? _expiresAt;
  var _generation = 0;
  SensitiveClipboardState _state = const SensitiveClipboardState.idle();

  /// Fixed sensitive-copy lifetime for the current app version.
  final Duration timeout;

  /// Non-sensitive state used by copy feedback widgets.
  SensitiveClipboardState get state => _state;

  /// Copies a password or secret custom field and starts its cleanup window.
  Future<void> copySensitive(String value) async {
    _cancelTimer();
    final int generation = ++_generation;
    await _clipboard.writeText(value);
    _lastCopiedValue = value;
    _expiresAt = _clock().add(timeout);
    _publish(
      SensitiveClipboardState(
        status: SensitiveClipboardStatus.active,
        remaining: timeout,
      ),
    );
    _scheduleNext(generation);
  }

  /// Applies an expiry immediately when the app returns from suspension.
  Future<void> onForegrounded() async {
    if (_expiresAt == null) return;
    await _refresh(generation: _generation);
  }

  @override
  void dispose() {
    _cancelTimer();
    _lastCopiedValue = null;
    _expiresAt = null;
    super.dispose();
  }

  void _scheduleNext(int generation) {
    final DateTime? expiresAt = _expiresAt;
    if (expiresAt == null || generation != _generation) return;
    final Duration remaining = expiresAt.difference(_clock());
    if (remaining <= Duration.zero) {
      unawaited(_refresh(generation: generation));
      return;
    }
    final Duration tick = remaining < const Duration(seconds: 1)
        ? remaining
        : const Duration(seconds: 1);
    _timer = timerFactory(tick, () {
      unawaited(_refresh(generation: generation));
    });
  }

  Future<void> _refresh({required int generation}) async {
    if (generation != _generation) return;
    final DateTime? expiresAt = _expiresAt;
    final String? copiedValue = _lastCopiedValue;
    if (expiresAt == null || copiedValue == null) return;
    final Duration remaining = expiresAt.difference(_clock());
    if (remaining > Duration.zero) {
      _cancelTimer();
      _publish(
        SensitiveClipboardState(
          status: SensitiveClipboardStatus.active,
          remaining: remaining,
        ),
      );
      _scheduleNext(generation);
      return;
    }

    _cancelTimer();
    final String? currentValue = await _clipboard.readText();
    if (generation != _generation) return;
    final bool ownsClipboard = currentValue == copiedValue;
    if (ownsClipboard) await _clipboard.clearText();
    _lastCopiedValue = null;
    _expiresAt = null;
    _publish(
      SensitiveClipboardState(
        status: ownsClipboard
            ? SensitiveClipboardStatus.cleared
            : SensitiveClipboardStatus.preservedReplacement,
      ),
    );
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _publish(SensitiveClipboardState state) {
    _state = state;
    notifyListeners();
  }
}
