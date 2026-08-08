import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';

import 'migration_exception.dart';

/// Message types carried by an authenticated migration session.
enum MigrationMessageType {
  /// Capability exchange before entry transfer.
  preflight,

  /// One encrypted entry transfer payload.
  entry,

  /// Final message carrying the transcript MAC.
  transferEnd,
}

/// Maps migration message types to their stable wire representation.
extension MigrationMessageTypeWire on MigrationMessageType {
  /// Stable numeric value used in the binary frame header.
  int get wireValue => switch (this) {
    MigrationMessageType.preflight => 1,
    MigrationMessageType.entry => 2,
    MigrationMessageType.transferEnd => 3,
  };

  /// Decodes the stable wire value of a message type.
  static MigrationMessageType fromWireValue(int value) => switch (value) {
    1 => MigrationMessageType.preflight,
    2 => MigrationMessageType.entry,
    3 => MigrationMessageType.transferEnd,
    _ => throw const MigrationProtocolException(
      MigrationErrorCode.malformed,
      'The migration message type is invalid.',
    ),
  };
}

/// An authenticated session frame ready for transport over TCP.
final class MigrationSessionFrame {
  /// Creates a validated frame and copies all byte buffers.
  MigrationSessionFrame({
    required this.type,
    required this.sequence,
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) : nonce = Uint8List.fromList(nonce),
       ciphertext = Uint8List.fromList(ciphertext) {
    if (sequence < 0 ||
        this.nonce.length != 24 ||
        this.ciphertext.length < 16) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The migration frame is invalid.',
      );
    }
  }

  /// Binary frame magic and version prefix.
  static const List<int> _magic = <int>[0x4d, 0x47, 0x01];

  /// Frame message kind.
  final MigrationMessageType type;

  /// Monotonic sequence number scoped to this session direction.
  final int sequence;

  /// XChaCha20 nonce.
  final Uint8List nonce;

  /// Ciphertext with its authentication tag.
  final Uint8List ciphertext;

  /// Clears the frame's nonce and ciphertext after transport use.
  void dispose() {
    clearSensitiveBytes(nonce);
    clearSensitiveBytes(ciphertext);
  }

  /// Encodes a frame with a length-delimited ciphertext body.
  Uint8List encode() {
    final ByteData sequenceData = ByteData(8)
      ..setUint64(0, sequence, Endian.big);
    final ByteData lengthData = ByteData(4)
      ..setUint32(0, ciphertext.length, Endian.big);
    return Uint8List.fromList(<int>[
      ..._magic,
      type.wireValue,
      ...sequenceData.buffer.asUint8List(),
      ...nonce,
      ...lengthData.buffer.asUint8List(),
      ...ciphertext,
    ]);
  }

  /// Decodes and validates one complete frame; trailing bytes are rejected.
  static MigrationSessionFrame decode(Uint8List encoded) {
    const int fixedLength = 3 + 1 + 8 + 24 + 4;
    if (encoded.length < fixedLength + 16 ||
        encoded[0] != _magic[0] ||
        encoded[1] != _magic[1] ||
        encoded[2] != _magic[2]) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The migration frame is malformed.',
      );
    }
    final ByteData data = ByteData.sublistView(encoded);
    final MigrationMessageType type = MigrationMessageTypeWire.fromWireValue(
      data.getUint8(3),
    );
    final int sequence = data.getUint64(4, Endian.big);
    final Uint8List nonce = Uint8List.fromList(encoded.sublist(12, 36));
    final int ciphertextLength = data.getUint32(36, Endian.big);
    if (ciphertextLength != encoded.length - fixedLength) {
      throw const MigrationProtocolException(
        MigrationErrorCode.malformed,
        'The migration frame length is invalid.',
      );
    }
    return MigrationSessionFrame(
      type: type,
      sequence: sequence,
      nonce: nonce,
      ciphertext: Uint8List.fromList(encoded.sublist(fixedLength)),
    );
  }

  /// Constructs the AEAD AAD bound to frame metadata.
  static Uint8List additionalData(MigrationMessageType type, int sequence) {
    final ByteData sequenceData = ByteData(8)
      ..setUint64(0, sequence, Endian.big);
    return Uint8List.fromList(<int>[
      ..._magic,
      type.wireValue,
      ...sequenceData.buffer.asUint8List(),
    ]);
  }
}

