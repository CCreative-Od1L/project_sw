import 'dart:typed_data';

/// User-supplied fields for a new complete VaultEntry.
final class NewVaultEntry {
  /// Creates a new entry request without assigning its CSPRNG entry identity.
  const NewVaultEntry({
    required this.name,
    this.url = '',
    this.username = '',
    this.password = '',
    this.notes = '',
    this.favorite = false,
    this.customFields = const <CustomField>[],
  });

  /// Required, user-visible entry label.
  final String name;

  /// Optional service URL.
  final String url;

  /// Optional login username.
  final String username;

  /// Optional sensitive password.
  final String password;

  /// Optional sensitive notes.
  final String notes;

  /// Whether this entry is pinned in the summary list.
  final bool favorite;

  /// Detail-only custom fields.
  final List<CustomField> customFields;
}

/// One detail-only extension field of a complete VaultEntry.
final class CustomField {
  /// Creates an immutable custom field.
  const CustomField({
    required this.label,
    required this.value,
    required this.secret,
  });

  /// User-visible label.
  final String label;

  /// Detail-only value, never copied into EntrySummary.
  final String value;

  /// Whether the value receives password-level UI hygiene.
  final bool secret;
}

/// The complete plaintext entity that exists only during encryption/decryption.
final class VaultEntry {
  /// Creates a complete VaultEntry with a stable CSPRNG identity.
  VaultEntry({
    required Uint8List entryId,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.favorite,
    required List<CustomField> customFields,
  }) : entryId = Uint8List.fromList(entryId),
       customFields = List<CustomField>.unmodifiable(customFields) {
    if (this.entryId.length != 16) {
      throw ArgumentError.value(entryId, 'entryId', 'must be 16 bytes');
    }
  }

  /// CSPRNG identity also held by the EntryRecord.
  final Uint8List entryId;

  /// Required entry label.
  final String name;

  /// Optional service URL.
  final String url;

  /// Optional username.
  final String username;

  /// Sensitive password; detail-only after decoding.
  final String password;

  /// Sensitive notes; detail-only after decoding.
  final String notes;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC modification timestamp.
  final DateTime updatedAt;

  /// Non-sensitive list pin.
  final bool favorite;

  /// Detail-only custom fields.
  final List<CustomField> customFields;

  /// Extracts exactly the fields permitted in unlocked global residency.
  EntrySummary toSummary() => EntrySummary(
    entryId: entryId,
    name: name,
    url: url,
    username: username,
    favorite: favorite,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// The only entry model permitted to remain globally resident while unlocked.
final class EntrySummary {
  /// Creates the limited, non-secret list projection.
  EntrySummary({
    required Uint8List entryId,
    required this.name,
    required this.url,
    required this.username,
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
  }) : entryId = Uint8List.fromList(entryId) {
    if (this.entryId.length != 16) {
      throw ArgumentError.value(entryId, 'entryId', 'must be 16 bytes');
    }
  }

  /// Stable opaque entry identity.
  final Uint8List entryId;

  /// List-visible name.
  final String name;

  /// List-visible URL.
  final String url;

  /// List-visible username.
  final String username;

  /// List-visible favorite flag.
  final bool favorite;

  /// List-visible creation timestamp.
  final DateTime createdAt;

  /// List-visible modification timestamp.
  final DateTime updatedAt;
}
