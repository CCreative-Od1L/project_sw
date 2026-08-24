import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';

/// Persists an atomic Master Vault Key re-wrap under a new master password.
abstract interface class MasterPasswordChangeRepository {
  /// Verifies [currentMasterPassword], generates a fresh KDF salt, and wraps
  /// the unchanged Master Vault Key with [newMasterPassword].
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
    required SessionActivityGuard activityGuard,
  });
}
