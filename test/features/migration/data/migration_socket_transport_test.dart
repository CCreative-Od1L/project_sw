import 'dart:typed_data';

import 'package:project_sw/features/migration/data/migration_socket_transport.dart';
import 'package:project_sw/features/migration/domain/migration_session.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  test(
    'round-trips bidirectional authenticated frames over loopback TCP',
    () async {
      final MigrationSocketServer server = await MigrationSocketServer.bind(
        '127.0.0.1',
        0,
      );
      final Future<MigrationSocketTransport> accepted = server.accept();
      final MigrationSocketTransport client =
          await MigrationSocketTransport.connect('127.0.0.1', server.port);
      final MigrationSocketTransport peer = await accepted;
      final FakeCryptoService crypto = FakeCryptoService();
      final identity = crypto.generateEphemeralKeyPair();
      final peerIdentity = crypto.generateEphemeralKeyPair();
      final Uint8List identityPublicKey = Uint8List.fromList(
        identity.publicKey,
      );
      final Uint8List peerPublicKey = Uint8List.fromList(
        peerIdentity.publicKey,
      );
      final MigrationSession sender = MigrationSession.establishClient(
        crypto: crypto,
        localIdentity: identity,
        remotePublicKey: peerPublicKey,
      );
      final MigrationSession receiver = MigrationSession.establishServer(
        crypto: crypto,
        localIdentity: peerIdentity,
        remotePublicKey: identityPublicKey,
      );

      try {
        await client.send(
          sender.seal(
            MigrationMessageType.entry,
            Uint8List.fromList(<int>[1, 2, 3]),
          ),
        );
        final MigrationSessionFrame received = await peer.receive();
        expect(receiver.open(received), <int>[1, 2, 3]);

        await peer.send(
          receiver.seal(
            MigrationMessageType.preflight,
            Uint8List.fromList(<int>[4, 5]),
          ),
        );
        final MigrationSessionFrame response = await client.receive();
        expect(sender.open(response), <int>[4, 5]);

        await client.send(sender.sealTransferEnd());
        final Uint8List transcriptMac = receiver.openTransferEnd(
          await peer.receive(),
        );
        receiver.verifyTranscriptMac(transcriptMac);
        transcriptMac.fillRange(0, transcriptMac.length, 0);
      } finally {
        sender.dispose();
        receiver.dispose();
        await client.close();
        await peer.close();
        await server.close();
      }
    },
  );

  test(
    'reports a peer disconnect instead of returning a partial frame',
    () async {
      final MigrationSocketServer server = await MigrationSocketServer.bind(
        '127.0.0.1',
        0,
      );
      final Future<MigrationSocketTransport> accepted = server.accept();
      final MigrationSocketTransport client =
          await MigrationSocketTransport.connect('127.0.0.1', server.port);
      final MigrationSocketTransport peer = await accepted;
      await client.close();

      expect(peer.receive(), throwsA(isA<MigrationTransportException>()));
      await peer.close();
      await server.close();
    },
  );
}
