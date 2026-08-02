/// Clears sensitive state owned outside the session-state value object.
abstract interface class SessionSecretCleaner {
  /// Clears all unlocked key material and decrypted session data.
  void clearUnlockedSession();
}

/// Invokes every unlocked-session cleaner from the one session lock boundary.
final class SessionSecretCleaners implements SessionSecretCleaner {
  /// Creates a fixed, ordered set of in-memory state cleaners.
  const SessionSecretCleaners(this._cleaners);

  final List<SessionSecretCleaner> _cleaners;

  @override
  void clearUnlockedSession() {
    for (final SessionSecretCleaner cleaner in _cleaners) {
      cleaner.clearUnlockedSession();
    }
  }
}
