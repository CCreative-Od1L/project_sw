import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/features/auth/data/file_vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_wipe_test_',
    );
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('deletes the platform key and every explicit app-data target', () async {
    final String vaultPath = '${temporaryDirectory.path}/vault.psw';
    final String recoveryPath = '${temporaryDirectory.path}/recovery.json';
    final String logPath = '${temporaryDirectory.path}/logs';
    final List<String> targets = <String>[
      vaultPath,
      '$vaultPath.bak',
      '$vaultPath.tmp',
      '$vaultPath.migration.tmp',
      recoveryPath,
      '$recoveryPath.tmp',
      logPath,
    ];
    for (final String path in targets.take(6)) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('encrypted or non-secret test data');
    }
    Directory(logPath).createSync();
    File('$logPath/app.log').writeAsStringSync('redacted log');
    final _WipeBiometricKeyStore keyStore = _WipeBiometricKeyStore();
    final FileVaultWipeRepository repository = FileVaultWipeRepository(
      biometricKeyStore: keyStore,
      targetPathsResolver: () async => targets,
    );

    await repository.wipeVault();

    expect(keyStore.deleteCalls, 1);
    for (final String path in targets) {
      expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound);
    }
  });

  test('does not delete files when platform key deletion fails', () async {
    final String vaultPath = '${temporaryDirectory.path}/vault.psw';
    File(vaultPath).writeAsStringSync('encrypted vault');
    final FileVaultWipeRepository repository = FileVaultWipeRepository(
      biometricKeyStore: _WipeBiometricKeyStore(
        error: const BiometricAuthenticationException(),
      ),
      targetPathsResolver: () async => <String>[vaultPath],
    );

    await expectLater(
      repository.wipeVault(),
      throwsA(isA<VaultWipeException>()),
    );

    expect(File(vaultPath).existsSync(), isTrue);
  });

  test('rejects a filesystem root before deleting the platform key', () async {
    final _WipeBiometricKeyStore keyStore = _WipeBiometricKeyStore();
    final FileVaultWipeRepository repository = FileVaultWipeRepository(
      biometricKeyStore: keyStore,
      targetPathsResolver: () async => <String>['/'],
    );

    await expectLater(
      repository.wipeVault(),
      throwsA(isA<VaultWipeException>()),
    );

    expect(keyStore.deleteCalls, 0);
  });
}

final class _WipeBiometricKeyStore implements BiometricKeyStore {
  _WipeBiometricKeyStore({this.error});

  final Object? error;
  var deleteCalls = 0;

  @override
  Future<BiometricAvailability> get availability async =>
      BiometricAvailability.available;

  @override
  Future<Uint8List> createAndStoreKey() async => throw UnimplementedError();

  @override
  Future<void> deleteKey() async {
    deleteCalls++;
    final Object? failure = error;
    if (failure != null) throw failure;
  }

  @override
  Future<Uint8List> loadKey() async => throw UnimplementedError();
}
