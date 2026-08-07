import 'package:flutter/material.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';

/// Reusable copy action for a password or secret custom field.
final class SensitiveCopyButton extends StatelessWidget {
  /// Creates a copy action that uses the common cleanup path.
  const SensitiveCopyButton({
    super.key,
    required this.value,
    required this.controller,
    this.tooltip,
  });

  /// Detail-local plaintext to copy.
  final String value;

  /// Shared cleanup controller.
  final SensitiveClipboardController controller;

  /// Non-sensitive accessibility label.
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip ?? context.l10n.copySensitiveValue,
    icon: const Icon(Icons.copy_outlined),
    onPressed: () => _copy(context),
  );

  Future<void> _copy(BuildContext context) async {
    await controller.copySensitive(value);
    if (!context.mounted) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    messenger
      ?..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.sensitiveCopied)));
  }
}
