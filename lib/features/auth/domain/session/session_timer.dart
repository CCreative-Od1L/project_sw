import 'dart:async';

/// A timer handle owned by [SessionController].
abstract interface class SessionTimer {
  /// Whether the timer can still invoke its callback.
  bool get isActive;

  /// Cancels the timer and makes its callback inert.
  void cancel();
}

/// Factory used by [SessionController] so timer transitions can be controlled
/// in unit tests without waiting five minutes.
typedef SessionTimerFactory =
    SessionTimer Function(Duration duration, void Function() callback);

/// The production timer backed by Dart's event loop.
final class DartSessionTimer implements SessionTimer {
  /// Creates a one-shot timer for [duration].
  DartSessionTimer(Duration duration, void Function() callback)
    : _timer = Timer(duration, callback);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}

/// Creates the production session timer.
SessionTimer createDartSessionTimer(
  Duration duration,
  void Function() callback,
) => DartSessionTimer(duration, callback);
