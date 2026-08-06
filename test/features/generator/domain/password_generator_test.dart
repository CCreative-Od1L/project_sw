import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';

void main() {
  test('random mode uses the requested length and enabled alphabet', () {
    final GeneratePassword generator = GeneratePassword(
      SequenceRandomSource(<int>[0, 1, 2, 3, 4, 5, 6, 7]),
    );

    final String password = generator(
      const GenerationProfile(
        length: 8,
        lowercase: true,
        uppercase: false,
        digits: false,
        symbols: false,
      ),
    );

    expect(password, hasLength(8));
    expect(password, matches(RegExp(r'^[a-z]+$')));
  });

  test('pronounceable mode alternates consonants and vowels', () {
    final GeneratePassword generator = GeneratePassword(
      SequenceRandomSource(List<int>.filled(20, 0)),
    );

    final String password = generator(
      const GenerationProfile(mode: GenerationMode.pronounceable, length: 9),
    );

    expect(password, hasLength(9));
    for (var index = 0; index < password.length; index++) {
      final bool isVowel = 'aeiou'.contains(password[index]);
      expect(isVowel, index.isOdd);
    }
  });

  test('ambiguous characters can be excluded without changing length', () {
    final GeneratePassword generator = GeneratePassword(
      SequenceRandomSource(List<int>.filled(20, 0)),
    );

    final String password = generator(
      const GenerationProfile(length: 20, excludeAmbiguous: true),
    );

    expect(password, hasLength(20));
    expect(
      password.split('').any(GenerationProfile.ambiguousCharacters.contains),
      isFalse,
    );
  });

  test('random mode rejects invalid length and an empty alphabet', () {
    final GeneratePassword generator = GeneratePassword(
      SequenceRandomSource(const <int>[0]),
    );

    expect(
      () => generator(const GenerationProfile(length: 7)),
      throwsA(isA<RangeError>()),
    );
    expect(
      () => generator(
        const GenerationProfile(
          lowercase: false,
          uppercase: false,
          digits: false,
          symbols: false,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('entropy follows the documented strength thresholds', () {
    final GeneratePassword generator = GeneratePassword(
      SequenceRandomSource(const <int>[0]),
    );

    expect(
      generator
          .estimateEntropy(
            const GenerationProfile(
              length: 8,
              uppercase: false,
              digits: false,
              symbols: false,
            ),
          )
          .strength,
      PasswordStrength.weak,
    );
    expect(
      generator
          .estimateEntropy(
            const GenerationProfile(
              length: 20,
              uppercase: false,
              digits: false,
              symbols: false,
            ),
          )
          .strength,
      PasswordStrength.strong,
    );
    expect(
      generator.estimateEntropy(const GenerationProfile()).strength,
      PasswordStrength.veryStrong,
    );
  });
}

final class SequenceRandomSource implements PasswordRandomSource {
  SequenceRandomSource(this._values);

  final List<int> _values;
  var _index = 0;

  @override
  int nextInt(int upperBound) {
    final int value = _values[_index % _values.length];
    _index++;
    return value % upperBound;
  }
}
