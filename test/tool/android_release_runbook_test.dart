import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android release runbook matches the checked-in release contract', () {
    final String runbook = File('docs/RELEASE_RUNBOOK.md').readAsStringSync();

    expect(runbook, contains('Android-only'));
    expect(runbook, contains('ANDROID_KEYSTORE_BASE64'));
    expect(runbook, contains('ANDROID_KEY_ALIAS'));
    expect(runbook, contains('ANDROID_KEYSTORE_PASSWORD'));
    expect(runbook, contains('ANDROID_KEY_PASSWORD'));
    expect(runbook, contains('release environment'));
    expect(runbook, contains('release-metadata.txt'));
    expect(runbook, contains('app-release.aab'));
    expect(runbook, contains('git tag -a vX.Y.Z'));
    expect(runbook, isNot(contains('IOS_CERTIFICATE')));
  });
}
