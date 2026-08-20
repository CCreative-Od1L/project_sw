import 'dart:convert';
import 'dart:io';

import 'package:project_sw/features/auth/domain/recovery/master_password_recovery_store.dart';

/// Resolves the application-support file used for non-secret recovery state.
typedef RecoveryStatePathResolver = Future<String> Function();

/// Persists recovery deadlines as a minimal, atomically replaced JSON file.
final class FileMasterPasswordRecoveryStore
    implements MasterPasswordRecoveryStore {
  /// Creates the adapter with an application-support [pathResolver].
  const FileMasterPasswordRecoveryStore({required this.pathResolver});

  /// Resolves the recovery metadata file without exposing it to domain code.
  final RecoveryStatePathResolver pathResolver;

  @override
  Future<MasterPasswordRecoveryMetadata> read() async {
    try {
      final File file = File(await pathResolver());
      if (!await file.exists()) {
        return const MasterPasswordRecoveryMetadata();
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Recovery state must be an object.');
      }
      final DateTime? cooldownUntil = _parseDeadline(decoded, 'cooldown_until');
      final DateTime? availableUntil = _parseDeadline(
        decoded,
        'available_until',
      );
      if (cooldownUntil == null && availableUntil == null) {
        throw const FormatException('Recovery state has no deadline.');
      }
      return MasterPasswordRecoveryMetadata(
        cooldownUntil: cooldownUntil,
        availableUntil: availableUntil,
      );
    } on MasterPasswordRecoveryStoreException {
      rethrow;
    } on Object catch (error) {
      throw MasterPasswordRecoveryStoreException(cause: error);
    }
  }

  @override
  Future<void> write(MasterPasswordRecoveryMetadata metadata) async {
    File? temporary;
    try {
      if (metadata.isEmpty) {
        throw ArgumentError.value(metadata, 'metadata', 'Must not be empty.');
      }
      final String path = await pathResolver();
      final File destination = File(path);
      await destination.parent.create(recursive: true);
      temporary = File('$path.tmp');
      final Map<String, String> encoded = <String, String>{};
      final DateTime? cooldownUntil = metadata.cooldownUntil;
      final DateTime? availableUntil = metadata.availableUntil;
      if (cooldownUntil != null) {
        encoded['cooldown_until'] = cooldownUntil.toUtc().toIso8601String();
      }
      if (availableUntil != null) {
        encoded['available_until'] = availableUntil.toUtc().toIso8601String();
      }
      await temporary.writeAsString(jsonEncode(encoded), flush: true);
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
  Future<void> clear() async {
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

  DateTime? _parseDeadline(Map<String, Object?> values, String key) {
    final Object? encoded = values[key];
    if (encoded == null) return null;
    if (encoded is! String) {
      throw FormatException('$key must be a string.');
    }
    final DateTime? deadline = DateTime.tryParse(encoded);
    if (deadline == null || !deadline.isUtc) {
      throw FormatException('$key must be UTC.');
    }
    return deadline;
  }
}
