import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/vault/domain/add_vault_entry.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';

void main() {
  test(
    'lock interrupts a detail read and clears the summary projection',
    () async {
      final BlockingVaultRepository repository = BlockingVaultRepository();
      final SessionController sessionController = _session();
      final VaultEntriesCubit entries = _entries(repository, sessionController);
      addTearDown(entries.close);
      addTearDown(sessionController.dispose);

      final Future<EntryDetail> detail = entries.detail(_entryId);
      await repository.detailStarted.future;

      sessionController.lock(LockReason.manualLock);
      repository.releaseDetail.complete();

      await expectLater(detail, throwsA(isA<SessionActivityInterrupted>()));
      expect(entries.state.summaries, isEmpty);
    },
  );

  test('lock interrupts an add before it publishes a summary', () async {
    final BlockingVaultRepository repository = BlockingVaultRepository();
    final SessionController sessionController = _session();
    final VaultEntriesCubit entries = _entries(repository, sessionController);
    addTearDown(entries.close);
    addTearDown(sessionController.dispose);

    final Future<void> add = entries.add(
      const NewVaultEntry(name: 'Lock-raced entry', password: 'secret'),
    );
    await repository.addStarted.future;

    sessionController.lock(LockReason.backgroundOrTimeout);
    repository.releaseAdd.complete();
    await add;

    expect(repository.addCalls, 0);
    expect(entries.state.summaries, isEmpty);
  });

  test('lock interrupts an update before the repository commits it', () async {
    final BlockingVaultRepository repository = BlockingVaultRepository();
    final SessionController sessionController = _session();
    final VaultEntriesCubit entries = _entries(repository, sessionController);
    addTearDown(entries.close);
    addTearDown(sessionController.dispose);

    final Future<void> update = entries.update(_entry);
    await repository.updateStarted.future;

    sessionController.lock(LockReason.manualLock);
    repository.releaseUpdate.complete();

    await expectLater(update, throwsA(isA<SessionActivityInterrupted>()));
    expect(repository.updateCalls, 0);
    expect(entries.state.summaries, isEmpty);
  });

  test('lock interrupts a delete before the repository commits it', () async {
    final BlockingVaultRepository repository = BlockingVaultRepository();
    final SessionController sessionController = _session();
    final VaultEntriesCubit entries = _entries(repository, sessionController);
    addTearDown(entries.close);
    addTearDown(sessionController.dispose);

    final Future<void> delete = entries.delete(_entryId);
    await repository.deleteStarted.future;

    sessionController.lock(LockReason.manualLock);
    repository.releaseDelete.complete();

    await expectLater(delete, throwsA(isA<SessionActivityInterrupted>()));
    expect(repository.deleteCalls, 0);
    expect(entries.state.summaries, isEmpty);
  });

  test('closing the cubit cancels an in-flight vault activity', () async {
    final BlockingVaultRepository repository = BlockingVaultRepository();
    final SessionController sessionController = _session();
    final VaultEntriesCubit entries = _entries(repository, sessionController);
    addTearDown(sessionController.dispose);

    final Future<EntryDetail> detail = entries.detail(_entryId);
    await repository.detailStarted.future;

    final Future<void> close = entries.close();
    repository.releaseDetail.complete();

    await close;
    await expectLater(detail, throwsA(isA<SessionActivityInterrupted>()));
    expect(
      (sessionController.state as UnlockedSession).activity,
      SessionActivity.none,
    );
  });
}

final Uint8List _entryId = Uint8List.fromList(<int>[
  ...List<int>.filled(15, 0),
  1,
]);

final VaultEntry _entry = VaultEntry(
  entryId: _entryId,
  name: 'Example',
  url: 'https://example.test',
  username: 'alice',
  password: 'secret',
  notes: 'notes',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  favorite: false,
  customFields: const <CustomField>[],
);

SessionController _session() => SessionController(
  initialState: const UnlockedSession(
    authStrength: AuthStrength.masterPassword,
  ),
);

VaultEntriesCubit _entries(
  BlockingVaultRepository repository,
  SessionController sessionController,
) {
  final VaultEntriesCubit entries = VaultEntriesCubit(
    AddVaultEntry(repository),
    repository,
    sessionController,
  );
  sessionController.registerSecretCleaner(entries);
  return entries;
}

final class BlockingVaultRepository implements VaultRepository {
  final Completer<void> detailStarted = Completer<void>();
  final Completer<void> releaseDetail = Completer<void>();
  final Completer<void> addStarted = Completer<void>();
  final Completer<void> releaseAdd = Completer<void>();
  final Completer<void> updateStarted = Completer<void>();
  final Completer<void> releaseUpdate = Completer<void>();
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> releaseDelete = Completer<void>();
  var addCalls = 0;
  var updateCalls = 0;
  var deleteCalls = 0;

  @override
  Future<void> createEmptyVault({
    required String masterPassword,
    required Argon2idParameters kdfParameters,
  }) async => throw UnimplementedError();

  @override
  Future<void> unlockWithMasterPassword(
    String masterPassword, {
    SessionActivityGuard? activityGuard,
  }) async => throw UnimplementedError();

  @override
  bool get hasUnlockedSession => true;

  @override
  Future<EntrySummary> addEntry(
    NewVaultEntry entry, {
    required SessionActivityGuard activityGuard,
  }) async {
    addStarted.complete();
    await releaseAdd.future;
    activityGuard.ensureActive();
    addCalls++;
    return _entry.toSummary();
  }

  @override
  List<EntrySummary> get entrySummaries => <EntrySummary>[_entry.toSummary()];

  @override
  Argon2idParameters? get activeKdfParameters => null;

  @override
  Future<EntryDetail> getEntryDetail(
    Uint8List entryId, {
    required SessionActivityGuard activityGuard,
  }) async {
    detailStarted.complete();
    await releaseDetail.future;
    activityGuard.ensureActive();
    return EntryDetail(_entry);
  }

  @override
  Future<EntrySummary> updateEntry(
    VaultEntry entry, {
    required SessionActivityGuard activityGuard,
  }) async {
    updateStarted.complete();
    await releaseUpdate.future;
    activityGuard.ensureActive();
    updateCalls++;
    return entry.toSummary();
  }

  @override
  Future<void> deleteEntry(
    Uint8List entryId, {
    required SessionActivityGuard activityGuard,
  }) async {
    deleteStarted.complete();
    await releaseDelete.future;
    activityGuard.ensureActive();
    deleteCalls++;
  }

  @override
  void clearUnlockedSession() {}
}
