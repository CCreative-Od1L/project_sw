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

/// The non-sensitive timing result for one completed Argon2id profile.
final class Argon2idBenchmarkTier {
  /// Creates a completed profile result from its [parameters] and median time.
  const Argon2idBenchmarkTier({
    required this.parameters,
    required this.medianDuration,
  });

  /// The parameters measured for this tier.
  final Argon2idParameters parameters;

  /// The median of the tier's derivation samples.
  final Duration medianDuration;
}

/// The non-sensitive outcome of first-vault Argon2id parameter selection.
final class Argon2idBenchmarkResult {
  /// Creates an immutable report of all evaluated tiers and the chosen profile.
  Argon2idBenchmarkResult({
    required List<Argon2idBenchmarkTier> tiers,
    required this.selectedParameters,
  }) : tiers = List<Argon2idBenchmarkTier>.unmodifiable(tiers);

  /// Each profile evaluated before the selection rule stopped.
  final List<Argon2idBenchmarkTier> tiers;

  /// The strongest measured profile whose median met the target duration.
  final Argon2idParameters selectedParameters;
}

/// Progress emitted after each benchmarked parameter tier.
final class Argon2idBenchmarkProgress {
  /// Creates a benchmark progress update.
  const Argon2idBenchmarkProgress({
    required this.completedTiers,
    required this.totalTiers,
    required this.tier,
  });

  /// Number of parameter tiers that have completed.
  final int completedTiers;

  /// Total number of parameter tiers in the protocol.
  final int totalTiers;

  /// The completed tier's non-sensitive timing result.
  final Argon2idBenchmarkTier tier;
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
  Future<Argon2idBenchmarkResult> selectParameters(
    String password, {
    void Function(Argon2idBenchmarkProgress progress)? onProgress,
  }) async {
    if (samplesPerTier <= 0 || profiles.isEmpty) {
      throw ArgumentError('Benchmark profiles and samples must not be empty.');
    }

    final Uint8List salt = _crypto.randomBytes(16);
    Argon2idParameters selected = profiles.first;
    final List<Argon2idBenchmarkTier> tiers = <Argon2idBenchmarkTier>[];
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
        final Argon2idBenchmarkTier tier = Argon2idBenchmarkTier(
          parameters: profile,
          medianDuration: median,
        );
        tiers.add(tier);
        onProgress?.call(
          Argon2idBenchmarkProgress(
            completedTiers: tierIndex + 1,
            totalTiers: profiles.length,
            tier: tier,
          ),
        );
        if (median > targetDuration) {
          return Argon2idBenchmarkResult(
            tiers: tiers,
            selectedParameters: selected,
          );
        }
        selected = profile;
      }
      return Argon2idBenchmarkResult(
        tiers: tiers,
        selectedParameters: selected,
      );
    } finally {
      clearSensitiveBytes(salt);
    }
  }
}
