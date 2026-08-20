import 'package:project_sw/features/auth/domain/master_password_strength.dart';
import 'package:test/test.dart';

void main() {
  const MasterPasswordStrengthEvaluator evaluator =
      MasterPasswordStrengthEvaluator();

  test('classifies a short chosen password as weak', () {
    expect(evaluator.evaluate('short').strength, MasterPasswordStrength.weak);
  });

  test('uses the documented theoretical entropy bands', () {
    final MasterPasswordStrengthAssessment assessment = evaluator.evaluate(
      'correct horse battery staple',
    );

    expect(assessment.estimatedBits, greaterThanOrEqualTo(120));
    expect(assessment.strength, MasterPasswordStrength.veryStrong);
  });
}
