import 'package:flutter/material.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';

/// Placeholder route replaced by the security settings slice in #35.
final class SettingsPage extends StatelessWidget {
  /// Creates the settings route placeholder.
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => SessionPageScaffold(
    title: context.l10n.settings,
    child: Center(child: Text(context.l10n.settingsComingSoon)),
  );
}
