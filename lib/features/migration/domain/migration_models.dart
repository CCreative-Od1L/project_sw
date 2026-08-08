import 'dart:convert';
import 'dart:typed_data';

import 'migration_exception.dart';

/// The only role allowed to publish a QR pairing payload.
enum MigrationPairingRole {
  /// The device that will send encrypted entry records.
  sender,
}

/// Out-of-band connection information shown as a short-lived QR payload.
final class MigrationPairingPayload {
  /// Creates and validates a sender pairing payload.
  MigrationPairingPayload({
    required this.host,
    required this.port,
    required Uint8List senderPublicKey,
    required this.issuedAtEpochSeconds,
    required this.expiresAtEpochSeconds,
  }) : senderPublicKey = Uint8List.fromList(senderPublicKey) {
    _validate();
  }

  /// Creates a payload with an explicit short validity window.
  factory MigrationPairingPayload.issue({
    required String host,
    required int port,
    required Uint8List senderPublicKey,
    DateTime? issuedAt,
    Duration ttl = const Duration(minutes: 5),
  }) {
    final DateTime now = (issuedAt ?? DateTime.now()).toUtc();
    return MigrationPairingPayload(
      host: host,
      port: port,
      senderPublicKey: senderPublicKey,
      issuedAtEpochSeconds: now.millisecondsSinceEpoch ~/ 1000,
      expiresAtEpochSeconds: now.add(ttl).millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// The current QR payload schema version.
  static const int protocolVersion = 1;

  /// The sender's literal IP address or local network hostname.
  final String host;

  /// Temporary TCP listening port.
  final int port;

  /// One-time sender X25519 public key.
  final Uint8List senderPublicKey;

  /// Creation time in UTC Unix seconds.
  final int issuedAtEpochSeconds;

  /// Expiration time in UTC Unix seconds.
  final int expiresAtEpochSeconds;

  /// Whether the payload is no longer valid at [now].
  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000 >=
      expiresAtEpochSeconds;

  /// Serializes the payload without including any private key material.
  String encode() => jsonEncode(<String, Object>{
    'v': protocolVersion,
    'role': MigrationPairingRole.sender.name,
    'host': host,
    'port': port,
    'pk_sender': base64Url.encode(senderPublicKey),
    'issued_at': issuedAtEpochSeconds,
    'expires_at': expiresAtEpochSeconds,
  });

  /// Parses and validates a QR payload, including its expiration window.
  factory MigrationPairingPayload.decode(String encoded, {DateTime? now}) {
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final Map<String, dynamic> object = decoded;
      final Object? version = object['v'];
      final Object? role = object['role'];
      if (version != protocolVersion ||
          role != MigrationPairingRole.sender.name) {
        throw const FormatException();
      }
      final String host = _requiredString(object, 'host');
      final int port = _requiredInt(object, 'port');
      final int issuedAt = _requiredInt(object, 'issued_at');
      final int expiresAt = _requiredInt(object, 'expires_at');
      final String encodedPublicKey = _requiredString(object, 'pk_sender');
      final Uint8List publicKey = Uint8List.fromList(
        base64Url.decode(_withBase64Padding(encodedPublicKey)),
      );
      final MigrationPairingPayload payload = MigrationPairingPayload(
        host: host,
        port: port,
        senderPublicKey: publicKey,
        issuedAtEpochSeconds: issuedAt,
        expiresAtEpochSeconds: expiresAt,
      );
      if (payload.isExpired(now)) {
        throw const MigrationProtocolException(
          MigrationErrorCode.expired,
          'The pairing payload has expired.',
        );
      }
      return payload;
    } on MigrationProtocolException {
      rethrow;
    } on Object {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The pairing payload is malformed.',
      );
    }
  }

  void _validate() {
    if (host.isEmpty || host.trim() != host || host.contains(RegExp(r'\s'))) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The pairing address is invalid.',
      );
    }
    if (port < 1 || port > 65535) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The pairing port is invalid.',
      );
    }
    if (senderPublicKey.length != 32) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The pairing public key is invalid.',
      );
    }
    if (expiresAtEpochSeconds <= issuedAtEpochSeconds) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The pairing validity window is invalid.',
      );
    }
  }
}

/// Format and algorithm capabilities exchanged before any entry transfer.
final class MigrationCapabilities {
  /// Creates a validated immutable capability set.
  MigrationCapabilities({
    required this.formatVersion,
    required this.aeadAlgorithmId,
    required Iterable<int> supportedPlaintextFormatIds,
  }) : supportedPlaintextFormatIds = _normalizeFormatIds(
         supportedPlaintextFormatIds,
       );

  /// Vault container format version.
  final int formatVersion;

  /// AEAD algorithm identifier used by the vault format.
  final int aeadAlgorithmId;

  /// Inner plaintext formats this endpoint can read and write.
  final List<int> supportedPlaintextFormatIds;

  /// Selects a mutually supported capability or throws before transfer.
  int negotiateWith(MigrationCapabilities other) {
    if (formatVersion != other.formatVersion ||
        aeadAlgorithmId != other.aeadAlgorithmId) {
      throw const MigrationProtocolException(
        MigrationErrorCode.incompatible,
        'The vault format or encryption algorithm is incompatible.',
      );
    }
    for (final int formatId in supportedPlaintextFormatIds) {
      if (other.supportedPlaintextFormatIds.contains(formatId)) {
        return formatId;
      }
    }
    throw const MigrationProtocolException(
      MigrationErrorCode.incompatible,
      'No plaintext format is supported by both endpoints.',
    );
  }

  static List<int> _normalizeFormatIds(Iterable<int> ids) {
    final List<int> normalized = ids.toSet().toList()..sort();
    if (normalized.isEmpty || normalized.any((int id) => id < 0 || id > 255)) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The plaintext format capability set is invalid.',
      );
    }
    return List<int>.unmodifiable(normalized);
  }
}

String _requiredString(Map<String, dynamic> object, String key) {
  final Object? value = object[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException();
  }
  return value;
}

int _requiredInt(Map<String, dynamic> object, String key) {
  final Object? value = object[key];
  if (value is! int) {
    throw const FormatException();
  }
  return value;
}

String _withBase64Padding(String value) {
  final int padding = (4 - value.length % 4) % 4;
  return '$value${'=' * padding}';
}
