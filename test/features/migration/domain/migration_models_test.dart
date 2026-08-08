import 'dart:typed_data';

import 'package:project_sw/features/migration/domain/migration_exception.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:test/test.dart';

void main() {
  group('MigrationPairingPayload', () {
    test('round-trips only public pairing data', () {
      final DateTime issuedAt = DateTime.utc(2026, 8, 8, 12);
      final Uint8List publicKey = Uint8List.fromList(
        List<int>.generate(32, (int index) => index),
      );
      final MigrationPairingPayload payload = MigrationPairingPayload.issue(
        host: '192.168.1.20',
        port: 43123,
        senderPublicKey: publicKey,
        issuedAt: issuedAt,
      );

      final MigrationPairingPayload decoded = MigrationPairingPayload.decode(
        payload.encode(),
        now: issuedAt.add(const Duration(seconds: 1)),
      );

      expect(decoded.host, payload.host);
      expect(decoded.port, payload.port);
      expect(decoded.senderPublicKey, publicKey);
      expect(decoded.isExpired(issuedAt), isFalse);
    });

    test('rejects expired payloads before connection setup', () {
      final MigrationPairingPayload payload = MigrationPairingPayload.issue(
        host: '192.168.1.20',
        port: 43123,
        senderPublicKey: Uint8List(32),
        issuedAt: DateTime.utc(2026, 8, 8, 12),
        ttl: const Duration(seconds: 10),
      );

      expect(
        () => MigrationPairingPayload.decode(
          payload.encode(),
          now: DateTime.utc(2026, 8, 8, 12, 0, 11),
        ),
        throwsA(
          isA<MigrationProtocolException>().having(
            (MigrationProtocolException error) => error.code,
            'code',
            MigrationErrorCode.expired,
          ),
        ),
      );
    });

    test('rejects malformed role, address, and public key', () {
      expect(
        () => MigrationPairingPayload(
          host: 'not a host',
          port: 43123,
          senderPublicKey: Uint8List(32),
          issuedAtEpochSeconds: 1,
          expiresAtEpochSeconds: 2,
        ),
        throwsA(isA<MigrationProtocolException>()),
      );
      expect(
        () => MigrationPairingPayload(
          host: '192.168.1.20',
          port: 43123,
          senderPublicKey: Uint8List(31),
          issuedAtEpochSeconds: 1,
          expiresAtEpochSeconds: 2,
        ),
        throwsA(isA<MigrationProtocolException>()),
      );
    });
  });

  group('MigrationCapabilities', () {
    test('selects a shared plaintext format', () {
      final MigrationCapabilities sender = MigrationCapabilities(
        formatVersion: 1,
        aeadAlgorithmId: 1,
        supportedPlaintextFormatIds: <int>[2, 1],
      );
      final MigrationCapabilities receiver = MigrationCapabilities(
        formatVersion: 1,
        aeadAlgorithmId: 1,
        supportedPlaintextFormatIds: <int>[3, 2],
      );

      expect(sender.negotiateWith(receiver), 2);
      expect(sender.supportedPlaintextFormatIds, <int>[1, 2]);
    });

    test('rejects format and algorithm mismatches', () {
      final MigrationCapabilities sender = MigrationCapabilities(
        formatVersion: 1,
        aeadAlgorithmId: 1,
        supportedPlaintextFormatIds: <int>[1],
      );

      expect(
        () => sender.negotiateWith(
          MigrationCapabilities(
            formatVersion: 2,
            aeadAlgorithmId: 1,
            supportedPlaintextFormatIds: <int>[1],
          ),
        ),
        throwsA(isA<MigrationProtocolException>()),
      );
      expect(
        () => sender.negotiateWith(
          MigrationCapabilities(
            formatVersion: 1,
            aeadAlgorithmId: 2,
            supportedPlaintextFormatIds: <int>[1],
          ),
        ),
        throwsA(isA<MigrationProtocolException>()),
      );
    });
  });
}
