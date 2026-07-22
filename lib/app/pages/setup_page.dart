import 'package:flutter/material.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';

/// First-run route shown while no vault exists on this device.
final class SetupPage extends StatelessWidget {
  /// Creates the setup route for [sessionController].
  const SetupPage({super.key, required this.sessionController});

  /// The session source of truth that owns route availability.
  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    return SessionPageScaffold(
      title: 'Project SW',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Create your vault',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text('Your encrypted vault will be created on this device.'),
          const SizedBox(height: 24),
          const TextField(
            enabled: false,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Master password'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Create vault'),
          ),
        ],
      ),
    );
  }
}
