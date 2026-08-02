import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
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

final class _SetupPageState extends State<SetupPage> {
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final SetupCubit? setupCubit = widget.setupCubit;
    if (setupCubit == null) {
      return;
    }
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
    required this.state,
    required this.controller,
  });

  final Future<void> Function()? onSubmit;
  final VoidCallback? onContinueToUnlock;
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
        ? 'Optimizing security parameters…'
        : 'Optimizing security parameters… ${progress!.progress!.completedTiers}/${progress.progress!.totalTiers}';
    return SessionPageScaffold(
      title: 'Project SW',
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
              'Create your vault',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text('Your encrypted vault will be created on this device.'),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              enabled: !optimizing && onSubmit != null,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Master password'),
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
                label: const Text('Create vault'),
              ),
            if (failure != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                failure.message,
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
          'Vault created',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text('Security parameters optimized for this device:'),
        const SizedBox(height: 8),
        Text(
          'Argon2id: m=$memoryMiB MiB, '
          't=${parameters.iterations}, p=${parameters.parallelism}',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onContinueToUnlock,
          child: const Text('Continue to unlock'),
        ),
      ],
    );
  }
}
