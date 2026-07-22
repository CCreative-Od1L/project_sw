import 'dart:developer' as developer;

import 'package:project_sw/core/observability/redaction_filter.dart';

/// Severity levels supported by the project logging pipeline.
enum LogLevel {
  /// Detailed diagnostics intended for development investigation.
  verbose,

  /// A normal product lifecycle event.
  info,

  /// A recoverable condition requiring attention.
  warning,

  /// A system fault that requires diagnosis.
  error,
}

/// Structured logging interface used outside the logging implementation.
abstract interface class Logger {
  /// Records a verbose diagnostic event.
  void verbose(String tag, String message, {Map<String, dynamic>? context});

  /// Records an informational event.
  void info(String tag, String message, {Map<String, dynamic>? context});

  /// Records a warning event.
  void warning(String tag, String message, {Map<String, dynamic>? context});

  /// Records a system fault and its optional diagnostic details.
  void error(
    String tag,
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  });
}

/// Local-only event tracking interface.
abstract interface class EventTracker {
  /// Records a non-sensitive product event.
  void track(String event, {Map<String, dynamic>? params});
}

/// Local-only metrics recording interface.
abstract interface class MetricsRecorder {
  /// Records an operation duration.
  void recordTiming(String name, Duration duration);

  /// Increments a non-sensitive counter.
  void recordCounter(String name, {int increment = 1});
}

/// A fully redacted log record sent to a [LogSink].
final class LogEntry {
  /// Creates a log entry.
  const LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    required this.context,
    this.error,
    this.stackTrace,
  });

  /// The event severity.
  final LogLevel level;

  /// The emitting module identifier.
  final String tag;

  /// A caller-owned message that must not interpolate secrets.
  final String message;

  /// Structured context after redaction.
  final Map<String, dynamic> context;

  /// A normalized system fault, if present.
  final Object? error;

  /// A system fault stack trace, if present.
  final StackTrace? stackTrace;
}

/// Receives redacted [LogEntry] values for a concrete destination.
abstract interface class LogSink {
  /// Writes one fully redacted log entry.
  void write(LogEntry entry);
}

/// Logger implementation that redacts context before every sink write.
final class RedactingLogger implements Logger {
  /// Creates a logger that always applies [redactionFilter] before [sink].
  const RedactingLogger(this._sink, this._redactionFilter);

  final LogSink _sink;
  final RedactionFilter _redactionFilter;

  @override
  void verbose(String tag, String message, {Map<String, dynamic>? context}) {
    _log(LogLevel.verbose, tag, message, context: context);
  }

  @override
  void info(String tag, String message, {Map<String, dynamic>? context}) {
    _log(LogLevel.info, tag, message, context: context);
  }

  @override
  void warning(String tag, String message, {Map<String, dynamic>? context}) {
    _log(LogLevel.warning, tag, message, context: context);
  }

  @override
  void error(
    String tag,
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.error,
      tag,
      message,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _log(
    LogLevel level,
    String tag,
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _sink.write(
      LogEntry(
        level: level,
        tag: tag,
        message: message,
        context: _redactionFilter.redact(context),
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

/// Development log sink backed by Dart's structured developer log API.
final class DeveloperLogSink implements LogSink {
  /// Creates the development log sink.
  const DeveloperLogSink();

  @override
  void write(LogEntry entry) {
    developer.log(
      '${entry.message} ${entry.context}',
      name: entry.tag,
      level: _levelFor(entry.level),
      error: entry.error,
      stackTrace: entry.stackTrace,
    );
  }

  int _levelFor(LogLevel level) {
    return switch (level) {
      LogLevel.verbose => 500,
      LogLevel.info => 800,
      LogLevel.warning => 900,
      LogLevel.error => 1000,
    };
  }
}

/// Event tracker used until a persistent local tracker is introduced.
final class NoopEventTracker implements EventTracker {
  /// Creates a no-op event tracker.
  const NoopEventTracker();

  @override
  void track(String event, {Map<String, dynamic>? params}) {}
}

/// Metrics recorder used until a persistent local recorder is introduced.
final class NoopMetricsRecorder implements MetricsRecorder {
  /// Creates a no-op metrics recorder.
  const NoopMetricsRecorder();

  @override
  void recordCounter(String name, {int increment = 1}) {}

  @override
  void recordTiming(String name, Duration duration) {}
}
