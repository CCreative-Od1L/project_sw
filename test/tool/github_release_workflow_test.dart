import 'dart:io';

import 'package:test/test.dart';

void main() {
  final RegExp pinnedDownload = RegExp(
    r'uses: actions/download-artifact@([0-9a-f]{40}) # v(\d+)\.\d+\.\d+',
  );

  test('release workflow publishes only verified Android artifacts', () {
    final String workflow = File(
      '.github/workflows/release.yml',
    ).readAsStringSync();
    final List<RegExpMatch> downloads = pinnedDownload
        .allMatches(workflow)
        .toList();

    expect(workflow, contains('needs: [metadata, android]'));
    expect(workflow, contains('actions: read'));
    expect(workflow, contains('contents: write'));
    expect(downloads, hasLength(2));
    expect(
      downloads.map((RegExpMatch match) => match.group(1)).toSet(),
      hasLength(1),
    );
    for (final RegExpMatch download in downloads) {
      expect(int.parse(download.group(2)!), greaterThanOrEqualTo(8));
    }
    expect(workflow, contains('name: Download release metadata'));
    expect(workflow, contains('path: release-assets/metadata'));
    expect(workflow, contains('name: Download signed Android AAB'));
    expect(workflow, contains('path: release-assets/android'));
    expect(workflow, contains('scripts/extract_changelog_section.sh'));
    expect(workflow, contains(r'GH_TOKEN: ${{ github.token }}'));
    expect(workflow, contains('gh release create'));
    expect(workflow, contains('--verify-tag'));
    expect(workflow, contains('release-assets/metadata/release-metadata.txt'));
    expect(workflow, contains('release-assets/android/app-release.aab'));
  });

  test('artifact compatibility check exercises the release download pin', () {
    final String release = File(
      '.github/workflows/release.yml',
    ).readAsStringSync();
    final String compatibility = File(
      '.github/workflows/artifact-download.yml',
    ).readAsStringSync();
    final List<String?> releasePins = pinnedDownload
        .allMatches(release)
        .map((RegExpMatch match) => match.group(1))
        .toList();
    final List<String?> checkedPins = pinnedDownload
        .allMatches(compatibility)
        .map((RegExpMatch match) => match.group(1))
        .toList();

    expect(checkedPins, hasLength(2));
    expect(checkedPins, releasePins);
    expect(compatibility, contains('contents: read'));
    expect(compatibility, isNot(contains('contents: write')));
    expect(compatibility, isNot(contains('gh release create')));
    expect(compatibility, isNot(contains('secrets.')));
    expect(
      compatibility,
      contains(
        'cmp expected/metadata/release-metadata.txt '
        'downloaded/metadata/release-metadata.txt',
      ),
    );
    expect(
      compatibility,
      contains(
        'cmp expected/android/app-release.aab downloaded/android/app-release.aab',
      ),
    );
  });
}
