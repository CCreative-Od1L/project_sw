import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'release workflow wires Android signing through the fail-closed seam',
    () {
      final String workflow = File(
        '.github/workflows/release.yml',
      ).readAsStringSync();

      expect(workflow, contains('needs: metadata'));
      expect(workflow, contains('environment: release'));
      expect(workflow, contains('scripts/prepare_android_signing.sh'));
      expect(workflow, contains('scripts/build_android.sh release-aab'));
      expect(workflow, contains(r'ANDROID_KEYSTORE_BASE64: ${{ secrets.'));
      expect(workflow, contains(r'ANDROID_KEY_ALIAS: ${{ secrets.'));
      expect(workflow, contains(r'ANDROID_KEYSTORE_PASSWORD: ${{ secrets.'));
      expect(workflow, contains(r'ANDROID_KEY_PASSWORD: ${{ secrets.'));
      expect(
        workflow,
        contains(r'${{ runner.temp }}/project-sw-release.keystore'),
      );
      expect(workflow, contains(r'if: ${{ always() }}'));
      expect(workflow, contains('if-no-files-found: error'));
      expect(workflow, contains('permissions:\n  contents: read'));
      expect(
        workflow,
        contains('permissions:\n      actions: read\n      contents: write'),
      );
      expect(workflow, isNot(contains('build_ios.sh')));
    },
  );
}
