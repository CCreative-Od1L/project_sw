import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/features/auth/presentation/deadlock_wipe_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';

/// Locked-vault route that accepts the master-password unlock path.
final class UnlockPage extends StatefulWidget {
  /// Creates the unlock route for [sessionController].
  const UnlockPage({
    super.key,
    required this.sessionController,
    this.unlockCubit,
    this.biometricUnlockCubit,
    this.deadlockWipeCubit,
  });

  /// The session source of truth that owns route availability.
  final SessionController sessionController;

  /// The injected unlock form coordinator.
  final UnlockCubit? unlockCubit;

  /// The optional biometric action coordinator.
  final BiometricUnlockCubit? biometricUnlockCubit;

  /// Optional hidden deadlock-wipe escape path coordinator.
  final DeadlockWipeCubit? deadlockWipeCubit;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

final class _UnlockPageState extends State<UnlockPage>
    implements SessionSecretCleaner {
  final TextEditingController _passwordController = TextEditingController();
  var _wipeDialogOpen = false;

  @override
  void initState() {
    super.initState();
    widget.sessionController.registerSecretCleaner(this);
    widget.biometricUnlockCubit?.loadAvailability();
  }

  @override
  void dispose() {
    widget.sessionController.unregisterSecretCleaner(this);
    _passwordController
      ..clear()
      ..dispose();
    super.dispose();
  }

  @override
  void clearUnlockedSession() => _passwordController.clear();

  Future<void> _submit() async {
    final UnlockCubit? unlockCubit = widget.unlockCubit;
    if (unlockCubit == null) {
      return;
    }
    widget.sessionController.handle(SessionEvent.userInteractionObserved);
    await unlockCubit.submit(_passwordController.text);
    _passwordController.clear();
  }

  Future<void> _submitBiometric() async {
    final BiometricUnlockCubit? biometricUnlockCubit =
        widget.biometricUnlockCubit;
    if (biometricUnlockCubit == null) return;
    widget.sessionController.handle(SessionEvent.userInteractionObserved);
    await biometricUnlockCubit.unlock();
  }

  Widget _buildContent(
    UnlockViewState unlockState, {
    required Future<void> Function()? onSubmit,
  }) {
    final BiometricUnlockCubit? biometricUnlockCubit =
        widget.biometricUnlockCubit;
    if (biometricUnlockCubit == null) {
      return _UnlockContent(
        onSubmit: onSubmit,
        onBiometricSubmit: null,
        onActivity: () => widget.sessionController.handle(
          SessionEvent.userInteractionObserved,
        ),
        state: unlockState,
        biometricState: null,
        controller: _passwordController,
        canUseBiometric: false,
        onLockIconTap: widget.deadlockWipeCubit?.registerLockIconTap,
      );
    }
    return BlocProvider<BiometricUnlockCubit>.value(
      value: biometricUnlockCubit,
      child: BlocBuilder<BiometricUnlockCubit, BiometricUnlockViewState>(
        builder: (BuildContext context, BiometricUnlockViewState state) {
          final bool canUseBiometric =
              widget.sessionController.state is LockedSession &&
              (widget.sessionController.state as LockedSession).canUseBiometric;
          return _UnlockContent(
            onSubmit: onSubmit,
            onBiometricSubmit: _submitBiometric,
            onActivity: () => widget.sessionController.handle(
              SessionEvent.userInteractionObserved,
            ),
            state: unlockState,
            biometricState: state,
            controller: _passwordController,
            canUseBiometric: canUseBiometric,
            onLockIconTap: widget.deadlockWipeCubit?.registerLockIconTap,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final UnlockCubit? unlockCubit = widget.unlockCubit;
    final Widget content;
    if (unlockCubit == null) {
      content = _buildContent(const UnlockReady(), onSubmit: null);
    } else {
      content = BlocProvider<UnlockCubit>.value(
        value: unlockCubit,
        child: BlocBuilder<UnlockCubit, UnlockViewState>(
          builder: (BuildContext context, UnlockViewState state) =>
              _buildContent(state, onSubmit: _submit),
        ),
      );
    }
    final DeadlockWipeCubit? wipeCubit = widget.deadlockWipeCubit;
    if (wipeCubit == null) return content;
    return BlocProvider<DeadlockWipeCubit>.value(
      value: wipeCubit,
      child: BlocListener<DeadlockWipeCubit, DeadlockWipeViewState>(
        listener: (BuildContext context, DeadlockWipeViewState state) {
          if (state is DeadlockWipeRevealed && !_wipeDialogOpen) {
            _showDeadlockWipeDialog(context, wipeCubit);
          }
        },
        child: content,
      ),
    );
  }

  Future<void> _showDeadlockWipeDialog(
    BuildContext context,
    DeadlockWipeCubit cubit,
  ) async {
    _wipeDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => BlocProvider<DeadlockWipeCubit>.value(
        value: cubit,
        child: const _DeadlockWipeDialog(),
      ),
    );
    _wipeDialogOpen = false;
    if (mounted &&
        cubit.state is! DeadlockWipeCompleted &&
        cubit.state is! DeadlockWipeWorking) {
      cubit.hide();
    }
  }
}

final class _UnlockContent extends StatelessWidget {
  const _UnlockContent({
    required this.onSubmit,
    required this.onBiometricSubmit,
    required this.onActivity,
    required this.state,
    required this.biometricState,
    required this.controller,
    required this.canUseBiometric,
    required this.onLockIconTap,
  });

  final Future<void> Function()? onSubmit;
  final Future<void> Function()? onBiometricSubmit;
  final VoidCallback? onActivity;
  final UnlockViewState state;
  final BiometricUnlockViewState? biometricState;
  final TextEditingController controller;
  final bool canUseBiometric;
  final VoidCallback? onLockIconTap;

  @override
  Widget build(BuildContext context) {
    final bool unlocking = state is Unlocking;
    final bool biometricUnlocking = biometricState is BiometricUnlocking;
    final String? message = switch (state) {
      UnlockInvalidPassword() => context.l10n.incorrectMasterPassword,
      UnlockFault() => context.l10n.vaultUnlockFailed,
      _ => null,
    };
    final String? biometricMessage = switch (biometricState) {
      BiometricUnlockCancelled() => context.l10n.biometricCancelled,
      BiometricUnlockInvalidated() => context.l10n.biometricInvalidated,
      BiometricUnlockUnavailable() => context.l10n.biometricUnavailable,
      BiometricUnlockFault() => context.l10n.biometricUnlockFailed,
      _ => null,
    };
    final bool showBiometric =
        canUseBiometric &&
        onBiometricSubmit != null &&
        biometricState is BiometricUnlockReady &&
        (biometricState as BiometricUnlockReady).isConfigured &&
        (biometricState as BiometricUnlockReady).isAvailable;
    return SessionPageScaffold(
      title: context.l10n.unlockVault,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: InkResponse(
              key: const ValueKey<String>('deadlock-wipe-trigger'),
              onTap: onLockIconTap,
              radius: 32,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.lock_outline_rounded, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.unlockYourVault,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            enabled: !unlocking && !biometricUnlocking && onSubmit != null,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: context.l10n.masterPassword),
            onChanged: (_) => onActivity?.call(),
          ),
          const SizedBox(height: 16),
          if (unlocking)
            const CircularProgressIndicator()
          else
            FilledButton.icon(
              onPressed: onSubmit == null || biometricUnlocking
                  ? null
                  : () => onSubmit!(),
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(context.l10n.unlock),
            ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (showBiometric) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: biometricUnlocking ? null : () => onBiometricSubmit!(),
              icon: const Icon(Icons.fingerprint),
              label: Text(context.l10n.useBiometric),
            ),
          ],
          if (biometricUnlocking) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (biometricMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              biometricMessage,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

final class _DeadlockWipeDialog extends StatefulWidget {
  const _DeadlockWipeDialog();

  @override
  State<_DeadlockWipeDialog> createState() => _DeadlockWipeDialogState();
}

final class _DeadlockWipeDialogState extends State<_DeadlockWipeDialog> {
  final TextEditingController _confirmationController = TextEditingController();

  @override
  void dispose() {
    _confirmationController
      ..clear()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DeadlockWipeCubit, DeadlockWipeViewState>(
      listener: (BuildContext context, DeadlockWipeViewState state) {
        if (state is DeadlockWipeCompleted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      builder: (BuildContext context, DeadlockWipeViewState state) {
        final bool countingDown = state is DeadlockWipeCountingDown;
        final bool working = state is DeadlockWipeWorking;
        final bool confirmationInvalid = switch (state) {
          DeadlockWipeRevealed(:final bool confirmationInvalid) =>
            confirmationInvalid,
          _ => false,
        };
        return AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(context.l10n.deadlockWipeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.deadlockWipeWarning,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (countingDown)
                Text(
                  context.l10n.deadlockWipeCountdown(state.remainingSeconds),
                  style: Theme.of(context).textTheme.titleMedium,
                )
              else if (working) ...<Widget>[
                Text(context.l10n.deadlockWipeWorking),
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ] else ...<Widget>[
                Text(context.l10n.deadlockWipeInstructions),
                if (state is DeadlockWipeFault) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.deadlockWipeFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey<String>('deadlock-wipe-confirmation'),
                  controller: _confirmationController,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !working,
                  decoration: InputDecoration(
                    labelText: context.l10n.deadlockWipeConfirmation,
                    errorText: confirmationInvalid
                        ? context.l10n.deadlockWipeConfirmationInvalid
                        : null,
                  ),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            if (countingDown)
              TextButton(
                onPressed: context.read<DeadlockWipeCubit>().cancelCountdown,
                child: Text(context.l10n.cancelDeadlockWipe),
              )
            else if (!working) ...<Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.close),
              ),
              FilledButton(
                onPressed: () => context
                    .read<DeadlockWipeCubit>()
                    .startCountdown(_confirmationController.text),
                child: Text(context.l10n.startDeadlockWipeCountdown),
              ),
            ],
          ],
        );
      },
    );
  }
}
