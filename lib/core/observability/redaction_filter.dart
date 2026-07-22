/// Removes sensitive values from structured logging context.
final class RedactionFilter {
  /// Creates the redaction filter.
  const RedactionFilter();

  static const Set<String> _sensitiveKeys = <String>{
    'password',
    'key',
    'mvk',
    'kek',
    'dek',
    'k_bio',
    'secret',
    'master_password',
    'wrapped_key',
    'plaintext',
    'entry_ciphertext',
  };

  /// Returns a copy of [context] with sensitive keys replaced by a marker.
  Map<String, dynamic> redact(Map<String, dynamic>? context) {
    if (context == null) {
      return <String, dynamic>{};
    }

    return context.map((String key, dynamic value) {
      final String normalizedKey = _normalize(key);
      final bool isSensitive = _sensitiveKeys.any(
        (String sensitiveKey) =>
            normalizedKey.contains(_normalize(sensitiveKey)),
      );
      return MapEntry<String, dynamic>(key, isSensitive ? '[REDACTED]' : value);
    });
  }

  static String _normalize(String key) {
    return key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  }
}
