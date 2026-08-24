import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/vault_file/vault_file.dart';
import 'package:project_sw/features/auth/data/encrypted_vault_repository.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  late Directory temporaryDirectory;
  late String vaultPath;
  late FakeBiometricKeyStore keyStore;
  late EncryptedVaultRepository repository;

  setUp(() async {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_biometric_repository_test_',
    );
    vaultPath = '${temporaryDirectory.path}/vault.psw';
    keyStore = FakeBiometricKeyStore();
    repository = EncryptedVaultRepository(
      crypto: FakeCryptoService(),
      vaultFileEngine: VaultFileEngine(),
      vaultPathResolver: () async => vaultPath,
      biometricKeyStore: keyStore,
    );
    await repository.createEmptyVault(
      masterPassword: 'correct password',
      kdfParameters: const Argon2idParameters(
        memoryKiB: 64 * 1024,
        iterations: 3,
        parallelism: 1,
      ),
    );
    await repository.unlockWithMasterPassword('correct password');
    await repository.addEntry(
      const NewVaultEntry(name: 'Example', password: 'private'),
    );
  });

  tearDown(() {
    repository.clearUnlockedSession();
    temporaryDirectory.deleteSync(recursive: true);
  });

  test(
    'enables biometric access by storing only an MVK envelope in the file',
    () async {
      await repository.enableBiometricUnlock(
        activityGuard: const _AlwaysActiveGuard(),
      );

      final OpenVaultFile opened = VaultFileEngine().openVaultFile(vaultPath);
      expect(repository.hasBiometricUnlock, isTrue);
      expect(opened.header.flags & 0x01, 0x01);
      expect(opened.header.biometricWrappedMasterVaultKey, hasLength(72));
      expect(keyStore.createdKeys, hasLength(1));
    },
  );

  test(
    'reopens the same vault through biometric access after a restart',
    () async {
      await repository.enableBiometricUnlock(
        activityGuard: const _AlwaysActiveGuard(),
      );
      repository.clearUnlockedSession();

      final EncryptedVaultRepository restarted = EncryptedVaultRepository(
        crypto: FakeCryptoService(),
        vaultFileEngine: VaultFileEngine(),
        vaultPathResolver: () async => vaultPath,
        biometricKeyStore: keyStore,
      );
      addTearDown(restarted.clearUnlockedSession);

      expect(await restarted.hasConfiguredBiometricUnlock(), isTrue);
      await restarted.unlockWithBiometric();

      expect(restarted.hasUnlockedSession, isTrue);
      expect(restarted.entrySummaries.single.name, 'Example');
      expect(keyStore.loadedKeys, hasLength(1));
    },
  );

  test(
    'resets by disabling the old key before creating the new pair',
    () async {
      await repository.enableBiometricUnlock(
        activityGuard: const _AlwaysActiveGuard(),
      );
      final Uint8List firstEnvelope = Uint8List.fromList(
        VaultFileEngine()
            .openVaultFile(vaultPath)
            .header
            .biometricWrappedMasterVaultKey!,
      );

      await repository.enableBiometricUnlock(
        activityGuard: const _AlwaysActiveGuard(),
      );

      final OpenVaultFile opened = VaultFileEngine().openVaultFile(vaultPath);
      expect(keyStore.deleteCount, 1);
      expect(keyStore.hasKey, isTrue);
      expect(opened.header.biometricWrappedMasterVaultKey, isNotNull);
      expect(
        opened.header.biometricWrappedMasterVaultKey,
        isNot(orderedEquals(firstEnvelope)),
      );
    },
  );

  test(
    'disabling biometric access removes the envelope and platform key',
    () async {
      await repository.enableBiometricUnlock(
        activityGuard: const _AlwaysActiveGuard(),
      );

      await repository.disableBiometricUnlock(
        activityGuard: const _AlwaysActiveGuard(),
      );

      final OpenVaultFile opened = VaultFileEngine().openVaultFile(vaultPath);
      expect(repository.hasBiometricUnlock, isFalse);
      expect(opened.header.flags & 0x01, 0);
      expect(opened.header.biometricWrappedMasterVaultKey, isNull);
      expect(keyStore.deleted, isTrue);
    },
  );

  test(
    'keeps the master-password path available when biometric access fails',
    () async {
      await repository.enableBiometricUnlock(
        activityGuard: const _AlwaysActiveGuard(),
      );
      repository.clearUnlockedSession();
      keyStore.loadFailure = const BiometricCancelledException();

      expect(
        repository.unlockWithBiometric(),
        throwsA(isA<BiometricCancelledException>()),
      );
      expect(repository.hasUnlockedSession, isFalse);

      await repository.unlockWithMasterPassword('correct password');
      expect(repository.hasUnlockedSession, isTrue);
    },
  );

  test('cleans unlocked key material before publishing a biometric lock', () {
    final SessionController controller = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
      secretCleaner: repository,
    );
    addTearDown(controller.dispose);

    controller.lock(LockReason.backgroundOrTimeout);

    expect(repository.hasUnlockedSession, isFalse);
    expect(controller.state, isA<LockedSession>());
  });

  test('an interrupted reset fails safe with biometrics disabled', () async {
    await repository.enableBiometricUnlock(
      activityGuard: const _AlwaysActiveGuard(),
    );
    keyStore.blockNextCreate();
    final SessionController controller = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      secretCleaner: repository,
    );
    final SessionActivityLease activityLease = controller.beginActivity(
      SessionActivity.biometricConfiguration,
    );
    addTearDown(controller.dispose);

    final Future<void> reset = repository.enableBiometricUnlock(
      activityGuard: activityLease,
    );
    await keyStore.createStarted.future;

    controller.handle(SessionEvent.appBackgrounded);
    keyStore.completeCreate();

    await expectLater(reset, throwsA(isA<SessionActivityInterrupted>()));
    final OpenVaultFile opened = VaultFileEngine().openVaultFile(vaultPath);
    expect(opened.header.biometricWrappedMasterVaultKey, isNull);
    expect(repository.hasBiometricUnlock, isFalse);
    expect(keyStore.hasKey, isFalse);
  });

  test('lock during key deletion leaves biometrics disabled', () async {
    await repository.enableBiometricUnlock(
      activityGuard: const _AlwaysActiveGuard(),
    );
    keyStore.blockNextDelete();
    final SessionController controller = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      secretCleaner: repository,
    );
    final SessionActivityLease activityLease = controller.beginActivity(
      SessionActivity.biometricConfiguration,
    );
    addTearDown(controller.dispose);

    final Future<void> disable = repository.disableBiometricUnlock(
      activityGuard: activityLease,
    );
    await keyStore.deleteStarted.future;

    controller.handle(SessionEvent.appBackgrounded);
    keyStore.completeDelete();

    await expectLater(disable, throwsA(isA<SessionActivityInterrupted>()));
    final OpenVaultFile opened = VaultFileEngine().openVaultFile(vaultPath);
    expect(opened.header.biometricWrappedMasterVaultKey, isNull);
    expect(repository.hasBiometricUnlock, isFalse);
    expect(keyStore.hasKey, isFalse);
  });
}

