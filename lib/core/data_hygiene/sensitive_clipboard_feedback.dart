import 'package:flutter/material.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';

/// Shows non-sensitive copy countdown and cleanup feedback above [child].
final class SensitiveClipboardFeedback extends StatefulWidget {
  /// Creates a feedback wrapper for a page containing a [Scaffold].
  const SensitiveClipboardFeedback({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The shared sensitive clipboard controller.
  final SensitiveClipboardController controller;

  /// Page content, normally a [Scaffold].
  final Widget child;

  @override
  State<SensitiveClipboardFeedback> createState() =>
      _SensitiveClipboardFeedbackState();
}

final class _SensitiveClipboardFeedbackState
    extends State<SensitiveClipboardFeedback> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant SensitiveClipboardFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onStateChanged);
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _onStateChanged() {
    if (!mounted) return;
    final SensitiveClipboardState state = widget.controller.state;
    if (state.status == SensitiveClipboardStatus.idle) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      switch (state.status) {
        case SensitiveClipboardStatus.active:
          messenger.showSnackBar(
            SnackBar(
              duration: widget.controller.timeout + const Duration(seconds: 1),
              content: AnimatedBuilder(
                animation: widget.controller,
                builder: (BuildContext context, Widget? child) {
                  final int seconds = widget
                      .controller
                      .state
                      .remaining
                      .inSeconds
                      .ceil();
                  return Text('Sensitive value copied · clears in ${seconds}s');
                },
              ),
            ),
          );
        case SensitiveClipboardStatus.cleared:
          messenger.showSnackBar(
            const SnackBar(content: Text('Clipboard cleared')),
          );
        case SensitiveClipboardStatus.preservedReplacement:
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Clipboard changed; newer content kept'),
            ),
          );
        case SensitiveClipboardStatus.idle:
          break;
      }
    });
  }
}

/// Reusable copy action for a password or secret custom field.
final class SensitiveCopyButton extends StatelessWidget {
  /// Creates a copy action that uses the common cleanup path.
  const SensitiveCopyButton({
    super.key,
    required this.value,
    required this.controller,
    this.tooltip = 'Copy sensitive value',
  });

  /// Detail-local plaintext to copy.
  final String value;

  /// Shared cleanup controller.
  final SensitiveClipboardController controller;

  /// Non-sensitive accessibility label.
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: const Icon(Icons.copy_outlined),
    onPressed: () => controller.copySensitive(value),
  );
}
