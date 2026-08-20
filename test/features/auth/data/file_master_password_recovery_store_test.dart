import 'dart:io';

import 'package:project_sw/features/auth/data/file_master_password_recovery_store.dart';
import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'project_sw_recovery_store_test_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('persists and clears only the UTC cooldown deadline', () async {
    final String path = '${temporaryDirectory.path}/recovery.json';
    final FileMasterPasswordRecoveryStore store =
        FileMasterPasswordRecoveryStore(pathResolver: () async => path);
    final DateTime deadline = DateTime.utc(2026, 8, 27, 12);

    expect(await store.readCooldownUntil(), isNull);
    await store.writeCooldownUntil(deadline);

    final FileMasterPasswordRecoveryStore reopened =
        FileMasterPasswordRecoveryStore(pathResolver: () async => path);
    expect(await reopened.readCooldownUntil(), deadline);
    expect(
      File(path).readAsStringSync(),
      '{"cooldown_until":"2026-08-27T12:00:00.000Z"}',
    );
    final DateTime replacement = DateTime.utc(2026, 9, 3, 12);
    await reopened.writeCooldownUntil(replacement);
    expect(await store.readCooldownUntil(), replacement);

    await reopened.clearCooldown();
    expect(await store.readCooldownUntil(), isNull);
  });

  test('rejects malformed cooldown metadata instead of enabling recovery', () {
    final String path = '${temporaryDirectory.path}/recovery.json';
    File(path).writeAsStringSync('{"cooldown_until":"not-a-utc-time"}');
    final FileMasterPasswordRecoveryStore store =
        FileMasterPasswordRecoveryStore(pathResolver: () async => path);

    expect(
      store.readCooldownUntil(),
      throwsA(isA<MasterPasswordRecoveryStoreException>()),
    );
    expect(File(path).existsSync(), isTrue);
  });
}
