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

  static Uint8List _uint16(int value) {
    final ByteData data = ByteData(2)..setUint16(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}
