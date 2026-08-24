import 'dart:async';
import 'dart:typed_data';

import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/migration/data/migration_socket_transport.dart';
import 'package:project_sw/features/migration/data/migration_transfer_coordinator.dart';
import 'package:project_sw/features/migration/domain/migration_exception.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:project_sw/features/migration/domain/migration_session.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  test(
    'coordinates preflight, entries, final MAC, and one import call',
    () async {
      final MigrationSocketServer server = await MigrationSocketServer.bind(
        '127.0.0.1',
        0,
      );
      final Future<MigrationSocketTransport> accepted = server.accept();
      final MigrationSocketTransport senderTransport =
          await MigrationSocketTransport.connect('127.0.0.1', server.port);
      final MigrationSocketTransport receiverTransport = await accepted;
      final ({MigrationSession sender, MigrationSession receiver}) sessions =
          _sessions();
      final RecordingVault senderVault = RecordingVault(
        source: <MigrationEntryPayload>[_payload(7)],
      );
      final RecordingVault receiverVault = RecordingVault();
      final MigrationCapabilities capabilities = _capabilities();
      final SessionController senderController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      final SessionController receiverController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      final List<SessionActivity> senderActivities = <SessionActivity>[];
      final List<SessionActivity> receiverActivities = <SessionActivity>[];
      final senderSubscription = senderController.states.listen(
        (SessionState state) =>
            senderActivities.add((state as UnlockedSession).activity),
      );
      final receiverSubscription = receiverController.states.listen(
        (SessionState state) =>
            receiverActivities.add((state as UnlockedSession).activity),
      );

      try {
        await Future.wait<void>(<Future<void>>[
          MigrationTransferCoordinator.receive(
            sessionController: receiverController,
            transport: receiverTransport,
            session: sessions.receiver,
            capabilities: capabilities,
            vault: receiverVault,
          ),
          MigrationTransferCoordinator.send(
            sessionController: senderController,
            transport: senderTransport,
            session: sessions.sender,
            capabilities: capabilities,
            vault: senderVault,
          ),
        ]);

        expect(receiverVault.importedCount, 1);
        expect(senderActivities, <SessionActivity>[
          SessionActivity.migrationSending,
          SessionActivity.none,
        ]);
        expect(receiverActivities, <SessionActivity>[
          SessionActivity.migrationReceiving,
          SessionActivity.none,
        ]);
      } finally {
        await senderSubscription.cancel();
        await receiverSubscription.cancel();
        senderController.dispose();
        receiverController.dispose();
        senderVault.disposeSource();
        sessions.sender.dispose();
        sessions.receiver.dispose();
        await senderTransport.close();
        await receiverTransport.close();
        await server.close();
      }
    },
  );

  test(
    'does not import buffered entries when the final MAC is tampered',
    () async {
      final MigrationSocketServer server = await MigrationSocketServer.bind(
        '127.0.0.1',
        0,
      );
      final Future<MigrationSocketTransport> accepted = server.accept();
      final MigrationSocketTransport connected =
          await MigrationSocketTransport.connect('127.0.0.1', server.port);
      final MigrationSocketTransport receiverTransport = await accepted;
      final TamperingTransport senderTransport = TamperingTransport(connected);
      final ({MigrationSession sender, MigrationSession receiver}) sessions =
          _sessions();
      final RecordingVault senderVault = RecordingVault(
        source: <MigrationEntryPayload>[_payload(8)],
      );
      final RecordingVault receiverVault = RecordingVault();
      final MigrationCapabilities capabilities = _capabilities();
      final SessionController senderController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      final SessionController receiverController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );

      try {
        await expectLater(
          Future.wait<void>(<Future<void>>[
            MigrationTransferCoordinator.receive(
              sessionController: receiverController,
              transport: receiverTransport,
              session: sessions.receiver,
              capabilities: capabilities,
              vault: receiverVault,
            ),
            MigrationTransferCoordinator.send(
              sessionController: senderController,
              transport: senderTransport,
              session: sessions.sender,
              capabilities: capabilities,
              vault: senderVault,
            ),
          ]),
          throwsA(isA<MigrationProtocolException>()),
        );
        expect(receiverVault.importedCount, 0);
        expect(
          (senderController.state as UnlockedSession).activity,
          SessionActivity.none,
        );
        expect(
          (receiverController.state as UnlockedSession).activity,
          SessionActivity.none,
        );
      } finally {
        senderController.dispose();
        receiverController.dispose();
        senderVault.disposeSource();
        sessions.sender.dispose();
        sessions.receiver.dispose();
        await senderTransport.close();
        await receiverTransport.close();
        await server.close();
      }
    },
  );

  test('closes pending migration transport when the session locks', () async {
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    final BlockingReceiveTransport transport = BlockingReceiveTransport();
    final MigrationSession session = _sessions().sender;
    final RecordingVault vault = RecordingVault(
      source: <MigrationEntryPayload>[_payload(9)],
    );
    final Future<void> transfer = MigrationTransferCoordinator.send(
      sessionController: sessionController,
      transport: transport,
      session: session,
      capabilities: _capabilities(),
      vault: vault,
    );
    final Future<void> observedTransfer = transfer.catchError((Object _) {});
    addTearDown(() async {
      await transport.close();
      await observedTransfer;
      vault.disposeSource();
      session.dispose();
      sessionController.dispose();
    });

    await transport.receiveStarted.future;
    sessionController.handle(SessionEvent.appBackgrounded);
    await Future<void>.delayed(Duration.zero);

    expect(transport.closeCount, 1);
  });

  test('clears exported payloads returned after the session locks', () async {
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    final DelayedExportVault vault = DelayedExportVault();
    final RecordingCloseTransport transport = RecordingCloseTransport();
    final MigrationSession session = _sessions().sender;
    final MigrationEntryPayload payload = _payload(10);
    addTearDown(() {
      payload.dispose();
      session.dispose();
      sessionController.dispose();
    });

    final Future<void> transfer = MigrationTransferCoordinator.send(
      sessionController: sessionController,
      transport: transport,
      session: session,
      capabilities: _capabilities(),
      vault: vault,
    );
    await vault.exportStarted.future;

    sessionController.handle(SessionEvent.appBackgrounded);
    vault.complete(<MigrationEntryPayload>[payload]);

    await expectLater(transfer, throwsA(isA<SessionActivityInterrupted>()));
    expect(payload.dek, everyElement(0));
    expect(payload.entryCiphertext, everyElement(0));
  });
}

