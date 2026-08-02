/// Clears sensitive state owned outside the session-state value object.
abstract interface class SessionSecretCleaner {
  /// Clears all unlocked key material and decrypted session data.
  void clearUnlockedSession();
}
