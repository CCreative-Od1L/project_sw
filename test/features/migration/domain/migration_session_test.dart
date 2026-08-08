import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';
import 'package:project_sw/features/migration/domain/migration_exception.dart';
import 'package:project_sw/features/migration/domain/migration_session.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_crypto_service.dart';

void main() {
  late FakeCryptoService crypto;
  late MigrationSession sender;
  late MigrationSession receiver;

  setUp(() {
    crypto = FakeCryptoService();
    final identity = crypto.generateEphemeralKeyPair();
    final receiverIdentity = crypto.generateEphemeralKeyPair();
    final Uint8List senderPublicKey = Uint8List.fromList(identity.publicKey);
    final Uint8List receiverPublicKey = Uint8List.fromList(
      receiverIdentity.publicKey,
    );
    sender = MigrationSession.establishClient(
      crypto: crypto,
      localIdentity: identity,
      remotePublicKey: receiverPublicKey,
    );
    receiver = MigrationSession.establishServer(
      crypto: crypto,
      localIdentity: receiverIdentity,
      remotePublicKey: senderPublicKey,
    );
  });

  tearDown(() {
    sender.dispose();
    receiver.dispose();
  });

  test('round-trips an authenticated frame and transcript MAC', () {
    final Uint8List plaintext = Uint8List.fromList(<int>[1, 2, 3]);
    final MigrationSessionFrame frame = sender.seal(
      MigrationMessageType.entry,
      plaintext,
    );

    expect(
      receiver.open(MigrationSessionFrame.decode(frame.encode())),
      plaintext,
    );

    final Uint8List transcriptMac = sender.createTranscriptMac();
    receiver.verifyTranscriptMac(transcriptMac);
    expect(
      () => sender.seal(MigrationMessageType.entry, Uint8List(0)),
      throwsA(isA<MigrationProtocolException>()),
    );
    clearSensitiveBytes(transcriptMac);
  });

  test('rejects replay and out-of-order frames without advancing state', () {
    final MigrationSessionFrame first = sender.seal(
      MigrationMessageType.entry,
      Uint8List.fromList(<int>[1]),
    );
    final MigrationSessionFrame second = sender.seal(
      MigrationMessageType.entry,
      Uint8List.fromList(<int>[2]),
    );

    expect(receiver.open(first), <int>[1]);
    expect(
      () => receiver.open(first),
      throwsA(
        isA<MigrationProtocolException>().having(
          (MigrationProtocolException error) => error.code,
          'code',
          MigrationErrorCode.sequenceMismatch,
        ),
      ),
    );
    expect(receiver.open(second), <int>[2]);
  });

  test('rejects an authenticated-frame tamper', () {
    final MigrationSessionFrame original = sender.seal(
      MigrationMessageType.entry,
      Uint8List.fromList(<int>[7, 8]),
    );
    final Uint8List tamperedCiphertext = Uint8List.fromList(original.ciphertext)
      ..[0] ^= 0x01;
    final MigrationSessionFrame tampered = MigrationSessionFrame(
      type: original.type,
      sequence: original.sequence,
      nonce: original.nonce,
      ciphertext: tamperedCiphertext,
    );

    expect(
      () => receiver.open(tampered),
      throwsA(
        isA<MigrationProtocolException>().having(
          (MigrationProtocolException error) => error.code,
          'code',
          MigrationErrorCode.authenticationFailed,
        ),
      ),
    );
  });

  test('rejects a transcript MAC mismatch', () {
    final MigrationSessionFrame frame = sender.seal(
      MigrationMessageType.entry,
      Uint8List.fromList(<int>[9]),
    );
    receiver.open(frame);

    final Uint8List transcriptMac = sender.createTranscriptMac()..[0] ^= 0x01;
    expect(
      () => receiver.verifyTranscriptMac(transcriptMac),
      throwsA(
        isA<MigrationProtocolException>().having(
          (MigrationProtocolException error) => error.code,
          'code',
          MigrationErrorCode.transcriptMismatch,
        ),
      ),
    );
    clearSensitiveBytes(transcriptMac);
  });

  test('protects the final transfer frame without self-including its MAC', () {
    final MigrationSessionFrame entry = sender.seal(
      MigrationMessageType.entry,
      Uint8List.fromList(<int>[4]),
    );
    receiver.open(entry);

    final MigrationSessionFrame transferEnd = sender.sealTransferEnd();
    final Uint8List transcriptMac = receiver.openTransferEnd(transferEnd);
    expect(transcriptMac, hasLength(32));
    receiver.verifyTranscriptMac(transcriptMac);
    clearSensitiveBytes(transcriptMac);
  });
}
