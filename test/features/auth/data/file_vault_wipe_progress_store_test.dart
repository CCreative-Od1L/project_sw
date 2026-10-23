import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/features/auth/data/file_vault_wipe_progress_store.dart';
import 'package:project_sw/features/auth/data/file_vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_progress_store.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('wipe_progress_');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  FileVaultWipeProgressStore progress() => FileVaultWipeProgressStore(
    pathResolver: () async => '${directory.path}/vault.psw.wipe-pending',
  );

  test(
    'marker survives store reconstruction and an empty interrupted write',
    () async {
      expect(await progress().readPending(), isFalse);
      await progress().markPending();
      expect(await progress().readPending(), isTrue);
      File('${directory.path}/vault.psw.wipe-pending').writeAsStringSync('');
      expect(await progress().readPending(), isTrue);
      await progress().clear();
      await progress().clear();
      expect(await progress().readPending(), isFalse);
    },
  );

  for (final bool vaultExists in <bool>[false, true]) {
    test(
      'production bootstrap blocks pending wipe with vault=$vaultExists',
      () async {
        final GetIt locator = GetIt.asNewInstance();
        addTearDown(() => locator.reset(dispose: true));
        if (vaultExists) {
          File('${directory.path}/vault.psw').writeAsStringSync('ciphertext');
        }
        File('${directory.path}/vault.psw.bak').writeAsStringSync('residue');
        await progress().markPending();

        await registerProductionAppDependencies(
          locator,
          supportDirectory: directory,
          documentsDirectory: directory,
          crypto: FakeCryptoService(),
          keyStore: _KeyStore(),
        );

        final SessionController session = locator<SessionController>();
        expect(
          session.state,
          isA<LockedSession>().having(
            (LockedSession state) => state.reason,
            'reason',
            LockReason.wipeStarted,
          ),
        );
        expect(session.beginUnlockAttempt, throwsStateError);
        expect(() => session.unlock(AuthStrength.biometric), throwsStateError);
        expect(
          () => session.unlock(AuthStrength.masterPassword),
          throwsStateError,
        );
      },
    );
  }

  test('marker write failure prevents key and file deletion', () async {
    final String vault = '${directory.path}/vault.psw';
    File(vault).writeAsStringSync('ciphertext');
    final _KeyStore key = _KeyStore();
    final SessionController session = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    addTearDown(session.dispose);
    final WipeVault wipe = WipeVault(
      FileVaultWipeRepository(
        biometricKeyStore: key,
        targetPathsResolver: () async => <String>[vault],
        progressStore: _ProgressFailure(progress(), failMark: true),
      ),
      session,
    );

    await expectLater(wipe(), throwsA(isA<VaultWipeException>()));
    expect(key.deletions, 0);
    expect(File(vault).existsSync(), isTrue);
    expect(wipe.isPending, isTrue);
  });

  test(
    'partial deletion remains blocked after restart and retries idempotently',
    () async {
      final String vault = '${directory.path}/vault.psw';
      final String backup = '$vault.bak';
      File(vault).writeAsStringSync('ciphertext');
      File(backup).writeAsStringSync('backup');
      final _KeyStore key = _KeyStore(
        onDelete: () async {
          expect(await progress().readPending(), isTrue);
        },
      );
      final SessionController first = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      addTearDown(first.dispose);
      final WipeVault wipe = WipeVault(
        FileVaultWipeRepository(
          biometricKeyStore: key,
          targetPathsResolver: () async => <String>[vault, backup],
          progressStore: progress(),
          removeTarget: (String path) async {
            if (path == backup) {
              throw const FileSystemException('simulated interruption');
            }
            await File(path).delete();
          },
        ),
        first,
      );
      await expectLater(wipe(), throwsA(isA<VaultWipeException>()));
      expect(File(vault).existsSync(), isFalse);
      expect(File(backup).existsSync(), isTrue);
      expect(await progress().readPending(), isTrue);

      final GetIt restarted = GetIt.asNewInstance();
      addTearDown(() => restarted.reset(dispose: true));
      await registerProductionAppDependencies(
        restarted,
        supportDirectory: directory,
        documentsDirectory: directory,
        crypto: FakeCryptoService(),
        keyStore: key,
      );
      final WipeVault resumed = restarted<WipeVault>();
      expect(resumed.isPending, isTrue);
      await resumed();
      expect(await progress().readPending(), isFalse);
      expect(File(backup).existsSync(), isFalse);
      expect(
        restarted<SessionController>().state,
        isA<VaultNotCreatedSession>(),
      );
      expect(key.deletions, 2);
    },
  );

  test(
    'marker removal failure keeps setup blocked even after targets are gone',
    () async {
      final String vault = '${directory.path}/vault.psw';
      File(vault).writeAsStringSync('ciphertext');
      final SessionController session = SessionController(
        initialState: const LockedSession(reason: LockReason.coldStart),
      );
      addTearDown(session.dispose);
      final WipeVault wipe = WipeVault(
        FileVaultWipeRepository(
          biometricKeyStore: _KeyStore(),
          targetPathsResolver: () async => <String>[vault],
          progressStore: _ProgressFailure(progress(), failClear: true),
        ),
        session,
      );
      await expectLater(wipe(), throwsA(isA<VaultWipeException>()));
      expect(File(vault).existsSync(), isFalse);
      expect(await progress().readPending(), isTrue);
      expect(wipe.isPending, isTrue);
    },
  );

  test(
    'unexpected marker type is pending and cannot permit deletion',
    () async {
      Directory('${directory.path}/vault.psw.wipe-pending').createSync();
      expect(await progress().readPending(), isTrue);
      await expectLater(
        progress().markPending(),
        throwsA(isA<VaultWipeException>()),
      );
      await expectLater(progress().clear(), throwsA(isA<VaultWipeException>()));
    },
  );
}

final class _KeyStore implements BiometricKeyStore {
  _KeyStore({this.onDelete});
  final Future<void> Function()? onDelete;
  int deletions = 0;
  @override
  Future<void> deleteKey() async {
    deletions++;
    await onDelete?.call();
  }

  @override
  Future<BiometricAvailability> get availability async =>
      BiometricAvailability.available;
  @override
  Future<Uint8List> createAndStoreKey() async => Uint8List(32);
  @override
  Future<Uint8List> loadKey() async => Uint8List(32);
}

final class _ProgressFailure implements VaultWipeProgressStore {
  _ProgressFailure(this.inner, {this.failMark = false, this.failClear = false});
  final VaultWipeProgressStore inner;
  final bool failMark;
  final bool failClear;
  @override
  Future<bool> readPending() => inner.readPending();
  @override
  Future<void> markPending() async {
    if (failMark) throw const VaultWipeException();
    await inner.markPending();
  }

  @override
  Future<void> clear() async {
    if (failClear) throw const VaultWipeException();
    await inner.clear();
  }
}
