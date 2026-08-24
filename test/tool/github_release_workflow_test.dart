import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('release workflow publishes only verified Android artifacts', () {
    final String workflow = File(
      '.github/workflows/release.yml',
    ).readAsStringSync();

    expect(workflow, contains('needs: [metadata, android]'));
    expect(workflow, contains('actions: read'));
    expect(workflow, contains('contents: write'));
    expect(
      workflow,
      contains(
        'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093',
      ),
    );
    expect(workflow, contains('scripts/extract_changelog_section.sh'));
    expect(workflow, contains(r'GH_TOKEN: ${{ github.token }}'));
    expect(workflow, contains('gh release create'));
    expect(workflow, contains('--verify-tag'));
    expect(workflow, contains('release-assets/metadata/release-metadata.txt'));
    expect(workflow, contains('release-assets/android/app-release.aab'));
  });
}
