import 'dart:typed_data';

/// Creates the canonical byte encodings used as AEAD additional data.
abstract final class AadBuilder {
  /// Binds the KEK-wrapped MVK to the vault identity and KDF inputs.
  static Uint8List forWrapMvk({
    required Uint8List magic,
    required int formatVersion,
    required int kdfAlgorithmId,
    required Uint8List kdfParameters,
    required Uint8List kdfSalt,
  }) {
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(magic)
      ..add(_uint16(formatVersion))
      ..addByte(kdfAlgorithmId)
      ..add(kdfParameters)
      ..add(kdfSalt);
    return builder.toBytes();
  }

  /// Binds the biometric-wrapped MVK to this vault format and purpose.
  static Uint8List forWrapBiometricMvk({
    required Uint8List magic,
    required int formatVersion,
    required int aeadAlgorithmId,
  }) {
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(magic)
      ..add(_uint16(formatVersion))
      ..addByte(aeadAlgorithmId)
      ..add(<int>[0x62, 0x69, 0x6f, 0x2d, 0x6d, 0x76, 0x6b]);
    return builder.toBytes();
  }

  /// Binds an MVK-wrapped DEK to its stable EntryRecord identity.
  static Uint8List forWrapDek({
    required Uint8List magic,
    required int formatVersion,
    required int aeadAlgorithmId,
    required Uint8List entryId,
  }) {
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(magic)
      ..add(_uint16(formatVersion))
      ..addByte(aeadAlgorithmId)
      ..add(entryId);
    return builder.toBytes();
  }

  /// Binds encrypted entry plaintext to identity and its monotonic revision.
  static Uint8List forEncryptEntry({
    required Uint8List magic,
    required int formatVersion,
    required int aeadAlgorithmId,
    required Uint8List entryId,
    required int sequence,
  }) {
    final Uint8List sequenceBytes = (ByteData(
      8,
    )..setUint64(0, sequence, Endian.big)).buffer.asUint8List();
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(magic)
      ..add(_uint16(formatVersion))
      ..addByte(aeadAlgorithmId)
      ..add(entryId)
      ..add(sequenceBytes);
    return builder.toBytes();
  }

  static Uint8List _uint16(int value) {
    final ByteData data = ByteData(2)..setUint16(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}
