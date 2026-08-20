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

  test('atomically replaces recovery deadlines and clears them', () async {
    final String path = '${temporaryDirectory.path}/recovery.json';
    final FileMasterPasswordRecoveryStore store =
        FileMasterPasswordRecoveryStore(pathResolver: () async => path);
    final DateTime deadline = DateTime.utc(2026, 8, 27, 12);

    expect((await store.read()).isEmpty, isTrue);
    await store.write(MasterPasswordRecoveryMetadata(cooldownUntil: deadline));

    final FileMasterPasswordRecoveryStore reopened =
        FileMasterPasswordRecoveryStore(pathResolver: () async => path);
    expect((await reopened.read()).cooldownUntil, deadline);
    expect(
      File(path).readAsStringSync(),
      '{"cooldown_until":"2026-08-27T12:00:00.000Z"}',
    );
    final DateTime replacement = DateTime.utc(2026, 9, 3, 12);
    await reopened.write(
      MasterPasswordRecoveryMetadata(availableUntil: replacement),
    );
    final MasterPasswordRecoveryMetadata replaced = await store.read();
    expect(replaced.cooldownUntil, isNull);
    expect(replaced.availableUntil, replacement);
    expect(
      File(path).readAsStringSync(),
      '{"available_until":"2026-09-03T12:00:00.000Z"}',
    );

    await reopened.clear();
    expect((await store.read()).isEmpty, isTrue);
  });

  test('rejects malformed cooldown metadata instead of enabling recovery', () {
    final String path = '${temporaryDirectory.path}/recovery.json';
    File(path).writeAsStringSync('{"cooldown_until":"not-a-utc-time"}');
    final FileMasterPasswordRecoveryStore store =
        FileMasterPasswordRecoveryStore(pathResolver: () async => path);

    expect(store.read(), throwsA(isA<MasterPasswordRecoveryStoreException>()));
    expect(File(path).existsSync(), isTrue);
  });
}
