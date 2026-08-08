import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:project_sw/features/migration/domain/migration_session.dart';

/// Safe transport failure that does not include network payload contents.
final class MigrationTransportException implements Exception {
  /// Creates a network transport error.
  const MigrationTransportException(this.message, {this.cause});

  /// User-safe diagnostic.
  final String message;

  /// Underlying socket failure for logging and tests.
  final Object? cause;

  @override
  String toString() => 'MigrationTransportException: $message';
}

/// Minimal frame transport consumed by the migration coordinator.
abstract interface class MigrationFrameTransport {
  /// Sends one complete authenticated frame.
  Future<void> send(MigrationSessionFrame frame);

  /// Receives one complete authenticated frame.
  Future<MigrationSessionFrame> receive();

  /// Closes the transport.
  Future<void> close();
}

/// Length-prefixed TCP transport for authenticated migration frames.
final class MigrationSocketTransport implements MigrationFrameTransport {
  MigrationSocketTransport._(this._socket, this._timeout)
    : _chunks = StreamIterator<Uint8List>(_socket);

  /// Maximum frame body accepted before allocating a receive buffer.
  static const int maxFrameLength = 16 * 1024 * 1024;

  final Socket _socket;
  final Duration _timeout;
  final StreamIterator<Uint8List> _chunks;
  Uint8List? _pendingChunk;
  var _pendingOffset = 0;
  var _closed = false;

  /// Connects to a temporary migration listener.
  static Future<MigrationSocketTransport> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final Socket socket = await Socket.connect(host, port, timeout: timeout);
      return MigrationSocketTransport._(socket, timeout);
    } on Object catch (error) {
      throw MigrationTransportException(
        'The migration connection could not be established.',
        cause: error,
      );
    }
  }

  /// Sends one complete length-prefixed frame.
  @override
  Future<void> send(MigrationSessionFrame frame) async {
    _ensureOpen();
    final Uint8List encoded = frame.encode();
    if (encoded.length > maxFrameLength) {
      throw const MigrationTransportException(
        'The migration frame is too large.',
      );
    }
    final ByteData length = ByteData(4)
      ..setUint32(0, encoded.length, Endian.big);
    try {
      _socket
        ..add(length.buffer.asUint8List())
        ..add(encoded);
      await _socket.flush();
    } on Object catch (error) {
      throw MigrationTransportException(
        'The migration frame could not be sent.',
        cause: error,
      );
    }
  }

  /// Receives and decodes exactly one complete frame.
  @override
  Future<MigrationSessionFrame> receive() async {
    _ensureOpen();
    try {
      return await _receiveFrame().timeout(_timeout);
    } on MigrationTransportException {
      rethrow;
    } on Object catch (error) {
      _socket.destroy();
      throw MigrationTransportException(
        'The migration connection was interrupted.',
        cause: error,
      );
    }
  }

  /// Closes the socket and releases the stream iterator.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _chunks.cancel();
    _socket.destroy();
  }

  Future<MigrationSessionFrame> _receiveFrame() async {
    final Uint8List encodedLength = await _readExact(4);
    final int length = ByteData.sublistView(
      encodedLength,
    ).getUint32(0, Endian.big);
    if (length < 3 + 1 + 8 + 24 + 4 + 16 || length > maxFrameLength) {
      throw const MigrationTransportException(
        'The migration frame length is invalid.',
      );
    }
    return MigrationSessionFrame.decode(await _readExact(length));
  }

  Future<Uint8List> _readExact(int length) async {
    final Uint8List output = Uint8List(length);
    var written = 0;
    while (written < length) {
      if (_pendingChunk == null || _pendingOffset >= _pendingChunk!.length) {
        if (!await _chunks.moveNext()) {
          throw const MigrationTransportException(
            'The migration peer closed the connection.',
          );
        }
        _pendingChunk = _chunks.current;
        _pendingOffset = 0;
      }
      final Uint8List chunk = _pendingChunk!;
      final int available = chunk.length - _pendingOffset;
      final int copyLength = (length - written) < available
          ? length - written
          : available;
      output.setRange(written, written + copyLength, chunk, _pendingOffset);
      written += copyLength;
      _pendingOffset += copyLength;
    }
    return output;
  }

  void _ensureOpen() {
    if (_closed) {
      throw const MigrationTransportException(
        'The migration connection is already closed.',
      );
    }
  }
}

/// Temporary TCP listener used by the sender or receiver pairing flow.
final class MigrationSocketServer {
  MigrationSocketServer._(this._server, this._timeout);

  final ServerSocket _server;
  final Duration _timeout;
  var _closed = false;

  /// Binds a temporary listener to [host] and [port].
  static Future<MigrationSocketServer> bind(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      return MigrationSocketServer._(
        await ServerSocket.bind(host, port),
        timeout,
      );
    } on Object catch (error) {
      throw MigrationTransportException(
        'The migration listener could not be started.',
        cause: error,
      );
    }
  }

  /// The actual port, including when [bind] received zero.
  int get port => _server.port;

  /// Accepts one peer and returns a frame transport.
  Future<MigrationSocketTransport> accept() async {
    if (_closed) {
      throw const MigrationTransportException(
        'The migration listener is already closed.',
      );
    }
    try {
      final Socket socket = await _server.first.timeout(_timeout);
      return MigrationSocketTransport._(socket, _timeout);
    } on Object catch (error) {
      throw MigrationTransportException(
        'The migration peer could not connect.',
        cause: error,
      );
    }
  }

  /// Stops listening for new migration peers.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _server.close();
  }
}
