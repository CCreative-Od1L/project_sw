import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:test/test.dart';

void main() {
  test('changes the password and upgrades a biometric session', () async {
    final _PasswordChangeRepository repository = _PasswordChangeRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(authStrength: AuthStrength.biometric),
    );
    final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(repository),
      sessionController,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);

    await cubit.submit(
      currentMasterPassword: 'current password',
      newMasterPassword: 'new password',
      confirmation: 'new password',
    );

    expect(cubit.state, isA<MasterPasswordChangeCompleted>());
    expect(repository.calls, <(String, String)>[
      ('current password', 'new password'),
    ]);
    expect(
      (sessionController.state as UnlockedSession).authStrength,
      AuthStrength.masterPassword,
    );
  });

  test('rejects a mismatched confirmation before changing the vault', () async {
    final _PasswordChangeRepository repository = _PasswordChangeRepository();
    final SessionController sessionController = SessionController();
    final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
      ChangeMasterPassword(repository),
      sessionController,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);

    await cubit.submit(
      currentMasterPassword: 'current password',
      newMasterPassword: 'first value',
      confirmation: 'different value',
    );

    expect(cubit.state, isA<MasterPasswordChangeConfirmationMismatch>());
    expect(repository.calls, isEmpty);
  });

  test(
    'keeps the session unlocked when the current password is wrong',
    () async {
      final SessionController sessionController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.biometric,
        ),
      );
      final MasterPasswordChangeCubit cubit = MasterPasswordChangeCubit(
        ChangeMasterPassword(
          _PasswordChangeRepository(
            error: const InvalidMasterPasswordException(),
          ),
        ),
        sessionController,
      );
      addTearDown(cubit.close);
      addTearDown(sessionController.dispose);

      await cubit.submit(
        currentMasterPassword: 'wrong password',
        newMasterPassword: 'new password',
        confirmation: 'new password',
      );

      expect(cubit.state, isA<MasterPasswordChangeInvalidCurrent>());
      expect(
        (sessionController.state as UnlockedSession).authStrength,
        AuthStrength.biometric,
      );
    },
  );
}

final class _PasswordChangeRepository
    implements MasterPasswordChangeRepository {
  _PasswordChangeRepository({this.error});

  final List<(String, String)> calls = <(String, String)>[];
  final Object? error;

  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    calls.add((currentMasterPassword, newMasterPassword));
    if (error != null) throw error!;
  }
}
