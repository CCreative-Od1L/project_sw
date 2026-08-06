/// Events understood by the global session source of truth.
enum SessionEvent {
  /// The application has returned to the foreground.
  appForegrounded,

  /// The application has entered a background state that must lock.
  appBackgrounded,

  /// The user interacted with the foreground application.
  userInteractionObserved,

  /// The owned idle timer reached its deadline.
  idleTimeoutElapsed,
}