MigrationCapabilities _capabilities() => MigrationCapabilities(
  formatVersion: 1,
  aeadAlgorithmId: 1,
  supportedPlaintextFormatIds: <int>[1],
);

MigrationEntryPayload _payload(int fill) => MigrationEntryPayload(
  entryId: Uint8List.fromList(List<int>.filled(16, fill)),
  sequence: fill,
  plaintextFormatId: 1,
  entryCiphertext: Uint8List.fromList(List<int>.filled(40, fill + 1)),
  dek: Uint8List.fromList(List<int>.filled(32, fill + 2)),
);

({MigrationSession sender, MigrationSession receiver}) _sessions() {
  final FakeCryptoService crypto = FakeCryptoService();
  final identity = crypto.generateEphemeralKeyPair();
  final peerIdentity = crypto.generateEphemeralKeyPair();
  final Uint8List identityPublicKey = Uint8List.fromList(identity.publicKey);
  final Uint8List peerPublicKey = Uint8List.fromList(peerIdentity.publicKey);
  return (
    sender: MigrationSession.establishClient(
      crypto: crypto,
      localIdentity: identity,
      remotePublicKey: peerPublicKey,
    ),
    receiver: MigrationSession.establishServer(
      crypto: crypto,
      localIdentity: peerIdentity,
      remotePublicKey: identityPublicKey,
    ),
  );
}

