import 'dart:async';

import 'package:project_sw/features/auth/domain/authenticated_wipe_vault.dart';
import 'package:project_sw/features/auth/domain/master_password_verifier.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/verify_master_password.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/shared/errors/vault_exception.dart';
import 'package:project_sw/shared/result.dart';
import 'package:test/test.dart';

void main() {
  test(
    'rejects a wrong password without changing session or storage',
    () async {
      final _AuthenticatedWipeRepository repository =
          _AuthenticatedWipeRepository();
      final SessionController sessionController = SessionController(
        initialState: const UnlockedSession(
          authStrength: AuthStrength.masterPassword,
        ),
      );
      final AuthenticatedWipeVault wipe = AuthenticatedWipeVault(
        VerifyMasterPassword(
          _AuthenticatedWipeVerifier(
            error: const InvalidMasterPasswordException(),
          ),
        ),
        WipeVault(repository, sessionController),
        sessionController,
      );
      addTearDown(sessionController.dispose);

      final Result<WipedVault, AuthenticatedWipeFailure> result = await wipe(
        'wrong password',
      );

      expect(
        result,
        isA<Failure<WipedVault, AuthenticatedWipeFailure>>().having(
          (Failure<WipedVault, AuthenticatedWipeFailure> failure) =>
              failure.failure,
          'failure',
          AuthenticatedWipeFailure.invalidMasterPassword,
        ),
      );
      expect(repository.calls, 0);
      expect(sessionController.state, isA<UnlockedSession>());
    },
  );

  test('wipes only after the current master password verifies', () async {
    final _AuthenticatedWipeRepository repository =
        _AuthenticatedWipeRepository();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    final AuthenticatedWipeVault wipe = AuthenticatedWipeVault(
      VerifyMasterPassword(_AuthenticatedWipeVerifier()),
      WipeVault(repository, sessionController),
      sessionController,
    );
    addTearDown(sessionController.dispose);

    final Result<WipedVault, AuthenticatedWipeFailure> result = await wipe(
      'current password',
    );

    expect(result, isA<Success<WipedVault, AuthenticatedWipeFailure>>());
    expect(repository.calls, 1);
    expect(sessionController.state, isA<VaultNotCreatedSession>());
  });

  test('lock interrupts verification before destructive wipe begins', () async {
    final _AuthenticatedWipeRepository repository =
        _AuthenticatedWipeRepository();
    final _BlockingAuthenticatedWipeVerifier verifier =
        _BlockingAuthenticatedWipeVerifier();
    final SessionController sessionController = SessionController(
      initialState: const UnlockedSession(
        authStrength: AuthStrength.masterPassword,
      ),
    );
    final AuthenticatedWipeVault wipe = AuthenticatedWipeVault(
      VerifyMasterPassword(verifier),
      WipeVault(repository, sessionController),
      sessionController,
    );
    addTearDown(sessionController.dispose);

    final Future<Result<WipedVault, AuthenticatedWipeFailure>> result = wipe(
      'current password',
    );
    await verifier.started.future;

    sessionController.lock(LockReason.manualLock);
    verifier.release.complete();

    await expectLater(result, throwsA(isA<SessionActivityInterrupted>()));
    expect(repository.calls, 0);
    expect(sessionController.state, isA<LockedSession>());
  });
}

final class _AuthenticatedWipeVerifier implements MasterPasswordVerifier {
  _AuthenticatedWipeVerifier({this.error});

  final Object? error;

  @override
  Future<void> verifyMasterPassword(String masterPassword) async {
    final Object? failure = error;
    if (failure != null) throw failure;
  }
}

final class _BlockingAuthenticatedWipeVerifier
    implements MasterPasswordVerifier {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> verifyMasterPassword(String masterPassword) async {
    started.complete();
    await release.future;
  }
}

final class _AuthenticatedWipeRepository implements VaultWipeRepository {
  var calls = 0;

  @override
  Future<void> wipeVault() async => calls++;
}
