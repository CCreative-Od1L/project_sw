import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/shared/result.dart';
import 'package:test/test.dart';

void main() {
  test('changes a master password through one repository operation', () async {
    final _FakeMasterPasswordChangeRepository repository =
        _FakeMasterPasswordChangeRepository();
    final ChangeMasterPassword changeMasterPassword = ChangeMasterPassword(
      repository,
    );

    final Result<ChangedMasterPassword, ChangeMasterPasswordFailure> result =
        await changeMasterPassword(
          currentMasterPassword: 'current password',
          newMasterPassword: 'new password',
        );

    expect(
      result,
      isA<Success<ChangedMasterPassword, ChangeMasterPasswordFailure>>(),
    );
    expect(repository.calls, <(String, String)>[
      ('current password', 'new password'),
    ]);
  });

  test('maps a rejected current password to a business failure', () async {
    final ChangeMasterPassword changeMasterPassword = ChangeMasterPassword(
      _FakeMasterPasswordChangeRepository(
        error: const InvalidMasterPasswordException(),
      ),
    );

    final Result<ChangedMasterPassword, ChangeMasterPasswordFailure> result =
        await changeMasterPassword(
          currentMasterPassword: 'wrong password',
          newMasterPassword: 'new password',
        );

    expect(
      result,
      const Failure<ChangedMasterPassword, ChangeMasterPasswordFailure>(
        ChangeMasterPasswordFailure.invalidCurrentMasterPassword,
      ),
    );
  });
}

final class _FakeMasterPasswordChangeRepository
    implements MasterPasswordChangeRepository {
  _FakeMasterPasswordChangeRepository({this.error});

  final List<(String, String)> calls = <(String, String)>[];
  final Object? error;

  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
  }) async {
    calls.add((currentMasterPassword, newMasterPassword));
    if (error != null) {
      throw error!;
    }
  }
}
