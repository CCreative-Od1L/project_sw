import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/create_vault.dart';

/// UI state for the first-vault creation flow.
sealed class SetupViewState {
  /// Creates setup state values.
  const SetupViewState();
}

/// The form is ready for a master-password submission.
final class SetupReady extends SetupViewState {
  /// Creates the ready state.
  const SetupReady();
}

/// Non-cancellable Argon2id parameter optimization is running.
final class SetupOptimizing extends SetupViewState {
  /// Creates an optimizing state.
  const SetupOptimizing(this.progress);

  /// Current benchmark progress.
  final Argon2idBenchmarkProgress? progress;
}

/// The vault was written successfully.
final class SetupCompleted extends SetupViewState {
  /// Creates the success state.
  const SetupCompleted();
}

/// A normalized failure that can be shown without exposing secret data.
final class SetupFailure extends SetupViewState {
  /// Creates a failure state.
  const SetupFailure(this.message);

  /// Safe, user-facing error text.
  final String message;
}

/// Coordinates only setup-page interaction state around [CreateVault].
final class SetupCubit extends Cubit<SetupViewState> {
  /// Creates a setup projection around the use case.
  SetupCubit(this._createVault) : super(const SetupReady());

  final CreateVault _createVault;

  /// Creates a vault and emits progress; there is intentionally no cancel API.
  Future<void> submit(String masterPassword) async {
    if (state is SetupOptimizing) {
      return;
    }
    emit(const SetupOptimizing(null));
    try {
      await _createVault(
        masterPassword,
        onProgress: (Argon2idBenchmarkProgress progress) {
          emit(SetupOptimizing(progress));
        },
      );
      emit(const SetupCompleted());
    } on Object {
      emit(const SetupFailure('Vault creation could not be completed.'));
    }
  }
}
