import 'package:flutter/widgets.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';

/// Provides the process-owned clipboard controller to page-local widgets.
final class SensitiveClipboardScope
    extends InheritedNotifier<SensitiveClipboardController> {
  /// Creates a scope for [controller].
  const SensitiveClipboardScope({
    super.key,
    required SensitiveClipboardController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Returns the nearest clipboard controller, if one was composed.
  static SensitiveClipboardController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SensitiveClipboardScope>()
      ?.notifier;
}
