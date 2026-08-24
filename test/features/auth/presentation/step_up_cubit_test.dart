import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/presentation/step_up_cubit.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';

void main() {
  late FakeMasterPasswordVerifier verifier;
  late SessionController sessionController;
  late StepUpCubit cubit;

  setUp(() {
    verifier = FakeMasterPasswordVerifier();
    sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    cubit = StepUpCubit(VerifyMasterPassword(verifier), sessionController);
  });

  tearDown(() {
    cubit.close();
    sessionController.dispose();
  });

  test(
    'upgrades the session only after the master password verifies',
    () async {
      final bool verified = await cubit.verify('correct password');

      expect(verified, isTrue);
      expect(verifier.passwords, <String>['correct password']);
      expect(
        (sessionController.state as UnlockedSession).authStrength,
        AuthStrength.masterPassword,
      );
      expect(cubit.state, isA<StepUpReady>());
    },
  );

  test('keeps a biometric session when the password is rejected', () async {
    verifier.failure = const InvalidMasterPasswordException();

    final bool verified = await cubit.verify('wrong password');

    expect(verified, isFalse);
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.biometric,
    );
    expect(cubit.state, isA<StepUpInvalidPassword>());
  });

  test('does not prompt again after a session is upgraded', () async {
    sessionController.completeMasterPasswordStepUp();

    final bool verified = await cubit.verify('not consulted');

    expect(verified, isTrue);
    expect(verifier.passwords, isEmpty);
  });

  test('rejects a challenge after the session is locked', () async {
    sessionController.lock(LockReason.manualLock);

    final bool verified = await cubit.verify('correct password');

    expect(verified, isFalse);
    expect(cubit.state, isA<StepUpUnavailable>());
    expect(verifier.passwords, isEmpty);
  });
}

final class FakeMasterPasswordVerifier implements MasterPasswordVerifier {
  final List<String> passwords = <String>[];
  Object? failure;

  @override
  Future<void> verifyMasterPassword(String masterPassword) async {
    passwords.add(masterPassword);
    final Object? currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
  }
}
