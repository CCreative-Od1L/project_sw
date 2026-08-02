import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';

/// Deterministic crypto double that exposes temporary byte buffers to tests.
final class FakeCryptoService implements CryptoService {
  /// Creates a fake with optional derivation delays by KDF memory cost.
  FakeCryptoService({
    this.delays = const <int, Duration>{},
    this.derivationFailure,
  });

  /// Delays applied to each derivation's memory-cost profile.
  final Map<int, Duration> delays;

  /// Failure raised instead of deriving a KEK, when configured.
  final Object? derivationFailure;

  /// KEK buffers returned to callers.
  final List<Uint8List> derivedKeys = <Uint8List>[];

  /// MVK buffers returned to callers.
  final List<Uint8List> generatedKeys = <Uint8List>[];

  var _counter = 1;

  @override
  Future<Uint8List> deriveKek(
    String password,
    Uint8List salt, {
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) async {
    if (derivationFailure != null) {
      throw derivationFailure!;
    }
    final Duration? delay = delays[memoryKiB];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    final Uint8List key = Uint8List.fromList(
      List<int>.filled(32, memoryKiB & 0xff),
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
    return AeadCiphertext(nonce: nonce, ciphertext: ciphertext);
  }

  @override
  Uint8List decryptWithAead(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List additionalData,
  ) {
    final Uint8List plaintext = Uint8List(ciphertext.length - 16);
    for (var index = 0; index < plaintext.length; index++) {
      plaintext[index] = ciphertext[index] ^ key[index % key.length];
    }
    return plaintext;
  }
}
