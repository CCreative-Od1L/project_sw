import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/core/crypto/sodium_isolate_probe.dart';

void main() {
  group('SodiumIsolateProbe', () {
    test('initializes sodium and returns only random-byte metadata', () async {
      final SodiumProbeSample sample = await SodiumIsolateProbe.runSample();

      expect(sample.randomByteLength, sodiumProbeRandomByteLength);
      expect(sample.hasExpectedRandomByteLength, isTrue);
      expect(
        sample.initializationDuration,
        greaterThanOrEqualTo(Duration.zero),
      );
    });

    test('runs repeated short-lived samples sequentially', () async {
      final SodiumProbeSummary summary =
          await SodiumIsolateProbe.runSequentialSamples(sampleCount: 3);

      expect(summary.samples, hasLength(3));
      expect(summary.allSamplesValid, isTrue);
      expect(summary.minimum <= summary.p50, isTrue);
      expect(summary.p50 <= summary.p95, isTrue);
      expect(summary.p95 <= summary.maximum, isTrue);
    });

    test('propagates background-isolate errors', () async {
      await expectLater(
        SodiumIsolateProbe.throwInBackgroundForTesting(),
        throwsA(isA<StateError>()),
      );
    });

    test('clears temporary byte buffers in place', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      SodiumIsolateProbe.clearBytesForTesting(bytes);

      expect(bytes, everyElement(0));
    });
  });

  group('SodiumProbeSummary', () {
    test('uses the sorted nearest-rank sample for P95', () {
      final List<SodiumProbeSample> samples = List<SodiumProbeSample>.generate(
        30,
        (int index) => SodiumProbeSample(
          initializationDuration: Duration(microseconds: index + 1),
          randomByteLength: sodiumProbeRandomByteLength,
          hasExpectedRandomByteLength: true,
        ),
      ).reversed.toList();

      final SodiumProbeSummary summary = SodiumProbeSummary(samples);

      expect(summary.minimum, const Duration(microseconds: 1));
      expect(summary.p50, const Duration(microseconds: 15));
      expect(summary.p95, const Duration(microseconds: 29));
      expect(summary.maximum, const Duration(microseconds: 30));
    });

    test(
      'requires all samples to be valid before selecting short-lived work',
      () {
        final SodiumProbeSummary summary =
            SodiumProbeSummary(<SodiumProbeSample>[
              const SodiumProbeSample(
                initializationDuration: Duration(milliseconds: 1),
                randomByteLength: sodiumProbeRandomByteLength,
                hasExpectedRandomByteLength: false,
              ),
            ]);

        expect(summary.recommendsShortLivedIsolate, isFalse);
      },
    );
  });
}
