import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:test/test.dart';

void main() {
  test('publishes setup only after all wipe targets are gone', () async {
    final _WipeSecretCleaner cleaner = _WipeSecretCleaner();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
      secretCleaner: cleaner,
    );
    final _WipeRepository repository = _WipeRepository();
    addTearDown(sessionController.dispose);

    await WipeVault(repository, sessionController)();

    expect(repository.calls, 1);
    expect(cleaner.calls, 1);
    expect(sessionController.state, isA<VaultNotCreatedSession>());
  });

  test('keeps the session blocked when any wipe target fails', () async {
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final WipeVault wipeVault = WipeVault(
      _WipeRepository(error: StateError('delete failed')),
      sessionController,
    );
    addTearDown(sessionController.dispose);

    await expectLater(wipeVault(), throwsStateError);

    expect(sessionController.state, isA<LockedSession>());
    expect(
      (sessionController.state as LockedSession).reason,
      LockReason.wipeStarted,
    );
  });
}

final class _WipeRepository implements VaultWipeRepository {
  _WipeRepository({this.error});

  final Object? error;
  var calls = 0;

  @override
  Future<void> wipeVault() async {
    calls++;
    final Object? failure = error;
    if (failure != null) throw failure;
  }
}

final class _WipeSecretCleaner implements SessionSecretCleaner {
  var calls = 0;

  @override
  void clearUnlockedSession() => calls++;
}
