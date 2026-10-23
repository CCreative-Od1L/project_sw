import 'dart:async';
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
  Future<MigrationPairingPayload> prepareSender({
    MigrationSelection selection = const MigrationSelection.all(),
  });

  /// Acquires the receiver activity before opening the camera.
  Future<void> prepareReceiver();

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

  _MigrationOperation? _operation;

  _MigrationOperation _begin(
    SessionActivity activity,
    MigrationSelection selection,
  ) {
    if (_operation != null) throw StateError('A migration is already active.');
    final SessionState state = sessionController.state;
    if (state is! UnlockedSession ||
        state.authStrength != AuthStrength.masterPassword) {
      throw StateError('Migration requires master-password authorization.');
    }
    final _MigrationOperation operation = _MigrationOperation(
      sessionController.beginActivity(activity),
      selection,
    );
    _operation = operation;
    operation.lease.onInterrupted(() => unawaited(_finish(operation)));
    return operation;
  }

  void _ensureActive(_MigrationOperation operation) {
    operation.lease.ensureActive();
    if (!identical(_operation, operation)) {
      throw StateError('The migration operation has ended.');
    }
  }

  @override
  Future<MigrationPairingPayload> prepareSender({
    MigrationSelection selection = const MigrationSelection.all(),
  }) async {
    final _MigrationOperation operation = _begin(
      SessionActivity.migrationSending,
      selection,
    );
    try {
      operation.identity = crypto.generateEphemeralKeyPair();
      final MigrationSocketServer server = await MigrationSocketServer.bind(
        InternetAddress.anyIPv4.address,
        0,
        timeout: pairingTtl,
      );
      if (!operation.lease.isActive) {
        await server.close();
        operation.lease.ensureActive();
      }
      operation.server = server;
      _ensureActive(operation);
      final String host = await hostResolver();
      _ensureActive(operation);
      return MigrationPairingPayload.issue(
        host: host,
        port: server.port,
        senderPublicKey: operation.identity!.publicKey,
        ttl: pairingTtl,
      );
    } on Object {
      await _finish(operation);
      rethrow;
    }
  }

  @override
  Future<void> prepareReceiver() async {
    _begin(SessionActivity.migrationReceiving, const MigrationSelection.all());
  }

  @override
  Future<void> runSender() async {
    final _MigrationOperation operation = _require(
      SessionActivity.migrationSending,
    );
    if (operation.running ||
        operation.server == null ||
        operation.identity == null) {
      throw StateError('The sender is not ready.');
    }
    operation.running = true;
    try {
      final MigrationSocketTransport transport = await operation.server!
          .accept();
      await _adoptTransport(operation, transport);
      final MigrationSession session =
          await MigrationPairingHandshake.establishSender(
            transport: transport,
            crypto: crypto,
            senderIdentity: operation.identity!,
          );
      operation.identity = null; // Handshake consumes the one-time identity.
      if (!operation.lease.isActive) {
        session.dispose();
        operation.lease.ensureActive();
      }
      operation.session = session;
      _ensureActive(operation);
      await MigrationTransferCoordinator.send(
        sessionController: sessionController,
        lease: operation.lease,
        transport: transport,
        session: session,
        capabilities: capabilities,
        vault: vault,
        selection: operation.selection,
      );
    } finally {
      await _finish(operation);
    }
  }

  @override
  Future<void> runReceiver(MigrationPairingPayload payload) async {
    final _MigrationOperation operation = _require(
      SessionActivity.migrationReceiving,
    );
    if (operation.running) throw StateError('The receiver is already running.');
    operation.running = true;
    try {
      if (payload.isExpired()) {
        throw StateError('The pairing code has expired.');
      }
      final MigrationSocketTransport transport =
          await MigrationSocketTransport.connect(
            payload.host,
            payload.port,
            timeout: pairingTtl,
          );
      await _adoptTransport(operation, transport);
      final MigrationSession session =
          await MigrationPairingHandshake.establishReceiver(
            transport: transport,
            crypto: crypto,
            senderPublicKey: payload.senderPublicKey,
          );
      if (!operation.lease.isActive) {
        session.dispose();
        operation.lease.ensureActive();
      }
      operation.session = session;
      _ensureActive(operation);
      await MigrationTransferCoordinator.receive(
        sessionController: sessionController,
        lease: operation.lease,
        transport: transport,
        session: session,
        capabilities: capabilities,
        vault: vault,
      );
    } finally {
      await _finish(operation);
    }
  }

  _MigrationOperation _require(SessionActivity activity) {
    final _MigrationOperation? operation = _operation;
    if (operation == null || operation.lease.activity != activity) {
      throw StateError('The migration has not been prepared.');
    }
    _ensureActive(operation);
    return operation;
  }

  Future<void> _adoptTransport(
    _MigrationOperation operation,
    MigrationSocketTransport transport,
  ) async {
    if (!operation.lease.isActive) {
      await transport.close();
      operation.lease.ensureActive();
    }
    operation.transport = transport;
    _ensureActive(operation);
  }

  Future<void> _finish(_MigrationOperation operation) async {
    if (identical(_operation, operation)) _operation = null;
    await operation.close();
  }

  @override
  Future<void> cancel() async {
    final _MigrationOperation? operation = _operation;
    if (operation != null) await _finish(operation);
  }
}

final class _MigrationOperation {
  _MigrationOperation(this.lease, this.selection);

  final SessionActivityLease lease;
  final MigrationSelection selection;
  MigrationSocketServer? server;
  MigrationSocketTransport? transport;
  EphemeralKeyPair? identity;
  MigrationSession? session;
  bool running = false;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // Invalidate immediately: late bind/connect/handshake results cannot be used.
    lease.cancel();
    identity?.dispose();
    identity = null;
    session?.dispose();
    session = null;
    try {
      await transport?.close();
    } on Object {
      // A failed socket close must not retain the listener or the lease.
    } finally {
      try {
        await server?.close();
      } on Object {
        // Session revocation remains authoritative on platform cleanup failure.
      }
    }
  }
}
