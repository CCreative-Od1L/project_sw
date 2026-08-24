import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String repositoryRoot = Directory.current.path;
  final String script = '$repositoryRoot/scripts/prepare_android_signing.sh';

  Future<ProcessResult> runScript({
    String? encodedKeystore,
    required String keystorePath,
    Map<String, String> environment = const <String, String>{},
  }) => Process.run(
    'bash',
    <String>[script],
    workingDirectory: Directory.systemTemp.path,
    environment: <String, String>{
      ...Platform.environment,
      'ANDROID_KEYSTORE_BASE64': ?encodedKeystore,
      'ANDROID_KEYSTORE_PATH': keystorePath,
      ...environment,
    },
  );

  test(
    'decodes signing material outside the workspace with restrictive mode',
    () async {
      final Directory fixture = await Directory.systemTemp.createTemp(
        'android-signing-script-test-',
      );
      addTearDown(() => fixture.delete(recursive: true));
      final File keystore = File('${fixture.path}/release.keystore');
      final String secret = 'test-only-keystore-bytes';
      final ProcessResult result = await runScript(
        encodedKeystore: base64Encode(utf8.encode(secret)),
        keystorePath: keystore.path,
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(await keystore.readAsString(), secret);
      expect(result.stdout, isNot(contains(secret)));
      expect(result.stderr, isNot(contains(secret)));
      if (!Platform.isWindows) {
        expect((await keystore.stat()).mode & 0x1ff, 0x180);
      }
    },
  );

  test('fails closed when the signing secret is missing or invalid', () async {
    final Directory fixture = await Directory.systemTemp.createTemp(
      'android-signing-script-test-',
    );
    addTearDown(() => fixture.delete(recursive: true));
    final String keystorePath = '${fixture.path}/release.keystore';

    final ProcessResult missing = await runScript(
      keystorePath: keystorePath,
      environment: <String, String>{'ANDROID_KEYSTORE_BASE64': ''},
    );
    expect(missing.exitCode, 1);
    expect(missing.stderr, contains('ANDROID_KEYSTORE_BASE64 is required'));
    expect(missing.stderr, isNot(contains(keystorePath)));

    final ProcessResult invalid = await runScript(
      encodedKeystore: 'not-valid-base64%%%',
      keystorePath: keystorePath,
    );
    expect(invalid.exitCode, 1);
    expect(invalid.stderr, contains('not valid base64'));
    expect(File(keystorePath).existsSync(), isFalse);
  });

  test('refuses to place signing material in the workspace', () async {
    final Directory fixture = await Directory.systemTemp.createTemp(
      'android-signing-script-test-',
    );
    addTearDown(() => fixture.delete(recursive: true));
    final String secret = 'test-only-keystore-bytes';
    final ProcessResult result = await runScript(
      encodedKeystore: base64Encode(utf8.encode(secret)),
      keystorePath: '${fixture.path}/release.keystore',
      environment: <String, String>{'GITHUB_WORKSPACE': fixture.path},
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('outside the GitHub workspace'));
    expect(File('${fixture.path}/release.keystore').existsSync(), isFalse);
  });
}
