import 'dart:typed_data';

import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:test/test.dart';

import '../../helpers/fake_crypto_service.dart';

void main() {
  test(
    'selects the highest profile whose three-sample median meets target',
    () async {
      final FakeCryptoService crypto = FakeCryptoService(
        delays: const <int, Duration>{
          19 * 1024: Duration(milliseconds: 1),
          32 * 1024: Duration(milliseconds: 1),
          48 * 1024: Duration(milliseconds: 20),
        },
      );
      final Argon2idBenchmark benchmark = Argon2idBenchmark(
        crypto,
        targetDuration: const Duration(milliseconds: 10),
        profiles: Argon2idBenchmark.defaultProfiles.take(3).toList(),
      );

      final List<Argon2idBenchmarkProgress> progress =
          <Argon2idBenchmarkProgress>[];
      final Argon2idParameters selected = await benchmark.selectParameters(
        'correct horse battery staple',
        onProgress: progress.add,
      );

      expect(selected.memoryKiB, 32 * 1024);
      expect(progress, hasLength(3));
      expect(crypto.derivedKeys.every(_isCleared), isTrue);
    },
  );
}

bool _isCleared(Uint8List bytes) => bytes.every((int byte) => byte == 0);
