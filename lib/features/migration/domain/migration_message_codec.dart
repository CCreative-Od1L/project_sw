import 'dart:convert';
import 'dart:typed_data';

import 'migration_exception.dart';
import 'migration_models.dart';
import 'migration_transfer.dart';

/// Encodes the capability preflight exchanged inside an authenticated session.
abstract final class MigrationPreflightCodec {
  /// Serializes format and algorithm capabilities without key material.
  static Uint8List encode(MigrationCapabilities capabilities) =>
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object>{
            'format_version': capabilities.formatVersion,
            'aead_algorithm_id': capabilities.aeadAlgorithmId,
            'plaintext_format_ids': capabilities.supportedPlaintextFormatIds,
          }),
        ),
      );

  /// Parses a strict preflight payload before any entry is accepted.
  static MigrationCapabilities decode(Uint8List encoded) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(encoded));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final Object? formatVersion = decoded['format_version'];
      final Object? aeadAlgorithmId = decoded['aead_algorithm_id'];
      final Object? formats = decoded['plaintext_format_ids'];
      if (formatVersion is! int ||
          aeadAlgorithmId is! int ||
          formats is! List<dynamic> ||
          formats.any((Object? value) => value is! int)) {
        throw const FormatException();
      }
      return MigrationCapabilities(
        formatVersion: formatVersion,
        aeadAlgorithmId: aeadAlgorithmId,
        supportedPlaintextFormatIds: formats.cast<int>(),
      );
    } on MigrationProtocolException {
      rethrow;
    } on Object {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The migration preflight is malformed.',
      );
    }
  }
}

/// Encodes an entry payload before it is passed to the session AEAD.
abstract final class MigrationEntryPayloadCodec {
  /// Binary payload header size before ciphertext and DEK bytes.
  static const int _headerLength = 16 + 8 + 1 + 4;

  /// Serializes the DEK and raw entry ciphertext for session encryption.
  static Uint8List encode(MigrationEntryPayload payload) {
    final ByteData sequenceData = ByteData(8)
      ..setUint64(0, payload.sequence, Endian.big);
    final ByteData lengthData = ByteData(4)
      ..setUint32(0, payload.entryCiphertext.length, Endian.big);
    return Uint8List.fromList(<int>[
      ...payload.entryId,
      ...sequenceData.buffer.asUint8List(),
      payload.plaintextFormatId,
      ...lengthData.buffer.asUint8List(),
      ...payload.entryCiphertext,
      ...payload.dek,
    ]);
  }

  /// Parses and validates one decrypted entry payload.
  static MigrationEntryPayload decode(Uint8List encoded) {
    if (encoded.length < _headerLength + 40 + 32) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The migration entry payload is too short.',
      );
    }
    final ByteData data = ByteData.sublistView(encoded);
    final int ciphertextLength = data.getUint32(25, Endian.big);
    if (ciphertextLength < 40 ||
        encoded.length != _headerLength + ciphertextLength + 32) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The migration entry payload length is invalid.',
      );
    }
    try {
      return MigrationEntryPayload(
        entryId: Uint8List.fromList(encoded.sublist(0, 16)),
        sequence: data.getUint64(16, Endian.big),
        plaintextFormatId: data.getUint8(24),
        entryCiphertext: Uint8List.fromList(
          encoded.sublist(_headerLength, _headerLength + ciphertextLength),
        ),
        dek: Uint8List.fromList(
          encoded.sublist(_headerLength + ciphertextLength),
        ),
      );
    } on ArgumentError {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The migration entry payload fields are invalid.',
      );
    }
  }
}

/// Encodes and validates the final transcript MAC payload.
abstract final class MigrationTransferEndCodec {
  /// The fixed transcript MAC size.
  static const int macLength = 32;

  /// Copies a transcript MAC into its transport payload.
  static Uint8List encode(Uint8List transcriptMac) {
    if (transcriptMac.length != macLength) {
      throw const MigrationProtocolException(
        MigrationErrorCode.transcriptMismatch,
        'The migration transcript MAC has an invalid length.',
      );
    }
    return Uint8List.fromList(transcriptMac);
  }

  /// Decodes a fixed-size transcript MAC.
  static Uint8List decode(Uint8List encoded) {
    if (encoded.length != macLength) {
      throw const MigrationProtocolException(
        MigrationErrorCode.transcriptMismatch,
        'The migration transcript MAC has an invalid length.',
      );
    }
    return Uint8List.fromList(encoded);
  }
}
