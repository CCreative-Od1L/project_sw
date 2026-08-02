import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/presentation/unlock_cubit.dart';

/// Locked-vault route that accepts the master-password unlock path.
final class UnlockPage extends StatefulWidget {
  /// Creates the unlock route for [sessionController].
  const UnlockPage({
    super.key,
    required this.sessionController,
    this.unlockCubit,
  });

  /// The session source of truth that owns route availability.
  final SessionController sessionController;

  /// The injected unlock form coordinator.
  final UnlockCubit? unlockCubit;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

final class _UnlockPageState extends State<UnlockPage> {
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final UnlockCubit? unlockCubit = widget.unlockCubit;
    if (unlockCubit == null) {
      return;
    }
    await unlockCubit.submit(_passwordController.text);
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final UnlockCubit? unlockCubit = widget.unlockCubit;
    if (unlockCubit == null) {
      return _UnlockContent(
        onSubmit: null,
        state: const UnlockReady(),
        controller: _passwordController,
      );
    }
    return BlocProvider<UnlockCubit>.value(
      value: unlockCubit,
      child: BlocBuilder<UnlockCubit, UnlockViewState>(
        builder: (BuildContext context, UnlockViewState state) =>
            _UnlockContent(
              onSubmit: _submit,
              state: state,
              controller: _passwordController,
            ),
      ),
    );
  }
}

final class _UnlockContent extends StatelessWidget {
  const _UnlockContent({
    required this.onSubmit,
    required this.state,
    required this.controller,
  });

  final Future<void> Function()? onSubmit;
  final UnlockViewState state;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final bool unlocking = state is Unlocking;
    final String? message = switch (state) {
      UnlockInvalidPassword() => 'Master password is incorrect.',
      UnlockFault() => 'Vault unlock could not be completed.',
      _ => null,
    };
    return SessionPageScaffold(
      title: 'Unlock vault',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Unlock your vault',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            enabled: !unlocking && onSubmit != null,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Master password'),
          ),
          const SizedBox(height: 16),
          if (unlocking)
            const CircularProgressIndicator()
          else
            FilledButton.icon(
              onPressed: onSubmit == null ? null : () => onSubmit!(),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Unlock'),
            ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
