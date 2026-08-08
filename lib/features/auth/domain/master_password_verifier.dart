/// Verifies the master password without changing the current unlocked session.
///
/// Implementations must retain only transient key material and must not expose
/// the master password or the unwrapped MVK to callers.
abstract interface class MasterPasswordVerifier {
  /// Verifies [masterPassword] against the current vault header.
  Future<void> verifyMasterPassword(String masterPassword);
}
