import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:project_sw/core/crypto/sodium_isolate_probe.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('30 short-lived sodium isolates meet the background threshold', (
    WidgetTester tester,
  ) async {
    final SodiumProbeEnvironment environment =
        SodiumIsolateProbe.captureEnvironment();
    final SodiumProbeSummary summary =
        await SodiumIsolateProbe.runSequentialSamples();

    binding.reportData = <String, Object>{
      'environment': environment.toReportData(),
      'sampleCount': summary.samples.length,
      'minimumInitializationMicroseconds': summary.minimum.inMicroseconds,
      'p50InitializationMicroseconds': summary.p50.inMicroseconds,
      'p95InitializationMicroseconds': summary.p95.inMicroseconds,
      'maximumInitializationMicroseconds': summary.maximum.inMicroseconds,
      'allSamplesValid': summary.allSamplesValid,
      'recommendsShortLivedIsolate': summary.recommendsShortLivedIsolate,
    };

    expect(summary.allSamplesValid, isTrue);
    expect(summary.p95 <= sodiumProbeShortLivedP95Limit, isTrue);
  });
}
