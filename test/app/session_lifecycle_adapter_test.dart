import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/session_lifecycle_adapter.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';

void main() {
  test('only pause and detach map to the immediate background lock event', () {
    expect(
      sessionEventForLifecycleState(AppLifecycleState.paused),
      SessionEvent.appBackgrounded,
    );
    expect(
      sessionEventForLifecycleState(AppLifecycleState.detached),
      SessionEvent.appBackgrounded,
    );
    expect(sessionEventForLifecycleState(AppLifecycleState.inactive), isNull);
    expect(sessionEventForLifecycleState(AppLifecycleState.hidden), isNull);
    expect(
      sessionEventForLifecycleState(AppLifecycleState.resumed),
      SessionEvent.appForegrounded,
    );
  });
}
