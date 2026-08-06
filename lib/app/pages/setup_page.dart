import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/presentation/setup_cubit.dart';

/// First-run route that creates an encrypted vault on this device.
final class SetupPage extends StatefulWidget {
  /// Creates the setup route for [sessionController].
  const SetupPage({
    super.key,
    required this.sessionController,
    this.setupCubit,
  });

  /// The session source of truth that owns route availability.
  final SessionController sessionController;

  /// The injected creation flow; absent only for route-focused tests.
  final SetupCubit? setupCubit;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

final class _SetupPageState extends State<SetupPage>
    implements SessionSecretCleaner {
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.sessionController.registerSecretCleaner(this);
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
    final SetupCubit? setupCubit = widget.setupCubit;
    if (setupCubit == null) {
      return;
    }
    widget.sessionController.handle(SessionEvent.userInteractionObserved);
    await setupCubit.submit(_passwordController.text);
    _passwordController.clear();
  }

  void _continueToUnlock() {
    final SetupCubit? setupCubit = widget.setupCubit;
    if (setupCubit == null || setupCubit.state is! SetupCompleted) {
      return;
    }
    widget.sessionController.markVaultCreated();
  }

  @override
  Widget build(BuildContext context) {
    final SetupCubit? setupCubit = widget.setupCubit;
    if (setupCubit == null) {
      return _SetupContent(
        onSubmit: null,
        onContinueToUnlock: null,
        onActivity: null,
        state: const SetupReady(),
        controller: _passwordController,
      );
    }
    return BlocProvider<SetupCubit>.value(
      value: setupCubit,
      child: BlocBuilder<SetupCubit, SetupViewState>(
        builder: (BuildContext context, SetupViewState state) => _SetupContent(
          onSubmit: _submit,
          onContinueToUnlock: _continueToUnlock,
          onActivity: () => widget.sessionController.handle(
            SessionEvent.userInteractionObserved,
          ),
          state: state,
          controller: _passwordController,
        ),
      ),
    );
  }
}

final class _SetupContent extends StatelessWidget {
  const _SetupContent({
    required this.onSubmit,
    required this.onContinueToUnlock,
    required this.onActivity,
    required this.state,
    required this.controller,
  });

  final Future<void> Function()? onSubmit;
  final VoidCallback? onContinueToUnlock;
  final VoidCallback? onActivity;
  final SetupViewState state;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final bool optimizing = state is SetupOptimizing;
    final SetupFailure? failure = state is SetupFailure
        ? state as SetupFailure
        : null;
    final SetupOptimizing? progress = state is SetupOptimizing
        ? state as SetupOptimizing
        : null;
    final SetupCompleted? completed = state is SetupCompleted
        ? state as SetupCompleted
        : null;
    final String progressText = progress?.progress == null
        ? context.l10n.optimizingSecurityParameters
        : context.l10n.optimizingSecurityParametersProgress(
            progress!.progress!.completedTiers,
            progress.progress!.totalTiers,
          );
    return SessionPageScaffold(
      title: context.l10n.setupTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (completed != null)
            _SetupCompletedContent(
              completed: completed,
              onContinueToUnlock: onContinueToUnlock,
            )
          else ...<Widget>[
            Text(
              context.l10n.createYourVault,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(context.l10n.vaultDescription),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              enabled: !optimizing && onSubmit != null,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.l10n.masterPassword,
              ),
              onChanged: (_) => onActivity?.call(),
            ),
            const SizedBox(height: 16),
            if (optimizing) ...<Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(progressText),
            ] else
              FilledButton.icon(
                onPressed: onSubmit == null ? null : () => onSubmit!(),
                icon: const Icon(Icons.lock_outline),
                label: Text(context.l10n.createVault),
              ),
            if (failure != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                context.l10n.vaultCreationFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

final class _SetupCompletedContent extends StatelessWidget {
  const _SetupCompletedContent({
    required this.completed,
    required this.onContinueToUnlock,
  });

  final SetupCompleted completed;
  final VoidCallback? onContinueToUnlock;

  @override
  Widget build(BuildContext context) {
    final Argon2idParameters parameters = completed.result.selectedParameters;
    final int memoryMiB = parameters.memoryKiB ~/ 1024;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.vaultCreated,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(context.l10n.securityParametersOptimized),
        const SizedBox(height: 8),
        Text(
          context.l10n.argon2idParameters(
            memoryMiB,
            parameters.iterations,
            parameters.parallelism,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onContinueToUnlock,
          child: Text(context.l10n.continueToUnlock),
        ),
      ],
    );
  }
}
