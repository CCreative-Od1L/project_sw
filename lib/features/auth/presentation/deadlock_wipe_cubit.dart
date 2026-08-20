import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/features/auth/domain/wipe_vault.dart';

/// Clock seam for enforcing a genuinely consecutive hidden-tap gesture.
typedef DeadlockWipeClock = DateTime Function();

/// Delay seam for a visible, cancelable countdown.
typedef DeadlockWipeDelay = Future<void> Function(Duration duration);

/// UI state for the hidden deadlock-wipe escape path.
sealed class DeadlockWipeViewState {
  /// Creates a deadlock-wipe state.
  const DeadlockWipeViewState();
}

/// The escape path is not visible.
final class DeadlockWipeHidden extends DeadlockWipeViewState {
  /// Creates the hidden state.
  const DeadlockWipeHidden();
}

/// The irreversible warning and confirmation form are visible.
final class DeadlockWipeRevealed extends DeadlockWipeViewState {
  /// Creates the revealed state.
  const DeadlockWipeRevealed({this.confirmationInvalid = false});

  /// Whether the last submitted confirmation did not exactly match.
  final bool confirmationInvalid;
}

/// The wipe may still be cancelled for [remainingSeconds].
final class DeadlockWipeCountingDown extends DeadlockWipeViewState {
  /// Creates a countdown state.
  const DeadlockWipeCountingDown(this.remainingSeconds);

  /// Whole seconds remaining before deletion starts.
  final int remainingSeconds;
}

/// Durable deletion and verification are in progress and cannot be cancelled.
final class DeadlockWipeWorking extends DeadlockWipeViewState {
  /// Creates the working state.
  const DeadlockWipeWorking();
}

/// Every target was verified absent and setup may begin.
final class DeadlockWipeCompleted extends DeadlockWipeViewState {
  /// Creates the completed state.
  const DeadlockWipeCompleted();
}

/// Deletion failed and the session remains blocked for retry.
final class DeadlockWipeFault extends DeadlockWipeViewState {
  /// Creates the fault state.
  const DeadlockWipeFault();
}

/// Coordinates the hidden gesture, explicit confirmation, and delayed wipe.
final class DeadlockWipeCubit extends Cubit<DeadlockWipeViewState> {
  /// Creates the coordinator around the verified wipe transaction.
  DeadlockWipeCubit(
    this._wipeVault, {
    DeadlockWipeClock? clock,
    DeadlockWipeDelay? delay,
    this.requiredTaps = 7,
    this.tapWindow = const Duration(seconds: 3),
    this.countdownSeconds = 10,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       super(const DeadlockWipeHidden());

  /// Exact language-independent word required before countdown starts.
  static const String confirmationWord = 'DELETE';

  final WipeVault _wipeVault;
  final DeadlockWipeClock _clock;
  final DeadlockWipeDelay _delay;

  /// Number of consecutive lock-icon taps required to reveal the escape path.
  final int requiredTaps;

  /// Maximum interval between taps in the hidden gesture.
  final Duration tapWindow;

  /// Cancelable delay before durable deletion begins.
  final int countdownSeconds;

  DateTime? _lastTap;
  var _tapCount = 0;
  var _countdownGeneration = 0;

  /// Records one otherwise inert tap on the lock icon.
  void registerLockIconTap() {
    if (state is! DeadlockWipeHidden) return;
    final DateTime now = _clock().toUtc();
    final DateTime? lastTap = _lastTap;
    if (lastTap == null || now.difference(lastTap) >= tapWindow) {
      _tapCount = 0;
    }
    _lastTap = now;
    _tapCount++;
    if (_tapCount >= requiredTaps) {
      _tapCount = 0;
      _lastTap = null;
      emit(const DeadlockWipeRevealed());
    }
  }

  /// Hides the form and cancels any countdown that has not started deletion.
  void hide() {
    if (state is DeadlockWipeWorking) return;
    _countdownGeneration++;
    _tapCount = 0;
    _lastTap = null;
    emit(const DeadlockWipeHidden());
  }

  /// Starts the cancelable delay only after exact typed confirmation.
  Future<void> startCountdown(String confirmation) async {
    if (state is! DeadlockWipeRevealed && state is! DeadlockWipeFault) return;
    if (confirmation != confirmationWord) {
      emit(const DeadlockWipeRevealed(confirmationInvalid: true));
      return;
    }
    final int generation = ++_countdownGeneration;
    for (var remaining = countdownSeconds; remaining > 0; remaining--) {
      if (generation != _countdownGeneration) return;
      emit(DeadlockWipeCountingDown(remaining));
      await _delay(const Duration(seconds: 1));
    }
    if (generation != _countdownGeneration) return;
    emit(const DeadlockWipeWorking());
    try {
      await _wipeVault();
      emit(const DeadlockWipeCompleted());
    } on Object {
      emit(const DeadlockWipeFault());
    }
  }

  /// Returns to the warning form while the countdown is still cancelable.
  void cancelCountdown() {
    if (state is! DeadlockWipeCountingDown) return;
    _countdownGeneration++;
    emit(const DeadlockWipeRevealed());
  }

  @override
  Future<void> close() {
    _countdownGeneration++;
    return super.close();
  }
}
