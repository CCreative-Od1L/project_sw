import 'dart:async';

import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';
import 'package:project_sw/features/auth/presentation/deadlock_wipe_cubit.dart';
import 'package:test/test.dart';

void main() {
  test('reveals only after seven lock-icon taps within three seconds', () {
    DateTime now = DateTime.utc(2026, 8, 20, 12);
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final DeadlockWipeCubit cubit = DeadlockWipeCubit(
      WipeVault(_WipeRepository(), sessionController),
      clock: () => now,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);

    for (var tap = 0; tap < 6; tap++) {
      cubit.registerLockIconTap();
    }
    expect(cubit.state, isA<DeadlockWipeHidden>());

    cubit.registerLockIconTap();
    expect(cubit.state, isA<DeadlockWipeRevealed>());

    cubit.hide();
    for (var tap = 0; tap < 6; tap++) {
      cubit.registerLockIconTap();
    }
    now = now.add(const Duration(seconds: 3));
    cubit.registerLockIconTap();
    expect(cubit.state, isA<DeadlockWipeHidden>());
  });

  test('requires the exact confirmation word before countdown', () async {
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final DeadlockWipeCubit cubit = DeadlockWipeCubit(
      WipeVault(_WipeRepository(), sessionController),
      delay: (_) async {},
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);
    for (var tap = 0; tap < 7; tap++) {
      cubit.registerLockIconTap();
    }

    await cubit.startCountdown('delete');

    expect(
      cubit.state,
      isA<DeadlockWipeRevealed>().having(
        (DeadlockWipeRevealed state) => state.confirmationInvalid,
        'confirmationInvalid',
        isTrue,
      ),
    );
  });

  test('cancels during the delay without invoking the wipe', () async {
    final Completer<void> delay = Completer<void>();
    final _WipeRepository repository = _WipeRepository();
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    final DeadlockWipeCubit cubit = DeadlockWipeCubit(
      WipeVault(repository, sessionController),
      delay: (_) => delay.future,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);
    for (var tap = 0; tap < 7; tap++) {
      cubit.registerLockIconTap();
    }

    final Future<void> countdown = cubit.startCountdown('DELETE');
    await Future<void>.delayed(Duration.zero);
    expect(
      cubit.state,
      isA<DeadlockWipeCountingDown>().having(
        (DeadlockWipeCountingDown state) => state.remainingSeconds,
        'remainingSeconds',
        10,
      ),
    );
    cubit.cancelCountdown();
    delay.complete();
    await countdown;

    expect(cubit.state, isA<DeadlockWipeRevealed>());
    expect(repository.calls, 0);
  });

  test('wipes only after all ten countdown ticks finish', () async {
    final _WipeRepository repository = _WipeRepository();
    final SessionController sessionController = SessionController(
      initialState: const LockedSession(reason: LockReason.coldStart),
    );
    var delayCalls = 0;
    final DeadlockWipeCubit cubit = DeadlockWipeCubit(
      WipeVault(repository, sessionController),
      delay: (_) async => delayCalls++,
    );
    addTearDown(cubit.close);
    addTearDown(sessionController.dispose);
    for (var tap = 0; tap < 7; tap++) {
      cubit.registerLockIconTap();
    }

    await cubit.startCountdown('DELETE');

    expect(delayCalls, 10);
    expect(repository.calls, 1);
    expect(cubit.state, isA<DeadlockWipeCompleted>());
    expect(sessionController.state, isA<VaultNotCreatedSession>());
  });
}

final class _WipeRepository implements VaultWipeRepository {
  var calls = 0;

  @override
  Future<void> wipeVault() async => calls++;
}