final class _AlwaysActiveGuard implements SessionActivityGuard {
  const _AlwaysActiveGuard();

  @override
  void ensureActive() {}
}

final class FakeBiometricKeyStore implements BiometricKeyStore {
  final List<Uint8List> createdKeys = <Uint8List>[];
  final List<Uint8List> loadedKeys = <Uint8List>[];
  Object? loadFailure;
  var deleted = false;
  var deleteCount = 0;
  final Completer<void> createStarted = Completer<void>();
  final Completer<void> deleteStarted = Completer<void>();
  Completer<void>? _createCompletion;
  Completer<void>? _deleteCompletion;
  Uint8List? _key;

  bool get hasKey => _key != null;

  void blockNextCreate() => _createCompletion = Completer<void>();

  void completeCreate() => _createCompletion?.complete();

  void blockNextDelete() => _deleteCompletion = Completer<void>();

  void completeDelete() => _deleteCompletion?.complete();

  @override
  Future<BiometricAvailability> get availability async =>
      BiometricAvailability.available;

  @override
  Future<Uint8List> createAndStoreKey() async {
    final int generation = createdKeys.length + 1;
    _key = Uint8List.fromList(
      List<int>.generate(32, (int index) => index + generation),
    );
    createdKeys.add(Uint8List.fromList(_key!));
    final Completer<void>? pending = _createCompletion;
    if (pending != null) {
      if (!createStarted.isCompleted) createStarted.complete();
      await pending.future;
    }
    return Uint8List.fromList(_key!);
  }

  @override
  Future<Uint8List> loadKey() async {
    final Object? failure = loadFailure;
    if (failure != null) throw failure;
    final Uint8List? key = _key;
    if (key == null) {
      throw const BiometricUnavailableException();
    }
    loadedKeys.add(Uint8List.fromList(key));
    return Uint8List.fromList(key);
  }

  @override
  Future<void> deleteKey() async {
    _key = null;
    deleted = true;
    deleteCount++;
    final Completer<void>? pending = _deleteCompletion;
    if (pending != null) {
      if (!deleteStarted.isCompleted) deleteStarted.complete();
      await pending.future;
    }
  }
}
