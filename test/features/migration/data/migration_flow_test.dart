import 'dart:async';
import 'dart:typed_data';

import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/migration/data/migration_flow.dart';
import 'package:project_sw/features/migration/data/migration_socket_transport.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  SessionController controller() {
    final result = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    addTearDown(result.dispose);
    return result;
  }

  NetworkMigrationFlow flow(
    SessionController session, {
    ScopeVault? vault,
    MigrationHostResolver? host,
  }) {
    final result = NetworkMigrationFlow(
      crypto: FakeCryptoService(),
      vault: vault ?? ScopeVault(),
      sessionController: session,
      hostResolver: host ?? () async => '127.0.0.1',
    );
    addTearDown(result.cancel);
    return result;
  }

  test(
    'loopback pairing and transfer keep one lease from preparation through import',
    () async {
      final sender = controller();
      final receiver = controller();
      final source = ScopeVault(source: <int>[1, 2]);
      final destination = ScopeVault();
      final sending = flow(sender, vault: source);
      final receiving = flow(receiver, vault: destination);
      final Uint8List selected = Uint8List.fromList(List<int>.filled(16, 2));
      final selection = MigrationSelection.single(selected);
      selected.fillRange(0, selected.length, 9); // Selection owns its identity.
      final payload = await sending.prepareSender(selection: selection);
      expect(
        (sender.state as UnlockedSession).activity,
        SessionActivity.migrationSending,
      );
      await receiving.prepareReceiver();
      expect(
        (receiver.state as UnlockedSession).activity,
        SessionActivity.migrationReceiving,
      );
      await Future.wait<void>(<Future<void>>[
        sending.runSender(),
        receiving.runReceiver(payload),
      ]);
      expect(destination.imported, <int>[2]);
      expect((sender.state as UnlockedSession).activity, SessionActivity.none);
      expect(
        (receiver.state as UnlockedSession).activity,
        SessionActivity.none,
      );
    },
  );

  test(
    'biometric sessions cannot create listener or scanner activity',
    () async {
      final session = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      addTearDown(session.dispose);
      var resolutions = 0;
      final migration = flow(
        session,
        host: () async {
          resolutions++;
          return '127.0.0.1';
        },
      );
      await expectLater(migration.prepareSender(), throwsStateError);
      await expectLater(migration.prepareReceiver(), throwsStateError);
      expect(resolutions, 0);
      expect((session.state as UnlockedSession).activity, SessionActivity.none);
    },
  );

  test(
    'lock during address resolution revokes the listener and suppresses late payload',
    () async {
      final session = controller();
      final host = Completer<String>();
      final resolving = Completer<void>();
      final migration = flow(
        session,
        host: () {
          resolving.complete();
          return host.future;
        },
      );
      final preparation = migration.prepareSender();
      final rejected = expectLater(
        preparation,
        throwsA(isA<SessionActivityInterrupted>()),
      );
      await resolving.future;
      session.lock(LockReason.manualLock);
      host.complete('127.0.0.1');
      await rejected;
      expect(session.state, isA<LockedSession>());
      await migration.cancel();
    },
  );

  test(
    'cancelled preparation cannot close a replacement receiver lease',
    () async {
      final session = controller();
      final host = Completer<String>();
      final resolving = Completer<void>();
      final migration = flow(
        session,
        host: () {
          resolving.complete();
          return host.future;
        },
      );
      final preparation = migration.prepareSender();
      final rejected = expectLater(
        preparation,
        throwsA(isA<SessionActivityInterrupted>()),
      );
      await resolving.future;
      await migration.cancel();
      await migration.prepareReceiver();
      host.complete('127.0.0.1');
      await rejected;
      expect(
        (session.state as UnlockedSession).activity,
        SessionActivity.migrationReceiving,
      );
      await migration.cancel();
      expect((session.state as UnlockedSession).activity, SessionActivity.none);
    },
  );

  test('lock aborts a sender waiting for the peer handshake', () async {
    final session = controller();
    final migration = flow(session);
    final payload = await migration.prepareSender();
    final run = migration.runSender();
    final rejected = expectLater(run, throwsA(isA<Object>()));
    final peer = await MigrationSocketTransport.connect(
      payload.host,
      payload.port,
    );
    addTearDown(peer.close);
    session.lock(LockReason.manualLock);
    await rejected.timeout(const Duration(seconds: 3));
    expect(session.state, isA<LockedSession>());
  });

  test(
    'expired pairing fails before dialing and releases the scanner lease',
    () async {
      final session = controller();
      final migration = flow(session);
      await migration.prepareReceiver();
      final payload = MigrationPairingPayload.issue(
        host: '127.0.0.1',
        port: 1,
        senderPublicKey: Uint8List(32),
        issuedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      await expectLater(migration.runReceiver(payload), throwsStateError);
      expect((session.state as UnlockedSession).activity, SessionActivity.none);
    },
  );
}

final class ScopeVault implements MigrationVaultPort {
  ScopeVault({this.source = const <int>[]});
  final List<int> source;
  final List<int> imported = <int>[];

  @override
  Future<List<MigrationEntryPayload>> exportMigrationEntries({
    required SessionActivityGuard activityGuard,
    MigrationSelection selection = const MigrationSelection.all(),
  }) async {
    activityGuard.ensureActive();
    return <MigrationEntryPayload>[
      for (final id in source)
        if (selection.includes(Uint8List.fromList(List<int>.filled(16, id))))
          MigrationEntryPayload(
            entryId: Uint8List.fromList(List<int>.filled(16, id)),
            sequence: 1,
            plaintextFormatId: 1,
            entryCiphertext: Uint8List(40),
            dek: Uint8List(32),
          ),
    ];
  }

  @override
  Future<void> importMigrationEntries(
    List<MigrationEntryPayload> entries, {
    required SessionActivityGuard activityGuard,
  }) async {
    activityGuard.ensureActive();
    imported.addAll(entries.map((entry) => entry.entryId.first));
  }
}
