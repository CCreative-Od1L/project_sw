import 'dart:convert';
import 'dart:typed_data';

import 'package:project_sw/features/vault/domain/vault_entry.dart';

/// Hand-written, tolerant JSON codec for encrypted VaultEntry plaintext.
abstract final class VaultEntryJsonCodec {
  /// Encodes all complete-entry fields before entry-ciphertext encryption.
  static Uint8List encode(VaultEntry entry) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object>{
          'entry_id': _hex(entry.entryId),
          'name': entry.name,
          'url': entry.url,
          'username': entry.username,
          'password': entry.password,
          'notes': entry.notes,
          'created_at': entry.createdAt.toUtc().toIso8601String(),
          'updated_at': entry.updatedAt.toUtc().toIso8601String(),
          'favorite': entry.favorite,
          'custom_fields': entry.customFields
              .map(
                (CustomField field) => <String, Object>{
                  'label': field.label,
                  'value': field.value,
                  'secret': field.secret,
                },
              )
              .toList(growable: false),
        }),
      ),
    );
  }

  /// Decodes known fields while defaulting fields absent from older plaintext.
  static VaultEntry decode(Uint8List bytes, {required Uint8List entryId}) {
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException(
        'VaultEntry plaintext must be a JSON object.',
      );
    }
    final String? embeddedId = decoded['entry_id'] as String?;
    if (embeddedId != null && !_sameBytes(_fromHex(embeddedId), entryId)) {
      throw const FormatException(
        'VaultEntry identity does not match its record.',
      );
    }
    final List<CustomField> customFields = <CustomField>[];
    final Object? rawFields = decoded['custom_fields'];
    if (rawFields is List<Object?>) {
      for (final Object? raw in rawFields) {
        if (raw is Map<Object?, Object?>) {
          customFields.add(
            CustomField(
              label: raw['label'] as String? ?? '',
              value: raw['value'] as String? ?? '',
              secret: raw['secret'] as bool? ?? false,
            ),
          );
        }
      }
    }
    return VaultEntry(
      entryId: entryId,
      name: decoded['name'] as String? ?? '',
      url: decoded['url'] as String? ?? '',
      username: decoded['username'] as String? ?? '',
      password: decoded['password'] as String? ?? '',
      notes: decoded['notes'] as String? ?? '',
      createdAt: _dateOrEpoch(decoded['created_at']),
      updatedAt: _dateOrEpoch(decoded['updated_at']),
      favorite: decoded['favorite'] as bool? ?? false,
      customFields: customFields,
    );
  }

  static DateTime _dateOrEpoch(Object? value) =>
      DateTime.tryParse(value as String? ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static String _hex(Uint8List bytes) =>
      bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _fromHex(String value) {
    if (value.length != 32) {
      throw const FormatException('VaultEntry identity has an invalid length.');
    }
    final Uint8List bytes = Uint8List(16);
    for (var index = 0; index < bytes.length; index++) {
      final int? valueAtByte = int.tryParse(
        value.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
      if (valueAtByte == null) {
        throw const FormatException('VaultEntry identity is not hexadecimal.');
      }
      bytes[index] = valueAtByte;
    }
    return bytes;
  }

  static bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}
