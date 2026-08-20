import 'dart:convert';
import 'dart:io';

import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';

/// Resolves the application-support file used for non-secret recovery state.
typedef RecoveryStatePathResolver = Future<String> Function();

/// Persists the recovery cooldown as a minimal, atomically replaced JSON file.
final class FileMasterPasswordRecoveryStore
    implements MasterPasswordRecoveryStore {
  /// Creates the adapter with an application-support [pathResolver].
  const FileMasterPasswordRecoveryStore({required this.pathResolver});

  /// Resolves the recovery metadata file without exposing it to domain code.
  final RecoveryStatePathResolver pathResolver;

  @override
  Future<DateTime?> readCooldownUntil() async {
    try {
      final File file = File(await pathResolver());
      if (!await file.exists()) return null;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Recovery state must be an object.');
      }
      final Object? encodedDeadline = decoded['cooldown_until'];
      if (encodedDeadline is! String) {
        throw const FormatException('Recovery cooldown is missing.');
      }
      final DateTime? deadline = DateTime.tryParse(encodedDeadline);
      if (deadline == null || !deadline.isUtc) {
        throw const FormatException('Recovery cooldown must be UTC.');
      }
      return deadline;
    } on MasterPasswordRecoveryStoreException {
      rethrow;
    } on Object catch (error) {
      throw MasterPasswordRecoveryStoreException(cause: error);
    }
  }

  @override
  Future<void> writeCooldownUntil(DateTime value) async {
    File? temporary;
    try {
      final String path = await pathResolver();
      final File destination = File(path);
      await destination.parent.create(recursive: true);
      temporary = File('$path.tmp');
      await temporary.writeAsString(
        jsonEncode(<String, String>{
          'cooldown_until': value.toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await temporary.rename(path);
      temporary = null;
    } on MasterPasswordRecoveryStoreException {
      rethrow;
    } on Object catch (error) {
      throw MasterPasswordRecoveryStoreException(cause: error);
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<void> clearCooldown() async {
    try {
      final String path = await pathResolver();
      for (final File file in <File>[File(path), File('$path.tmp')]) {
        if (await file.exists()) {
          await file.delete();
        }
      }
    } on MasterPasswordRecoveryStoreException {
      rethrow;
    } on Object catch (error) {
      throw MasterPasswordRecoveryStoreException(cause: error);
    }
  }
}
