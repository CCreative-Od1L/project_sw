import 'package:flutter/material.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';

/// Binds a dialog-owned plaintext scope to the global session lock boundary.
mixin SessionSecretDialogState<T extends StatefulWidget> on State<T>
    implements SessionSecretCleaner {
  /// Session source that owns this dialog's lock lifecycle.
  SessionController? get sessionController;

  /// Clears every plaintext value owned by the concrete dialog.
  void clearDialogSecrets();

  var _dismissScheduled = false;

  @override
  void initState() {
    super.initState();
    sessionController?.registerSecretCleaner(this);
  }

  @override
  void dispose() {
    sessionController?.unregisterSecretCleaner(this);
    super.dispose();
  }

  @override
  void clearUnlockedSession() {
    clearDialogSecrets();
    if (!mounted || _dismissScheduled) return;
    _dismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    });
  }
}
