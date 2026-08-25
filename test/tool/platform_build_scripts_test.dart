import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String repositoryRoot = Directory.current.path;

  Future<ProcessResult> runScript(
    String script,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String> environment = const <String, String>{},
  }) => Process.run(
    'bash',
    <String>['$repositoryRoot/scripts/$script', ...arguments],
    workingDirectory: workingDirectory,
    environment: <String, String>{
      ...Platform.environment,
      'REPO_ROOT': repositoryRoot,
      ...environment,
    },
  );

  Future<Directory> createFakeFlutterFixture() async {
    final Directory fixture = await Directory.systemTemp.createTemp(
      'platform-build-script-test-',
    );
    final File fakeFlutter = File('${fixture.path}/fake_flutter.sh');
    await fakeFlutter.writeAsString(r'''#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" > "${FAKE_FLUTTER_ARGS_FILE}"

case "$*" in
  'build apk --debug --no-pub')
    artifact='build/app/outputs/flutter-apk/app-debug.apk'
    ;;
  'build appbundle --release --no-pub')
    artifact='build/app/outputs/bundle/release/app-release.aab'
    ;;
  'build appbundle --release')
    artifact='build/app/outputs/bundle/release/app-release.aab'
    ;;
  *)
    echo "unexpected Flutter arguments: $*" >&2
    exit 42
    ;;
esac

if [[ "${FAKE_FLUTTER_SKIP_ARTIFACT:-0}" != '1' ]]; then
  mkdir -p "$(dirname -- "${artifact}")"
  touch "${artifact}"
fi
''');
    return fixture;
  }

  test('Android build script exposes explicit safe modes', () async {
    final ProcessResult help = await runScript('build_android.sh', <String>[
      '--help',
    ]);
    expect(help.exitCode, 0, reason: '${help.stderr}');
    expect(help.stdout, contains('debug-apk'));
    expect(help.stdout, contains('release-aab'));

    final ProcessResult invalid = await runScript('build_android.sh', <String>[
      'unknown-mode',
    ]);
    expect(invalid.exitCode, 2);
  });

  test(
    'Android build script is cwd-independent and validates its artifact',
    () async {
      final Directory fixture = await createFakeFlutterFixture();
      addTearDown(() => fixture.delete(recursive: true));
      final File arguments = File('${fixture.path}/flutter-arguments.txt');
      final Map<String, String> environment = <String, String>{
        'REPO_ROOT': fixture.path,
        'FLUTTER_COMMAND': 'bash ${fixture.path}/fake_flutter.sh',
        'FAKE_FLUTTER_ARGS_FILE': arguments.path,
      };

      final ProcessResult debug = await runScript(
        'build_android.sh',
        <String>['debug-apk'],
        workingDirectory: Directory.systemTemp.path,
        environment: environment,
      );
      expect(debug.exitCode, 0, reason: '${debug.stderr}');
      expect(arguments.readAsStringSync(), 'build\napk\n--debug\n--no-pub\n');
      expect(
        File(
          '${fixture.path}/build/app/outputs/flutter-apk/app-debug.apk',
        ).existsSync(),
        isTrue,
      );

      final ProcessResult release = await runScript(
        'build_android.sh',
        <String>['release-aab'],
        workingDirectory: Directory.systemTemp.path,
        environment: environment,
      );
      expect(release.exitCode, 0, reason: '${release.stderr}');
      expect(
        arguments.readAsStringSync(),
        'build\nappbundle\n--release\n--no-pub\n',
      );
      expect(
        File(
          '${fixture.path}/build/app/outputs/bundle/release/app-release.aab',
        ).existsSync(),
        isTrue,
      );

      final ProcessResult releaseWithPub = await runScript(
        'build_android.sh',
        <String>['release-aab'],
        workingDirectory: Directory.systemTemp.path,
        environment: <String, String>{
          ...environment,
          'FLUTTER_BUILD_WITH_PUB': '1',
        },
      );
      expect(releaseWithPub.exitCode, 0, reason: '${releaseWithPub.stderr}');
      expect(arguments.readAsStringSync(), 'build\nappbundle\n--release\n');

      final ProcessResult debugWithPub = await runScript(
        'build_android.sh',
        <String>['debug-apk'],
        workingDirectory: Directory.systemTemp.path,
        environment: <String, String>{
          ...environment,
          'FLUTTER_BUILD_WITH_PUB': '1',
        },
      );
      expect(debugWithPub.exitCode, 0, reason: '${debugWithPub.stderr}');
      expect(arguments.readAsStringSync(), 'build\napk\n--debug\n--no-pub\n');

      final File debugArtifact = File(
        '${fixture.path}/build/app/outputs/flutter-apk/app-debug.apk',
      );
      await debugArtifact.delete();
      final ProcessResult missingArtifact = await runScript(
        'build_android.sh',
        <String>['debug-apk'],
        workingDirectory: Directory.systemTemp.path,
        environment: <String, String>{
          ...environment,
          'FAKE_FLUTTER_SKIP_ARTIFACT': '1',
        },
      );
      expect(missingArtifact.exitCode, 1);
      expect(missingArtifact.stderr, contains('expected artifact is missing'));
    },
  );

  test('iOS signed mode fails instead of silently downgrading', () async {
    final ProcessResult signed = await runScript('build_ios.sh', <String>[
      'signed-release',
    ]);
    expect(signed.exitCode, isNot(0));
    expect(signed.stderr, contains('no unsigned fallback is allowed'));
  });

  test('build workflow calls the checked-in platform scripts', () {
    final String workflow = File(
      '.github/workflows/build.yml',
    ).readAsStringSync();
    expect(workflow, contains('scripts/build_android.sh debug-apk'));
    expect(workflow, contains('scripts/build_ios.sh unsigned-debug'));
    expect(workflow, contains('scripts/**'));
    expect(workflow, contains('android/**'));
    expect(workflow, contains('ios/**'));
  });
}
