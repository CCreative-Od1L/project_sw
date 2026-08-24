/// Read-only guard passed into sensitive work owned by a session activity.
abstract interface class SessionActivityGuard {
  /// Throws when the activity no longer owns the unlocked session.
  void ensureActive();
}
