import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';

/// Deterministic crypto double that exposes temporary byte buffers to tests.
final class FakeCryptoService implements CryptoService {
  /// Creates a fake with optional derivation delays by KDF memory cost.
  FakeCryptoService({
    this.delays = const <int, Duration>{},
    this.derivationFailure,
    this.beforeDeriveKek,
  });

  /// Delays applied to each derivation's memory-cost profile.
  final Map<int, Duration> delays;

  /// Failure raised instead of deriving a KEK, when configured.
  final Object? derivationFailure;

  /// Optional synchronization hook invoked before each deterministic KDF.
  final Future<void> Function(String password)? beforeDeriveKek;

  /// KEK buffers returned to callers.
  final List<Uint8List> derivedKeys = <Uint8List>[];

  /// MVK buffers returned to callers.
  final List<Uint8List> generatedKeys = <Uint8List>[];

  /// Plaintext buffers returned from successful AEAD decryptions.
  final List<Uint8List> decryptedKeys = <Uint8List>[];

  var _counter = 1;

  @override
  Future<Uint8List> deriveKek(
    String password,
    Uint8List salt, {
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) async {
    await beforeDeriveKek?.call(password);
    if (derivationFailure != null) {
      throw derivationFailure!;
    }
    final Duration? delay = delays[memoryKiB];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    final int passwordFingerprint = password.codeUnits.fold<int>(
      0,
      (int value, int codeUnit) => (value + codeUnit) & 0xff,
    );
    final Uint8List key = Uint8List.fromList(
      List<int>.filled(32, (memoryKiB & 0xff) ^ passwordFingerprint),
    );
    derivedKeys.add(key);
    return key;
  }

  @override
  Uint8List generateKey() {
    final Uint8List key = Uint8List.fromList(
      List<int>.generate(32, (int index) => index + _counter),
    );
    _counter++;
    generatedKeys.add(key);
    return key;
  }

  @override
  Uint8List randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (int index) => (index + _counter) & 0xff),
  );

  @override
  int randomBytesUniform(int upperBound) {
    if (upperBound <= 0) {
      throw ArgumentError.value(upperBound, 'upperBound');
    }
    final int value = _counter % upperBound;
    _counter++;
    return value;
  }

  @override
  AeadCiphertext encryptWithAead(
    Uint8List key,
    Uint8List plaintext,
    Uint8List additionalData,
  ) {
    final Uint8List nonce = Uint8List.fromList(
      List<int>.generate(24, (int index) => (index + 9) & 0xff),
    );
    final Uint8List ciphertext = Uint8List(plaintext.length + 16);
    for (var index = 0; index < plaintext.length; index++) {
      ciphertext[index] = plaintext[index] ^ key[index % key.length];
    }
    final int tag = _authenticationTag(
      key,
      ciphertext.sublist(0, plaintext.length),
    );
    ciphertext.fillRange(plaintext.length, ciphertext.length, tag);
    return AeadCiphertext(nonce: nonce, ciphertext: ciphertext);
  }

  @override
  Uint8List decryptWithAead(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List additionalData,
  ) {
    if (ciphertext.length < 16) {
      throw StateError('authentication failed');
    }
    final Uint8List encryptedBody = ciphertext.sublist(
      0,
      ciphertext.length - 16,
    );
    final int expectedTag = _authenticationTag(key, encryptedBody);
    if (ciphertext
        .sublist(ciphertext.length - 16)
        .any((int byte) => byte != expectedTag)) {
      throw StateError('authentication failed');
    }
    final Uint8List plaintext = Uint8List(ciphertext.length - 16);
    for (var index = 0; index < plaintext.length; index++) {
      plaintext[index] = ciphertext[index] ^ key[index % key.length];
    }
    decryptedKeys.add(plaintext);
    return plaintext;
  }

  @override
  EphemeralKeyPair generateEphemeralKeyPair() {
    final int value = _counter++;
    return EphemeralKeyPair(
      publicKey: Uint8List.fromList(List<int>.filled(32, value)),
      secretKey: Uint8List.fromList(List<int>.filled(32, value ^ 0x5a)),
    );
  }

  @override
  DirectionalSessionKeys deriveClientSessionKeys({
    required Uint8List clientPublicKey,
    required Uint8List clientSecretKey,
    required Uint8List serverPublicKey,
  }) => DirectionalSessionKeys(
    tx: _sessionKey(clientPublicKey, serverPublicKey, 1),
    rx: _sessionKey(clientPublicKey, serverPublicKey, 2),
  );

  @override
  DirectionalSessionKeys deriveServerSessionKeys({
    required Uint8List serverPublicKey,
    required Uint8List serverSecretKey,
    required Uint8List clientPublicKey,
  }) => DirectionalSessionKeys(
    tx: _sessionKey(clientPublicKey, serverPublicKey, 2),
    rx: _sessionKey(clientPublicKey, serverPublicKey, 1),
  );

  @override
  Uint8List hash(Uint8List message) => _digest(message);

  @override
  Uint8List mac(Uint8List key, Uint8List message) =>
      _digest(Uint8List.fromList(<int>[...key, ...message]));

  int _authenticationTag(Uint8List key, Uint8List ciphertext) => <int>[
    ...key,
    ...ciphertext,
  ].fold<int>(0, (int sum, int byte) => (sum + byte) & 0xff);

  Uint8List _sessionKey(Uint8List client, Uint8List server, int direction) =>
      _digest(Uint8List.fromList(<int>[...client, ...server, direction]));

  Uint8List _digest(Uint8List message) {
    var accumulator = 0x811c9dc5;
    for (final int byte in message) {
      accumulator = ((accumulator ^ byte) * 0x01000193) & 0xffffffff;
    }
    return Uint8List.fromList(
      List<int>.generate(
        32,
        (int index) => (accumulator >> ((index % 4) * 8)) & 0xff,
      ),
    );
  }
}
