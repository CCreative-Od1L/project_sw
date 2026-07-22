import 'package:flutter/material.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';

/// Minimal unlocked route used to verify session-driven routing.
final class HomePage extends StatelessWidget {
  /// Creates the home route for [sessionController].
  const HomePage({super.key, required this.sessionController});

  /// The session source of truth that owns locking.
  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    return SessionPageScaffold(
      title: 'Vault',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Vault unlocked',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text('No entries have been added yet.'),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Lock vault',
              onPressed: () => sessionController.lock(LockReason.manualLock),
            ),
          ),
        ],
      ),
    );
  }
}