/// State machine for one directional, AEAD-protected migration stream.
final class MigrationSession {
  /// Establishes the client side of a crypto_kx session.
  static MigrationSession establishClient({
    required CryptoService crypto,
    required EphemeralKeyPair localIdentity,
    required Uint8List remotePublicKey,
  }) {
    DirectionalSessionKeys? keys;
    try {
      keys = crypto.deriveClientSessionKeys(
        clientPublicKey: localIdentity.publicKey,
        clientSecretKey: localIdentity.secretKey,
        serverPublicKey: remotePublicKey,
      );
      return MigrationSession.fromKeys(crypto, keys: keys);
    } finally {
      keys?.dispose();
      localIdentity.dispose();
    }
  }

  /// Establishes the server side of a crypto_kx session.
  static MigrationSession establishServer({
    required CryptoService crypto,
    required EphemeralKeyPair localIdentity,
    required Uint8List remotePublicKey,
  }) {
    DirectionalSessionKeys? keys;
    try {
      keys = crypto.deriveServerSessionKeys(
        serverPublicKey: localIdentity.publicKey,
        serverSecretKey: localIdentity.secretKey,
        clientPublicKey: remotePublicKey,
      );
      return MigrationSession.fromKeys(crypto, keys: keys);
    } finally {
      keys?.dispose();
      localIdentity.dispose();
    }
  }

  /// Creates a session from already-derived directional keys.
  MigrationSession.fromKeys(
    this._crypto, {
    required DirectionalSessionKeys keys,
  }) : _txKey = Uint8List.fromList(keys.tx),
       _rxKey = Uint8List.fromList(keys.rx);

  final CryptoService _crypto;
  final Uint8List _txKey;
  final Uint8List _rxKey;
  final BytesBuilder _transcript = BytesBuilder(copy: false);
  int _nextSendSequence = 0;
  int _nextReceiveSequence = 0;
  bool _finalized = false;
  bool _disposed = false;

  /// Encrypts one message and advances the sending sequence only on success.
  MigrationSessionFrame seal(MigrationMessageType type, Uint8List plaintext) {
    _ensureUsable();
    return _sealFrame(type, plaintext, includeInTranscript: true);
  }

  /// Encrypts the final transfer frame after MAC-ing all preceding frames.
  ///
  /// The final frame advances the transport sequence but is deliberately not
  /// included in the transcript it carries. The receiver must use
  /// [openTransferEnd] followed by [verifyTranscriptMac].
  MigrationSessionFrame sealTransferEnd() {
    _ensureUsable();
    final Uint8List transcriptMac = _finalize(_txKey);
    try {
      return _sealFrame(
        MigrationMessageType.transferEnd,
        transcriptMac,
        includeInTranscript: false,
      );
    } finally {
      clearSensitiveBytes(transcriptMac);
    }
  }

  MigrationSessionFrame _sealFrame(
    MigrationMessageType type,
    Uint8List plaintext, {
    required bool includeInTranscript,
  }) {
    final int sequence = _nextSendSequence;
    final Uint8List aad = MigrationSessionFrame.additionalData(type, sequence);
    AeadCiphertext? encrypted;
    try {
      encrypted = _crypto.encryptWithAead(_txKey, plaintext, aad);
      final MigrationSessionFrame frame = MigrationSessionFrame(
        type: type,
        sequence: sequence,
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
      );
      if (includeInTranscript) {
        _appendTranscript(frame);
      }
      _nextSendSequence++;
      return frame;
    } finally {
      clearSensitiveBytes(aad);
      if (encrypted != null) {
        clearSensitiveBytes(encrypted.nonce);
        clearSensitiveBytes(encrypted.ciphertext);
      }
    }
  }

