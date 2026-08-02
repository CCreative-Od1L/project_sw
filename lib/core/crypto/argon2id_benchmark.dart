import 'dart:typed_data';

import 'package:project_sw/core/crypto/crypto_service.dart';

/// Persisted Argon2id parameters expressed in the vault file format units.
final class Argon2idParameters {
  /// Creates a parameter set.
  const Argon2idParameters({
    required this.memoryKiB,
    required this.iterations,
    this.parallelism = 1,
  });

  /// Memory cost in KiB.
  final int memoryKiB;

  /// Time cost.
  final int iterations;

  /// Parallelism cost.
  final int parallelism;
}

/// Progress emitted after each benchmarked parameter tier.
final class Argon2idBenchmarkProgress {
  /// Creates a benchmark progress update.
  const Argon2idBenchmarkProgress({
    required this.completedTiers,
    required this.totalTiers,
  });

  /// Number of parameter tiers that have completed.
  final int completedTiers;

  /// Total number of parameter tiers in the protocol.
  final int totalTiers;
}

/// Selects the strongest KDF profile whose median derivation fits the target.
final class Argon2idBenchmark {
  /// Creates the benchmark with a selected [crypto] implementation.
  const Argon2idBenchmark(
    this._crypto, {
    this.targetDuration = const Duration(seconds: 1),
    this.samplesPerTier = 3,
    this.profiles = defaultProfiles,
  });

  /// The roadmap's ordered low-to-high parameter profiles.
  static const List<Argon2idParameters> defaultProfiles = <Argon2idParameters>[
    Argon2idParameters(memoryKiB: 19 * 1024, iterations: 2),
    Argon2idParameters(memoryKiB: 32 * 1024, iterations: 2),
    Argon2idParameters(memoryKiB: 48 * 1024, iterations: 3),
    Argon2idParameters(memoryKiB: 64 * 1024, iterations: 3),
    Argon2idParameters(memoryKiB: 96 * 1024, iterations: 4),
  ];

  /// Crypto primitive used for each isolated KDF sample.
  final CryptoService _crypto;

  /// Maximum accepted median derivation duration.
  final Duration targetDuration;

  /// Number of derivations measured for each profile.
  final int samplesPerTier;

  /// Ordered candidate profiles from lowest to highest cost.
  final List<Argon2idParameters> profiles;

  /// Benchmarks all viable tiers using the roadmap's three-sample median rule.
  Future<Argon2idParameters> selectParameters(
    String password, {
    void Function(Argon2idBenchmarkProgress progress)? onProgress,
  }) async {
    if (samplesPerTier <= 0 || profiles.isEmpty) {
      throw ArgumentError('Benchmark profiles and samples must not be empty.');
    }

    final Uint8List salt = _crypto.randomBytes(16);
    Argon2idParameters selected = profiles.first;
    try {
      for (var tierIndex = 0; tierIndex < profiles.length; tierIndex++) {
        final Argon2idParameters profile = profiles[tierIndex];
        final List<Duration> samples = <Duration>[];

        for (var sampleIndex = 0; sampleIndex < samplesPerTier; sampleIndex++) {
          final Stopwatch stopwatch = Stopwatch()..start();
          final Uint8List kek = await _crypto.deriveKek(
            password,
            salt,
            memoryKiB: profile.memoryKiB,
            iterations: profile.iterations,
            parallelism: profile.parallelism,
          );
          stopwatch.stop();
          clearSensitiveBytes(kek);
          samples.add(stopwatch.elapsed);
        }

        samples.sort();
        final Duration median = samples[samples.length ~/ 2];
        onProgress?.call(
          Argon2idBenchmarkProgress(
            completedTiers: tierIndex + 1,
            totalTiers: profiles.length,
          ),
        );
        if (median > targetDuration) {
          return selected;
        }
        selected = profile;
      }
      return selected;
    } finally {
      clearSensitiveBytes(salt);
    }
  }
}