final class RecordingVault implements MigrationVaultPort {
  RecordingVault({List<MigrationEntryPayload>? source})
    : _source = source ?? <MigrationEntryPayload>[];

  final List<MigrationEntryPayload> _source;
  var importedCount = 0;

  @override
  Future<List<MigrationEntryPayload>> exportMigrationEntries({
    required SessionActivityGuard activityGuard,
  }) async => _source.map(_copyPayload).toList(growable: false);

  @override
  Future<void> importMigrationEntries(
    List<MigrationEntryPayload> entries, {
    required SessionActivityGuard activityGuard,
  }) async {
    importedCount += entries.length;
  }

  void disposeSource() {
    for (final MigrationEntryPayload payload in _source) {
      payload.dispose();
    }
  }
}

MigrationEntryPayload _copyPayload(MigrationEntryPayload payload) =>
    MigrationEntryPayload(
      entryId: payload.entryId,
      sequence: payload.sequence,
      plaintextFormatId: payload.plaintextFormatId,
      entryCiphertext: payload.entryCiphertext,
      dek: payload.dek,
    );

final class TamperingTransport implements MigrationFrameTransport {
  TamperingTransport(this._delegate);

  final MigrationFrameTransport _delegate;
  var _tamperFinal = true;

  @override
  Future<void> send(MigrationSessionFrame frame) {
    if (!_tamperFinal || frame.type != MigrationMessageType.transferEnd) {
      return _delegate.send(frame);
    }
    _tamperFinal = false;
    final Uint8List ciphertext = Uint8List.fromList(frame.ciphertext)..[0] ^= 1;
    final MigrationSessionFrame tampered = MigrationSessionFrame(
      type: frame.type,
      sequence: frame.sequence,
      nonce: frame.nonce,
      ciphertext: ciphertext,
    );
    return _sendAndDispose(tampered);
  }

  Future<void> _sendAndDispose(MigrationSessionFrame frame) async {
    try {
      await _delegate.send(frame);
    } finally {
      frame.dispose();
    }
  }

  @override
  Future<MigrationSessionFrame> receive() => _delegate.receive();

  @override
  Future<void> close() => _delegate.close();
}

final class BlockingReceiveTransport implements MigrationFrameTransport {
  final Completer<void> receiveStarted = Completer<void>();
  final Completer<MigrationSessionFrame> _pendingReceive =
      Completer<MigrationSessionFrame>();
  var closeCount = 0;

  @override
  Future<void> send(MigrationSessionFrame frame) async {}

  @override
  Future<MigrationSessionFrame> receive() {
    if (!receiveStarted.isCompleted) {
      receiveStarted.complete();
    }
    return _pendingReceive.future;
  }

  @override
  Future<void> close() async {
    closeCount++;
    if (!_pendingReceive.isCompleted) {
      _pendingReceive.completeError(
        const MigrationTransportException('Session interrupted migration.'),
      );
    }
  }
}

final class DelayedExportVault implements MigrationVaultPort {
  final Completer<void> exportStarted = Completer<void>();
  final Completer<List<MigrationEntryPayload>> _export =
      Completer<List<MigrationEntryPayload>>();

  void complete(List<MigrationEntryPayload> entries) =>
      _export.complete(entries);

  @override
  Future<List<MigrationEntryPayload>> exportMigrationEntries({
    required SessionActivityGuard activityGuard,
  }) {
    exportStarted.complete();
    return _export.future;
  }

  @override
  Future<void> importMigrationEntries(
    List<MigrationEntryPayload> entries, {
    required SessionActivityGuard activityGuard,
  }) async {}
}

final class RecordingCloseTransport implements MigrationFrameTransport {
  var closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<MigrationSessionFrame> receive() => throw StateError('Not reached.');

  @override
  Future<void> send(MigrationSessionFrame frame) async {}
}
