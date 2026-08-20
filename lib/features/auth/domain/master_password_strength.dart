import 'dart:math' as math;

/// The documented theoretical-entropy bands for a chosen master password.
enum MasterPasswordStrength {
  /// Less than 50 estimated bits.
  weak,

  /// 50 through 80 estimated bits.
  medium,

  /// More than 80 through 120 estimated bits.
  strong,

  /// More than 120 estimated bits.
  veryStrong,
}

/// A non-secret strength projection suitable for immediate UI feedback.
final class MasterPasswordStrengthAssessment {
  /// Creates an assessment from estimated bits and its matching band.
  const MasterPasswordStrengthAssessment({
    required this.estimatedBits,
    required this.strength,
  });

  /// The theoretical entropy estimate, not a dictionary-resistance claim.
  final double estimatedBits;

  /// The fixed strength band derived from [estimatedBits].
  final MasterPasswordStrength strength;
}

/// Estimates chosen-password entropy from length and represented character sets.
final class MasterPasswordStrengthEvaluator {
  /// Creates the stateless evaluator.
  const MasterPasswordStrengthEvaluator();

  /// Returns a conservative theoretical estimate without retaining the input.
  MasterPasswordStrengthAssessment evaluate(String password) {
    var hasLowercase = false;
    var hasUppercase = false;
    var hasDigits = false;
    var length = 0;
    final Set<int> otherCharacters = <int>{};
    for (final int rune in password.runes) {
      length++;
      if (rune >= 0x61 && rune <= 0x7a) {
        hasLowercase = true;
      } else if (rune >= 0x41 && rune <= 0x5a) {
        hasUppercase = true;
      } else if (rune >= 0x30 && rune <= 0x39) {
        hasDigits = true;
      } else {
        otherCharacters.add(rune);
      }
    }
    final int alphabetSize =
        (hasLowercase ? 26 : 0) +
        (hasUppercase ? 26 : 0) +
        (hasDigits ? 10 : 0) +
        (otherCharacters.isEmpty ? 0 : math.max(33, otherCharacters.length));
    final double bits = alphabetSize < 2
        ? 0
        : length * math.log(alphabetSize) / math.ln2;
    return MasterPasswordStrengthAssessment(
      estimatedBits: bits,
      strength: switch (bits) {
        < 50 => MasterPasswordStrength.weak,
        < 80 => MasterPasswordStrength.medium,
        < 120 => MasterPasswordStrength.strong,
        _ => MasterPasswordStrength.veryStrong,
      },
    );
  }
}
