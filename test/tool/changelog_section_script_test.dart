import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String repositoryRoot = Directory.current.path;
  final String script = '$repositoryRoot/scripts/extract_changelog_section.sh';

  Future<ProcessResult> runScript(String version) => Process.run(
    'bash',
    <String>[script, version],
    workingDirectory: Directory.systemTemp.path,
    environment: <String, String>{
      ...Platform.environment,
      'REPO_ROOT': repositoryRoot,
    },
  );

  test('extracts one version section from any working directory', () async {
    final ProcessResult result = await runScript('1.0.0');

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, startsWith('## [1.0.0] - Unreleased'));
    expect(result.stdout, contains('### Added'));
    expect(result.stdout, contains('### Known limitations'));
  });

  test('fails for malformed or missing versions', () async {
    final ProcessResult malformed = await runScript('1.0');
    expect(malformed.exitCode, 1);
    expect(malformed.stderr, contains('version must match'));

    final ProcessResult missing = await runScript('9.9.9');
    expect(missing.exitCode, 1);
    expect(missing.stderr, contains('has no section for 9.9.9'));
  });
}
