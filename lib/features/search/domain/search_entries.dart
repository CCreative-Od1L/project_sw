import 'package:project_sw/features/vault/domain/vault_entry.dart';

/// Filters only the safe, in-memory [EntrySummary] projection.
final class SearchEntries {
  /// Creates the stateless local search operation.
  const SearchEntries();

  /// Returns matching summaries with favorites first, preserving list order.
  List<EntrySummary> call(
    Iterable<EntrySummary> summaries, {
    String query = '',
    bool favoritesOnly = false,
  }) {
    final String normalizedQuery = query.trim().toLowerCase();
    final List<EntrySummary> matching = summaries
        .where(
          (EntrySummary summary) =>
              (!favoritesOnly || summary.favorite) &&
              _matches(summary, normalizedQuery),
        )
        .toList();

    return <EntrySummary>[
      for (final EntrySummary summary in matching)
        if (summary.favorite) summary,
      for (final EntrySummary summary in matching)
        if (!summary.favorite) summary,
    ];
  }

  bool _matches(EntrySummary summary, String query) {
    if (query.isEmpty) return true;
    return summary.name.toLowerCase().contains(query) ||
        summary.url.toLowerCase().contains(query) ||
        summary.username.toLowerCase().contains(query);
  }
}
