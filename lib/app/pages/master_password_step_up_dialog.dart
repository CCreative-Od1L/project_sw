import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/localization.dart';
import 'session_secret_dialog.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/presentation/step_up_cubit.dart';

/// Requests master-password authorization with session-owned plaintext cleanup.
Future<bool> showMasterPasswordStepUp(
  BuildContext context,
  StepUpCubit cubit,
  SessionController? sessionController,
) async {
  final bool? verified = await showDialog<bool>(
    context: context,
    builder: (_) => BlocProvider<StepUpCubit>.value(
      value: cubit,
      child: MasterPasswordStepUpDialog(
        stepUpCubit: cubit,
        sessionController: sessionController,
      ),
    ),
  );
  return verified == true;
}

/// Shared password confirmation form for privileged actions.
final class MasterPasswordStepUpDialog extends StatefulWidget {
  /// Creates a session-bound password confirmation dialog.
  const MasterPasswordStepUpDialog({
    super.key,
    required this.stepUpCubit,
    required this.sessionController,
  });

  /// Verifier that upgrades the active session.
  final StepUpCubit stepUpCubit;

  /// Session owning the dialog plaintext.
  final SessionController? sessionController;

  @override
  State<MasterPasswordStepUpDialog> createState() =>
      _MasterPasswordStepUpDialogState();
}

final class _MasterPasswordStepUpDialogState
    extends State<MasterPasswordStepUpDialog>
    with SessionSecretDialogState<MasterPasswordStepUpDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  SessionController? get sessionController => widget.sessionController;

  @override
  void clearDialogSecrets() => _controller.clear();

  @override
  void dispose() {
    _controller
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final bool verified = await widget.stepUpCubit.verify(_controller.text);
    if (verified && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StepUpCubit, StepUpViewState>(
      builder: (BuildContext context, StepUpViewState state) {
        final bool verifying = state is StepUpVerifying;
        final String? error = switch (state) {
          StepUpInvalidPassword() => context.l10n.stepUpInvalidPassword,
          StepUpFault() => context.l10n.stepUpFailed,
          StepUpUnavailable() => context.l10n.stepUpUnavailable,
          _ => null,
        };
        return AlertDialog(
          title: Text(context.l10n.stepUpTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.l10n.stepUpDescription),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !verifying,
                decoration: InputDecoration(
                  labelText: context.l10n.masterPassword,
                ),
                onSubmitted: verifying ? null : (_) => _verify(),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: verifying ? null : () => Navigator.of(context).pop(),
              child: Text(context.l10n.close),
            ),
            FilledButton(
              onPressed: verifying ? null : _verify,
              child: verifying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.confirmMasterPassword),
            ),
          ],
        );
      },
    );
  }
}
