import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/core/crypto/sodium_crypto_service.dart';
import 'package:project_sw/core/crypto/sodium_isolate_probe.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports the default Argon2id calibration without secrets', (
    WidgetTester tester,
  ) async {
    final Argon2idBenchmark benchmark = Argon2idBenchmark(
      await SodiumCryptoService.initialize(),
    );
    final Argon2idBenchmarkResult result = await benchmark.selectParameters(
      'integration-calibration-password',
    );
    final Argon2idParameters expected = _expectedParameters(result);

    binding.reportData = <String, Object>{
      'environment': SodiumIsolateProbe.captureEnvironment().toReportData(),
      'targetDurationMilliseconds': benchmark.targetDuration.inMilliseconds,
      'tiers': result.tiers
          .map(
            (Argon2idBenchmarkTier tier) => <String, Object>{
              'memoryKiB': tier.parameters.memoryKiB,
              'iterations': tier.parameters.iterations,
              'parallelism': tier.parameters.parallelism,
              'medianMilliseconds': tier.medianDuration.inMilliseconds,
            },
          )
          .toList(),
      'selected': <String, Object>{
        'memoryKiB': result.selectedParameters.memoryKiB,
        'iterations': result.selectedParameters.iterations,
        'parallelism': result.selectedParameters.parallelism,
      },
    };

    expect(result.tiers, isNotEmpty);
    expect(result.tiers.length, lessThanOrEqualTo(benchmark.profiles.length));
    expect(result.selectedParameters.memoryKiB, expected.memoryKiB);
    expect(result.selectedParameters.iterations, expected.iterations);
    expect(result.selectedParameters.parallelism, expected.parallelism);
  });
}

Argon2idParameters _expectedParameters(Argon2idBenchmarkResult result) {
  Argon2idParameters selected = result.tiers.first.parameters;
  for (final Argon2idBenchmarkTier tier in result.tiers) {
    if (tier.medianDuration > const Duration(seconds: 1)) {
      break;
    }
    selected = tier.parameters;
  }
  return selected;
}
