import 'dart:math' as math;

import 'package:project_sw/core/crypto/crypto_service.dart';

/// Password generation mode defined by the v0.5 product specification.
enum GenerationMode {
  /// Uniformly samples the enabled character union.
  random,

  /// Alternates consonants and vowels for a more readable result.
  pronounceable,
}

/// The fixed strength bands used for theoretical entropy display.
enum PasswordStrength {
  /// Less than 50 bits.
  weak,

  /// 50 through 80 bits.
  medium,

  /// More than 80 through 120 bits.
  strong,

  /// More than 120 bits.
  veryStrong,
}

/// User-controlled password generation policy.
final class GenerationProfile {
  /// Creates a profile after validating its values at generation time.
  const GenerationProfile({
    this.mode = GenerationMode.random,
    this.length = 20,
    this.lowercase = true,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = false,
    this.symbolSubset = defaultSymbolSubset,
  });

  /// Minimum accepted random or pronounceable output length.
  static const int minLength = 8;

  /// Maximum accepted output length.
  static const int maxLength = 128;

  /// Symbols chosen to avoid common URL and form delimiters.
  static const Set<String> defaultSymbolSubset = <String>{
    '!',
    '@',
    '#',
    r'$',
    '%',
    '^',
    '&',
    '*',
    '(',
    ')',
    '-',
    '_',
    '=',
    '+',
    '[',
    ']',
    '{',
    '}',
    ':',
    ',',
    '.',
    '?',
  };

  /// Easily confused characters excluded when requested.
  static const Set<String> ambiguousCharacters = <String>{
    'O',
    '0',
    'I',
    '1',
    'l',
    '|',
    'B',
    '8',
    'S',
    '5',
    'G',
    '6',
  };

  /// Current generation mode.
  final GenerationMode mode;

  /// Number of output characters.
  final int length;

  /// Whether lowercase letters are enabled in random mode.
  final bool lowercase;

  /// Whether uppercase letters are enabled in random mode.
  final bool uppercase;

  /// Whether digits are enabled in random mode.
  final bool digits;

  /// Whether symbols are enabled in random mode.
  final bool symbols;

  /// Whether ambiguous glyphs should be removed from the random alphabet.
  final bool excludeAmbiguous;

  /// Symbols available when [symbols] is enabled.
  final Set<String> symbolSubset;

  /// Returns a modified profile for the generator controls.
  GenerationProfile copyWith({
    GenerationMode? mode,
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
    bool? excludeAmbiguous,
    Set<String>? symbolSubset,
  }) => GenerationProfile(
    mode: mode ?? this.mode,
    length: length ?? this.length,
    lowercase: lowercase ?? this.lowercase,
    uppercase: uppercase ?? this.uppercase,
    digits: digits ?? this.digits,
    symbols: symbols ?? this.symbols,
    excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
    symbolSubset: symbolSubset ?? this.symbolSubset,
  );
}

/// The non-sensitive strength report for one generation profile.
final class PasswordEntropy {
  /// Creates a theoretical entropy report.
  const PasswordEntropy({required this.bits, required this.strength});

  /// Estimated bits of entropy, not a dictionary-strength claim.
  final double bits;

  /// Strength band derived from [bits].
  final PasswordStrength strength;
}

/// Injectable CSPRNG boundary for deterministic domain tests.
abstract interface class PasswordRandomSource {
  /// Returns an unbiased integer in [0, upperBound).
  int nextInt(int upperBound);
}

/// Production random source backed by the same Sodium CSPRNG as vault crypto.
final class CryptoPasswordRandomSource implements PasswordRandomSource {
  /// Creates a random source from the application crypto boundary.
  const CryptoPasswordRandomSource(this._crypto);

  final CryptoService _crypto;

  @override
  int nextInt(int upperBound) => _crypto.randomBytesUniform(upperBound);
}

/// Generates passwords from a validated [GenerationProfile].
final class GeneratePassword {
  /// Creates the use case with an injected unbiased random source.
  const GeneratePassword(this._random);

  final PasswordRandomSource _random;

  /// Generates one password string.
  String call(GenerationProfile profile) {
    _validate(profile);
    return switch (profile.mode) {
      GenerationMode.random => _randomPassword(profile),
      GenerationMode.pronounceable => _pronounceablePassword(profile.length),
    };
  }

  /// Estimates theoretical entropy using the documented vocabulary size.
  PasswordEntropy estimateEntropy(GenerationProfile profile) {
    _validate(profile);
    final double bits = switch (profile.mode) {
      GenerationMode.random =>
        profile.length * _log2(_randomAlphabet(profile).length),
      GenerationMode.pronounceable => _pronounceableEntropy(profile.length),
    };
    return PasswordEntropy(bits: bits, strength: _strengthFor(bits));
  }

  String _randomPassword(GenerationProfile profile) {
    final String alphabet = _randomAlphabet(profile);
    return String.fromCharCodes(
      List<int>.generate(
        profile.length,
        (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ),
    );
  }

  String _pronounceablePassword(int length) {
    const String consonants = 'bcdfghjklmnpqrstvwxyz';
    const String vowels = 'aeiou';
    return String.fromCharCodes(
      List<int>.generate(length, (int index) {
        final String alphabet = index.isEven ? consonants : vowels;
        return alphabet.codeUnitAt(_random.nextInt(alphabet.length));
      }),
    );
  }

  String _randomAlphabet(GenerationProfile profile) {
    final StringBuffer alphabet = StringBuffer();
    if (profile.lowercase) alphabet.write('abcdefghijklmnopqrstuvwxyz');
    if (profile.uppercase) alphabet.write('ABCDEFGHIJKLMNOPQRSTUVWXYZ');
    if (profile.digits) alphabet.write('0123456789');
    if (profile.symbols) alphabet.write(profile.symbolSubset.join());
    final Iterable<String> characters = alphabet.toString().split('');
    final Iterable<String> filtered = profile.excludeAmbiguous
        ? characters.where(
            (String character) =>
                !GenerationProfile.ambiguousCharacters.contains(character),
          )
        : characters;
    return filtered.join();
  }

  double _pronounceableEntropy(int length) {
    const int consonants = 21;
    const int vowels = 5;
    final int pairs = length ~/ 2;
    final double pairEntropy = pairs * _log2(consonants * vowels);
    return length.isEven ? pairEntropy : pairEntropy + _log2(consonants);
  }

  void _validate(GenerationProfile profile) {
    if (profile.length < GenerationProfile.minLength ||
        profile.length > GenerationProfile.maxLength) {
      throw RangeError.range(
        profile.length,
        GenerationProfile.minLength,
        GenerationProfile.maxLength,
        'length',
      );
    }
    if (profile.mode == GenerationMode.random &&
        _randomAlphabet(profile).isEmpty) {
      throw ArgumentError('At least one random character set is required.');
    }
  }

  double _log2(num value) => math.log(value) / math.ln2;

  PasswordStrength _strengthFor(double bits) => switch (bits) {
    < 50 => PasswordStrength.weak,
    < 80 => PasswordStrength.medium,
    < 120 => PasswordStrength.strong,
    _ => PasswordStrength.veryStrong,
  };
}
