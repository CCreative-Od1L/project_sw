import 'dart:typed_data';

import 'migration_socket_transport.dart';
import '../domain/migration_session.dart';

import 'package:project_sw/core/crypto/crypto_service.dart';

/// Establishes a one-time crypto_kx session after QR pairing confirmation.
abstract final class MigrationPairingHandshake {
  /// Sender side: receives the peer's ephemeral public key and derives keys.
  static Future<MigrationSession> establishSender({
    required MigrationSocketTransport transport,
    required CryptoService crypto,
    required EphemeralKeyPair senderIdentity,
  }) async {
    final Uint8List receiverPublicKey = await transport.receivePublicKey();
    try {
      return MigrationSession.establishClient(
        crypto: crypto,
        localIdentity: senderIdentity,
        remotePublicKey: receiverPublicKey,
      );
    } finally {
      receiverPublicKey.fillRange(0, receiverPublicKey.length, 0);
    }
  }

  /// Receiver side: sends a fresh ephemeral key and binds the QR public key.
  static Future<MigrationSession> establishReceiver({
    required MigrationSocketTransport transport,
    required CryptoService crypto,
    required Uint8List senderPublicKey,
  }) async {
    if (senderPublicKey.length != 32) {
      throw const MigrationTransportException(
        'The paired sender public key has an invalid length.',
      );
    }
    final EphemeralKeyPair receiverIdentity = crypto.generateEphemeralKeyPair();
    try {
      await transport.sendPublicKey(receiverIdentity.publicKey);
      return MigrationSession.establishServer(
        crypto: crypto,
        localIdentity: receiverIdentity,
        remotePublicKey: senderPublicKey,
      );
    } catch (_) {
      receiverIdentity.dispose();
      rethrow;
    }
  }
}
