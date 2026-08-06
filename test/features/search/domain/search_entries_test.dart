import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/search/domain/search_entries.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';

void main() {
  test('empty query preserves summaries while placing favorites first', () {
    final EntrySummary regular = _summary(
      id: 1,
      name: 'Regular',
      favorite: false,
    );
    final EntrySummary firstFavorite = _summary(
      id: 2,
      name: 'First favorite',
      favorite: true,
    );
    final EntrySummary secondFavorite = _summary(
      id: 3,
      name: 'Second favorite',
      favorite: true,
    );

    final List<EntrySummary> result = const SearchEntries()(<EntrySummary>[
      regular,
      firstFavorite,
      secondFavorite,
    ]);

    expect(result, <EntrySummary>[firstFavorite, secondFavorite, regular]);
  });

  test('matches name, URL, and username case-insensitively', () {
    final SearchEntries search = const SearchEntries();
    expect(
      search(<EntrySummary>[
        _summary(id: 1, name: 'Personal Mail'),
        _summary(id: 2, url: 'https://Example.test'),
        _summary(id: 3, username: 'Alice@example.test'),
      ], query: 'EXAMPLE').map((EntrySummary summary) => summary.entryId.last),
      <int>[2, 3],
    );
  });

  test('favorite-only filtering composes with the search query', () {
    final List<EntrySummary> result = const SearchEntries()(
      <EntrySummary>[
        _summary(id: 1, name: 'Favorite portal', favorite: true),
        _summary(id: 2, name: 'Regular portal'),
        _summary(id: 3, name: 'Favorite notes', favorite: true),
      ],
      query: 'portal',
      favoritesOnly: true,
    );

    expect(result.map((EntrySummary summary) => summary.name), <String>[
      'Favorite portal',
    ]);
  });

  test('detail-only password, notes, and custom fields cannot match', () {
    final VaultEntry detail = VaultEntry(
      entryId: Uint8List.fromList(List<int>.generate(16, (int i) => i)),
      name: 'Visible entry',
      url: 'https://visible.test',
      username: 'visible-user',
      password: 'detail-password',
      notes: 'private-notes',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      favorite: false,
      customFields: const <CustomField>[
        CustomField(
          label: 'private-label',
          value: 'custom-secret',
          secret: true,
        ),
      ],
    );

    final SearchEntries search = const SearchEntries();
    final EntrySummary summary = detail.toSummary();

    expect(search(<EntrySummary>[summary], query: 'detail-password'), isEmpty);
    expect(search(<EntrySummary>[summary], query: 'private-notes'), isEmpty);
    expect(search(<EntrySummary>[summary], query: 'custom-secret'), isEmpty);
    expect(search(<EntrySummary>[summary], query: 'visible'), <EntrySummary>[
      summary,
    ]);
  });
}

EntrySummary _summary({
  required int id,
  String name = '',
  String url = '',
  String username = '',
  bool favorite = false,
}) => EntrySummary(
  entryId: Uint8List.fromList(<int>[...List<int>.filled(15, 0), id]),
  name: name,
  url: url,
  username: username,
  favorite: favorite,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
