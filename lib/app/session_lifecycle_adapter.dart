import 'package:flutter/widgets.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';

/// Converts Flutter lifecycle callbacks into project-owned session events.
final class SessionLifecycleAdapter extends StatefulWidget {
  /// Creates the adapter around the application widget tree.
  const SessionLifecycleAdapter({
    super.key,
    required this.sessionController,
    required this.child,
    this.onForegrounded,
  });

  /// The global session source of truth.
  final SessionController sessionController;

  /// Optional foreground callback for timed data-hygiene services.
  final VoidCallback? onForegrounded;

  /// The application widget tree.
  final Widget child;

  @override
  State<SessionLifecycleAdapter> createState() =>
      _SessionLifecycleAdapterState();
}

final class _SessionLifecycleAdapterState extends State<SessionLifecycleAdapter>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final SessionEvent? event = sessionEventForLifecycleState(state);
    if (event == SessionEvent.appForegrounded) {
      widget.onForegrounded?.call();
    }
    if (event != null) {
      widget.sessionController.handle(event);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) =>
        widget.sessionController.handle(SessionEvent.userInteractionObserved),
    child: NotificationListener<ScrollNotification>(
      onNotification: (_) {
        widget.sessionController.handle(SessionEvent.userInteractionObserved);
        return false;
      },
      child: widget.child,
    ),
  );
}

/// Maps platform lifecycle values without exposing Flutter types to domain.
SessionEvent? sessionEventForLifecycleState(AppLifecycleState state) =>
    switch (state) {
      AppLifecycleState.resumed => SessionEvent.appForegrounded,
      AppLifecycleState.paused ||
      AppLifecycleState.detached => SessionEvent.appBackgrounded,
      AppLifecycleState.inactive || AppLifecycleState.hidden => null,
    };

/// Resets the session timer when the navigator records user navigation.
final class SessionNavigationObserver extends NavigatorObserver {
  /// Creates an observer bound to [sessionController].
  SessionNavigationObserver(this.sessionController);

  /// The global session source of truth.
  final SessionController sessionController;

  @override
  void didPush(Route<void> route, Route<void>? previousRoute) {
    sessionController.handle(SessionEvent.userInteractionObserved);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<void> route, Route<void>? previousRoute) {
    sessionController.handle(SessionEvent.userInteractionObserved);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<void>? newRoute, Route<void>? oldRoute}) {
    sessionController.handle(SessionEvent.userInteractionObserved);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
