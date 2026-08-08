import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';
import 'migration_socket_transport.dart';
import '../domain/migration_exception.dart';
import '../domain/migration_message_codec.dart';
import '../domain/migration_models.dart';
import '../domain/migration_session.dart';
import '../domain/migration_transfer.dart';

/// Coordinates one sender-to-receiver migration over an authenticated stream.
abstract final class MigrationTransferCoordinator {
  /// Maximum number of entries retained before transcript verification.
  static const int maxBufferedEntries = 10000;

  /// Sends preflight, all entries, and the final transcript MAC.
  static Future<void> send({
    required MigrationFrameTransport transport,
    required MigrationSession session,
    required MigrationCapabilities capabilities,
    required MigrationVaultPort vault,
  }) async {
    final List<MigrationEntryPayload> entries = await vault
        .exportMigrationEntries();
    try {
      final Uint8List preflightBytes = MigrationPreflightCodec.encode(
        capabilities,
      );
      final MigrationSessionFrame preflight;
      try {
        preflight = session.seal(
          MigrationMessageType.preflight,
          preflightBytes,
        );
      } finally {
        clearSensitiveBytes(preflightBytes);
      }
      try {
        await transport.send(preflight);
      } finally {
        preflight.dispose();
      }

      final MigrationSessionFrame response = await transport.receive();
      try {
        _expectType(response, MigrationMessageType.preflight);
        final Uint8List responseBytes = session.open(response);
        try {
          final MigrationCapabilities peer = MigrationPreflightCodec.decode(
            responseBytes,
          );
          final int negotiated = capabilities.negotiateWith(peer);
          for (final MigrationEntryPayload entry in entries) {
            if (entry.plaintextFormatId != negotiated) {
              throw const MigrationProtocolException(
                MigrationErrorCode.incompatible,
                'An entry plaintext format was not negotiated.',
              );
            }
            final Uint8List encoded = MigrationEntryPayloadCodec.encode(entry);
            final MigrationSessionFrame frame = session.seal(
              MigrationMessageType.entry,
              encoded,
            );
            clearSensitiveBytes(encoded);
            try {
              await transport.send(frame);
            } finally {
              frame.dispose();
            }
          }
        } finally {
          clearSensitiveBytes(responseBytes);
        }
      } finally {
        response.dispose();
      }

      final MigrationSessionFrame transferEnd = session.sealTransferEnd();
      try {
        await transport.send(transferEnd);
      } finally {
        transferEnd.dispose();
      }
    } finally {
      for (final MigrationEntryPayload entry in entries) {
        entry.dispose();
      }
    }
  }

  /// Receives and buffers entries, importing only after transcript verification.
  static Future<void> receive({
    required MigrationFrameTransport transport,
    required MigrationSession session,
    required MigrationCapabilities capabilities,
    required MigrationVaultPort vault,
  }) async {
    final List<MigrationEntryPayload> entries = <MigrationEntryPayload>[];
    MigrationCapabilities? peerCapabilities;
    try {
      final MigrationSessionFrame preflight = await transport.receive();
      try {
        _expectType(preflight, MigrationMessageType.preflight);
        final Uint8List preflightBytes = session.open(preflight);
        try {
          peerCapabilities = MigrationPreflightCodec.decode(preflightBytes);
          capabilities.negotiateWith(peerCapabilities);
        } finally {
          clearSensitiveBytes(preflightBytes);
        }
      } finally {
        preflight.dispose();
      }

      final Uint8List responseBytes = MigrationPreflightCodec.encode(
        capabilities,
      );
      final MigrationSessionFrame response;
      try {
        response = session.seal(MigrationMessageType.preflight, responseBytes);
      } finally {
        clearSensitiveBytes(responseBytes);
      }
      try {
        await transport.send(response);
      } finally {
        response.dispose();
      }

      final int negotiated = capabilities.negotiateWith(peerCapabilities);
      while (true) {
        final MigrationSessionFrame frame = await transport.receive();
        if (frame.type == MigrationMessageType.transferEnd) {
          try {
            final Uint8List receivedMac = MigrationTransferEndCodec.decode(
              session.openTransferEnd(frame),
            );
            try {
              session.verifyTranscriptMac(receivedMac);
            } finally {
              clearSensitiveBytes(receivedMac);
            }
          } finally {
            frame.dispose();
          }
          break;
        }
        try {
          _expectType(frame, MigrationMessageType.entry);
          final Uint8List encoded = session.open(frame);
          try {
            final MigrationEntryPayload entry =
                MigrationEntryPayloadCodec.decode(encoded);
            if (entry.plaintextFormatId != negotiated) {
              entry.dispose();
              throw const MigrationProtocolException(
                MigrationErrorCode.incompatible,
                'An entry plaintext format was not negotiated.',
              );
            }
            entries.add(entry);
            if (entries.length > maxBufferedEntries) {
              throw const MigrationProtocolException(
                MigrationErrorCode.invalidState,
                'The migration contains too many entries.',
              );
            }
          } finally {
            clearSensitiveBytes(encoded);
          }
        } finally {
          frame.dispose();
        }
      }
      if (entries.isNotEmpty) {
        await vault.importMigrationEntries(entries);
      }
    } finally {
      for (final MigrationEntryPayload entry in entries) {
        entry.dispose();
      }
    }
  }

  static void _expectType(
    MigrationSessionFrame frame,
    MigrationMessageType expected,
  ) {
    if (frame.type != expected) {
      throw const MigrationProtocolException(
        MigrationErrorCode.invalidState,
        'The migration message arrived in an invalid order.',
      );
    }
  }
}
