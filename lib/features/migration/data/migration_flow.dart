import 'dart:io';

import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:project_sw/features/migration/domain/migration_session.dart';
import 'package:project_sw/features/migration/data/migration_pairing_handshake.dart';
import 'package:project_sw/features/migration/data/migration_socket_transport.dart';
import 'package:project_sw/features/migration/data/migration_transfer_coordinator.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';

/// Resolves a non-loopback IPv4 address that another device can dial.
typedef MigrationHostResolver = Future<String> Function();

/// Finds the first usable local IPv4 address for a QR pairing payload.
Future<String> resolveMigrationHost() async {
  final List<NetworkInterface> interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  for (final NetworkInterface interface in interfaces) {
    for (final InternetAddress address in interface.addresses) {
      if (!address.isLoopback && !address.address.startsWith('169.254.')) {
        return address.address;
      }
    }
  }
  throw const MigrationTransportException(
    'No local network address is available for migration.',
  );
}

/// Public operations needed by the migration page.
abstract interface class MigrationFlow {
  /// Opens a one-time sender listener and returns the QR payload to display.
  Future<MigrationPairingPayload> prepareSender();

  /// Waits for the scanned receiver and transfers the unlocked vault.
  Future<void> runSender();

  /// Connects to the sender described by [payload] and imports the vault.
  Future<void> runReceiver(MigrationPairingPayload payload);

  /// Cancels listeners, transports, and temporary key material.
  Future<void> cancel();
}

/// Production LAN migration flow built on the authenticated protocol layers.
final class NetworkMigrationFlow implements MigrationFlow {
  /// Creates a flow for one unlocked session.
  NetworkMigrationFlow({
    required this.crypto,
    required this.vault,
    required this.sessionController,
    this.hostResolver = resolveMigrationHost,
  });

  /// Crypto service used for the one-time handshake.
  final CryptoService crypto;

  /// Unlocked vault port used by the transfer coordinator.
  final MigrationVaultPort vault;

  /// Global session source of truth used for idle-timeout suppression.
  final SessionController sessionController;

  /// Injectable address resolver used by tests and platform-specific hosts.
  final MigrationHostResolver hostResolver;

  /// Maximum time a sender listener and its QR payload remain valid.
  static const Duration pairingTtl = Duration(minutes: 5);

  /// Capabilities advertised by the current vault format implementation.
  static final MigrationCapabilities capabilities = MigrationCapabilities(
    formatVersion: 1,
    aeadAlgorithmId: 1,
    supportedPlaintextFormatIds: <int>[1],
  );

  MigrationSocketServer? _server;
  MigrationSocketTransport? _transport;
  EphemeralKeyPair? _senderIdentity;

  @override
  Future<MigrationPairingPayload> prepareSender() async {
    if (_server != null || _senderIdentity != null) {
      throw StateError('A migration flow is already active.');
    }
    MigrationSocketServer? server;
    EphemeralKeyPair? identity;
    try {
      identity = crypto.generateEphemeralKeyPair();
      server = await MigrationSocketServer.bind(
        InternetAddress.anyIPv4.address,
        0,
        timeout: pairingTtl,
      );
      final String host = await hostResolver();
      final MigrationPairingPayload payload = MigrationPairingPayload.issue(
        host: host,
        port: server.port,
        senderPublicKey: identity.publicKey,
        ttl: pairingTtl,
      );
      _server = server;
      _senderIdentity = identity;
      server = null;
      identity = null;
      return payload;
    } finally {
      identity?.dispose();
      await server?.close();
    }
  }

  @override
  Future<void> runSender() async {
    final MigrationSocketServer? server = _server;
    final EphemeralKeyPair? identity = _senderIdentity;
    if (server == null || identity == null) {
      throw StateError('The sender listener has not been prepared.');
    }
    MigrationSession? session;
    try {
      final MigrationSocketTransport transport = await server.accept();
      _transport = transport;
      try {
        session = await MigrationPairingHandshake.establishSender(
          transport: transport,
          crypto: crypto,
          senderIdentity: identity,
        );
        _senderIdentity = null;
        await _runTransfer(
          () => MigrationTransferCoordinator.send(
            transport: transport,
            session: session!,
            capabilities: capabilities,
            vault: vault,
          ),
        );
      } finally {
        session?.dispose();
        await transport.close();
        _transport = null;
      }
    } finally {
      await server.close();
      _server = null;
      _senderIdentity?.dispose();
      _senderIdentity = null;
    }
  }

  @override
  Future<void> runReceiver(MigrationPairingPayload payload) async {
    MigrationSocketTransport? transport;
    MigrationSession? session;
    try {
      transport = await MigrationSocketTransport.connect(
        payload.host,
        payload.port,
        timeout: pairingTtl,
      );
      _transport = transport;
      session = await MigrationPairingHandshake.establishReceiver(
        transport: transport,
        crypto: crypto,
        senderPublicKey: payload.senderPublicKey,
      );
      await _runTransfer(
        () => MigrationTransferCoordinator.receive(
          transport: transport!,
          session: session!,
          capabilities: capabilities,
          vault: vault,
        ),
      );
    } finally {
      session?.dispose();
      await transport?.close();
      _transport = null;
    }
  }

  Future<void> _runTransfer(Future<void> Function() transfer) async {
    sessionController.beginIdleTimeoutSuppression(
      LockSuppressionReason.migrationInProgress,
    );
    try {
      await transfer();
    } finally {
      sessionController.endIdleTimeoutSuppression(
        LockSuppressionReason.migrationInProgress,
      );
    }
  }

  @override
  Future<void> cancel() async {
    final MigrationSocketTransport? transport = _transport;
    _transport = null;
    await transport?.close();
    final MigrationSocketServer? server = _server;
    _server = null;
    await server?.close();
    _senderIdentity?.dispose();
    _senderIdentity = null;
  }
}
