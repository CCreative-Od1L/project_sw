import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/features/migration/domain/migration_exception.dart';
import 'package:project_sw/features/migration/domain/migration_message_codec.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips the authenticated preflight payload', () {
    final MigrationCapabilities capabilities = MigrationCapabilities(
      formatVersion: 1,
      aeadAlgorithmId: 1,
      supportedPlaintextFormatIds: <int>[1, 2],
    );

    final MigrationCapabilities decoded = MigrationPreflightCodec.decode(
      MigrationPreflightCodec.encode(capabilities),
    );

    expect(decoded.formatVersion, 1);
    expect(decoded.aeadAlgorithmId, 1);
    expect(decoded.supportedPlaintextFormatIds, <int>[1, 2]);
  });

  test('round-trips an entry payload and copies sensitive buffers', () {
    final MigrationEntryPayload payload = MigrationEntryPayload(
      entryId: Uint8List.fromList(List<int>.filled(16, 1)),
      sequence: 7,
      plaintextFormatId: 1,
      entryCiphertext: Uint8List.fromList(List<int>.filled(40, 2)),
      dek: Uint8List.fromList(List<int>.filled(32, 3)),
    );
    final Uint8List encoded = MigrationEntryPayloadCodec.encode(payload);
    payload.dispose();

    final MigrationEntryPayload decoded = MigrationEntryPayloadCodec.decode(
      encoded,
    );
    expect(decoded.entryId, List<int>.filled(16, 1));
    expect(decoded.sequence, 7);
    expect(decoded.entryCiphertext, List<int>.filled(40, 2));
    expect(decoded.dek, List<int>.filled(32, 3));
    decoded.dispose();
    clearSensitiveBytes(encoded);
  });

  test('rejects malformed entry and transcript payloads', () {
    expect(
      () => MigrationEntryPayloadCodec.decode(Uint8List(100)),
      throwsA(isA<MigrationProtocolException>()),
    );
    expect(
      () => MigrationTransferEndCodec.decode(Uint8List(31)),
      throwsA(
        isA<MigrationProtocolException>().having(
          (MigrationProtocolException error) => error.code,
          'code',
          MigrationErrorCode.transcriptMismatch,
        ),
      ),
    );
  });
}
