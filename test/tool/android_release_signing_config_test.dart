import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('release signing never falls back to the debug key', () {
    final String gradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, contains('validateReleaseSigning'));
    expect(gradle, contains('ANDROID_KEYSTORE_PATH'));
    expect(gradle, contains('ANDROID_KEY_ALIAS'));
    expect(gradle, contains('ANDROID_KEYSTORE_PASSWORD'));
    expect(gradle, contains('ANDROID_KEY_PASSWORD'));
  });

  test('signing material extensions are ignored by git', () {
    final String gitignore = File('.gitignore').readAsStringSync();

    for (final String extension in <String>[
      '*.keystore',
      '*.jks',
      '*.p12',
      '*.p8',
      '*.mobileprovision',
    ]) {
      expect(gitignore, contains(extension));
    }
  });
}