  /// Decrypts one frame, rejecting replay, loss, reordering, or tampering.
  Uint8List open(MigrationSessionFrame frame) {
    _ensureUsable();
    return _openFrame(frame, includeInTranscript: true);
  }

  /// Opens the final frame without adding it to the preceding transcript.
  Uint8List openTransferEnd(MigrationSessionFrame frame) {
    _ensureUsable();
    if (frame.type != MigrationMessageType.transferEnd) {
      throw const MigrationProtocolException(
        MigrationErrorCode.invalidState,
        'The migration frame is not a transfer end.',
      );
    }
    return _openFrame(frame, includeInTranscript: false);
  }

  Uint8List _openFrame(
    MigrationSessionFrame frame, {
    required bool includeInTranscript,
  }) {
    if (frame.sequence != _nextReceiveSequence) {
      throw const MigrationProtocolException(
        MigrationErrorCode.sequenceMismatch,
        'The migration frame sequence is invalid.',
      );
    }
    final Uint8List aad = MigrationSessionFrame.additionalData(
      frame.type,
      frame.sequence,
    );
    try {
      final Uint8List plaintext = _crypto.decryptWithAead(
        _rxKey,
        frame.nonce,
        frame.ciphertext,
        aad,
      );
      if (includeInTranscript) {
        _appendTranscript(frame);
      }
      _nextReceiveSequence++;
      return plaintext;
    } on MigrationProtocolException {
      rethrow;
    } on Object {
      throw const MigrationProtocolException(
        MigrationErrorCode.authenticationFailed,
        'The migration frame could not be authenticated.',
      );
    } finally {
      clearSensitiveBytes(aad);
    }
  }

  /// Creates the final MAC for frames sent by this endpoint.
  Uint8List createTranscriptMac() {
    _ensureUsable();
    return _finalize(_txKey);
  }

  /// Verifies the final MAC received from the peer.
  void verifyTranscriptMac(Uint8List receivedMac) {
    _ensureUsable();
    if (receivedMac.length != 32) {
      throw const MigrationProtocolException(
        MigrationErrorCode.transcriptMismatch,
        'The migration transcript MAC is invalid.',
      );
    }
    final Uint8List expected = _finalize(_rxKey);
    try {
      if (!_constantTimeEquals(expected, receivedMac)) {
        throw const MigrationProtocolException(
          MigrationErrorCode.transcriptMismatch,
          'The migration transcript MAC does not match.',
        );
      }
    } finally {
      clearSensitiveBytes(expected);
    }
  }

  /// Clears session keys and transcript state.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    clearSensitiveBytes(_txKey);
    clearSensitiveBytes(_rxKey);
    clearSensitiveBytes(_transcript.takeBytes());
  }

  void _appendTranscript(MigrationSessionFrame frame) {
    final ByteData sequenceData = ByteData(8)
      ..setUint64(0, frame.sequence, Endian.big);
    _transcript
      ..add(sequenceData.buffer.asUint8List())
      ..add(frame.ciphertext);
  }

  Uint8List _finalize(Uint8List macKey) {
    if (_finalized) {
      throw const MigrationProtocolException(
        MigrationErrorCode.invalidState,
        'The migration transcript is already finalized.',
      );
    }
    _finalized = true;
    final Uint8List transcript = _transcript.takeBytes();
    Uint8List? digest;
    try {
      digest = _crypto.hash(transcript);
      return _crypto.mac(macKey, digest);
    } finally {
      clearSensitiveBytes(transcript);
      if (digest != null) {
        clearSensitiveBytes(digest);
      }
    }
  }

  void _ensureUsable() {
    if (_disposed || _finalized) {
      throw const MigrationProtocolException(
        MigrationErrorCode.invalidState,
        'The migration session is no longer active.',
      );
    }
  }

  bool _constantTimeEquals(Uint8List left, Uint8List right) {
    var difference = left.length ^ right.length;
    final int length = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
