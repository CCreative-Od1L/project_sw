import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/biometric_unlock_cubit.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';

/// Locked-vault route that accepts the master-password unlock path.
final class UnlockPage extends StatefulWidget {
  /// Creates the unlock route for [sessionController].
  const UnlockPage({
    super.key,
    required this.sessionController,
    this.unlockCubit,
    this.biometricUnlockCubit,
  });

  /// The session source of truth that owns route availability.
  final SessionController sessionController;

  /// The injected unlock form coordinator.
  final UnlockCubit? unlockCubit;

  /// The optional biometric action coordinator.
  final BiometricUnlockCubit? biometricUnlockCubit;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

final class _UnlockPageState extends State<UnlockPage>
    implements SessionSecretCleaner {
  final TextEditingController _passwordController = TextEditingController();

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
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final UnlockCubit? unlockCubit = widget.unlockCubit;
    if (unlockCubit == null) {
      return _buildContent(const UnlockReady(), onSubmit: null);
    }
    return BlocProvider<UnlockCubit>.value(
      value: unlockCubit,
      child: BlocBuilder<UnlockCubit, UnlockViewState>(
        builder: (BuildContext context, UnlockViewState state) =>
            _buildContent(state, onSubmit: _submit),
      ),
    );
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
  });

  final Future<void> Function()? onSubmit;
  final Future<void> Function()? onBiometricSubmit;
  final VoidCallback? onActivity;
  final UnlockViewState state;
  final BiometricUnlockViewState? biometricState;
  final TextEditingController controller;
  final bool canUseBiometric;

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
