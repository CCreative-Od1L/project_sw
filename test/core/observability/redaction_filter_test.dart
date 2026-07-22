import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/observability/logger.dart';
import 'package:project_sw/core/observability/redaction_filter.dart';

void main() {
  test('redaction filter masks sensitive keys case-insensitively', () {
    const RedactionFilter filter = RedactionFilter();

    final Map<String, dynamic> redacted = filter.redact(<String, dynamic>{
      'password': 'plain-text',
      'Master_Key': 'key-material',
      'entryCiphertext': 'ciphertext',
      'entryId': 'safe-id',
    });

    expect(redacted['password'], '[REDACTED]');
    expect(redacted['Master_Key'], '[REDACTED]');
    expect(redacted['entryCiphertext'], '[REDACTED]');
    expect(redacted['entryId'], 'safe-id');
  });

  test('logger applies redaction before writing to its sink', () {
    final RecordingLogSink sink = RecordingLogSink();
    final RedactingLogger logger = RedactingLogger(
      sink,
      const RedactionFilter(),
    );

    logger.info(
      'auth',
      'Unlock failed.',
      context: <String, dynamic>{'master_password': 'not-safe', 'attempt': 1},
    );

    expect(sink.entries, hasLength(1));
    expect(sink.entries.single.context['master_password'], '[REDACTED]');
    expect(sink.entries.single.context['attempt'], 1);
  });
}

final class RecordingLogSink implements LogSink {
  final List<LogEntry> entries = <LogEntry>[];

  @override
  void write(LogEntry entry) {
    entries.add(entry);
  }
}
