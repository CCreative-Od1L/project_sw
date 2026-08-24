import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String repositoryRoot = Directory.current.path;
  final String script = '$repositoryRoot/scripts/verify_release_metadata.sh';

  test(
    'validates the checked-in release metadata and writes a safe manifest',
    () async {
      final Directory temporaryDirectory = await Directory.systemTemp
          .createTemp('project_sw_release_test_');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final String output = '${temporaryDirectory.path}/release-metadata.txt';

      final ProcessResult result = await Process.run(
        'bash',
        <String>[script],
        environment: <String, String>{
          'RELEASE_TAG': 'v1.0.0',
          'REQUIRE_ANNOTATED_TAG': '0',
          'OUTPUT_FILE': output,
          'REPO_ROOT': repositoryRoot,
        },
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final String metadata = await File(output).readAsString();
      expect(metadata, contains('release_tag=v1.0.0'));
      expect(metadata, contains('version=1.0.0'));
      expect(metadata, contains('commit_sha='));
      expect(metadata, contains('flutter_version=3.44.7'));
      expect(metadata, contains('pubspec_lock_sha256='));
      expect(metadata.toLowerCase(), isNot(contains('password')));
      expect(metadata.toLowerCase(), isNot(contains('secret')));
    },
  );

  test('rejects a tag whose version differs from pubspec.yaml', () async {
    final ProcessResult result = await Process.run(
      'bash',
      <String>[script],
      environment: <String, String>{
        'RELEASE_TAG': 'v1.0.1',
        'REQUIRE_ANNOTATED_TAG': '0',
        'REPO_ROOT': repositoryRoot,
      },
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('does not match pubspec version'));
  });
}
