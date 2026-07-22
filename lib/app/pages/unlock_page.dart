import 'package:flutter/material.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';

/// Locked-vault route reserved for the future unlock use case.
final class UnlockPage extends StatelessWidget {
  /// Creates the unlock route for [sessionController].
  const UnlockPage({super.key, required this.sessionController});

  /// The session source of truth that owns route availability.
  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
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
          const TextField(
            enabled: false,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Master password'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Unlock'),
          ),
        ],
      ),
    );
  }
}
