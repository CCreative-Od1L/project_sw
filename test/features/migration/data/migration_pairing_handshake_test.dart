import 'dart:typed_data';

import 'package:project_sw/features/migration/data/migration_pairing_handshake.dart';
import 'package:project_sw/features/migration/data/migration_socket_transport.dart';
import 'package:project_sw/features/migration/domain/migration_message_codec.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:project_sw/features/migration/domain/migration_session.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  test('binds both session directions to the QR sender public key', () async {
    final MigrationSocketServer server = await MigrationSocketServer.bind(
      '127.0.0.1',
      0,
    );
    final Future<MigrationSocketTransport> accepted = server.accept();
    final MigrationSocketTransport senderTransport =
        await MigrationSocketTransport.connect('127.0.0.1', server.port);
    final MigrationSocketTransport receiverTransport = await accepted;
    final FakeCryptoService crypto = FakeCryptoService();
    final identity = crypto.generateEphemeralKeyPair();
    final Uint8List qrSenderPublicKey = Uint8List.fromList(identity.publicKey);

    try {
      final Future<MigrationSession> receiverFuture =
          MigrationPairingHandshake.establishReceiver(
            transport: receiverTransport,
            crypto: crypto,
            senderPublicKey: qrSenderPublicKey,
          );
      final MigrationSession sender =
          await MigrationPairingHandshake.establishSender(
            transport: senderTransport,
            crypto: crypto,
            senderIdentity: identity,
          );
      final MigrationSession receiver = await receiverFuture;
      final MigrationSessionFrame frame = sender.seal(
        MigrationMessageType.preflight,
        MigrationPreflightCodec.encode(
          MigrationCapabilities(
            formatVersion: 1,
            aeadAlgorithmId: 1,
            supportedPlaintextFormatIds: <int>[1],
          ),
        ),
      );
      await senderTransport.send(frame);
      final Uint8List encoded = receiver.open(
        await receiverTransport.receive(),
      );
      expect(MigrationPreflightCodec.decode(encoded).formatVersion, 1);
      encoded.fillRange(0, encoded.length, 0);
      frame.dispose();
      sender.dispose();
      receiver.dispose();
    } finally {
      qrSenderPublicKey.fillRange(0, qrSenderPublicKey.length, 0);
      await senderTransport.close();
      await receiverTransport.close();
      await server.close();
    }
  });

  test(
    'rejects a malformed QR sender public key before key generation',
    () async {
      final MigrationSocketServer server = await MigrationSocketServer.bind(
        '127.0.0.1',
        0,
      );
      final MigrationSocketTransport client =
          await MigrationSocketTransport.connect('127.0.0.1', server.port);
      final MigrationSocketTransport peer = await server.accept();
      final FakeCryptoService crypto = FakeCryptoService();
      try {
        expect(
          MigrationPairingHandshake.establishReceiver(
            transport: peer,
            crypto: crypto,
            senderPublicKey: Uint8List(31),
          ),
          throwsA(isA<MigrationTransportException>()),
        );
      } finally {
        await client.close();
        await peer.close();
        await server.close();
      }
    },
  );
}
