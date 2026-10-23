import 'dart:io';

import 'package:project_sw/features/auth/domain/vault_wipe_progress_store.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';

/// Resolves the dedicated marker outside the set of wipe targets.
typedef WipeProgressPathResolver = Future<String> Function();

/// Uses marker existence as intent, including empty or interrupted writes.
final class FileVaultWipeProgressStore implements VaultWipeProgressStore {
  /// Creates the store for one application-support marker file.
  const FileVaultWipeProgressStore({required this.pathResolver});

  /// Resolves the non-secret marker path.
  final WipeProgressPathResolver pathResolver;

  @override
  Future<bool> readPending() async {
    try {
      return await FileSystemEntity.type(
            await pathResolver(),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound;
    } on Object catch (error) {
      throw VaultWipeException(cause: error);
    }
  }

  @override
  Future<void> markPending() async {
    try {
      final String path = await pathResolver();
      final FileSystemEntityType type = await FileSystemEntity.type(
        path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        throw const FileSystemException('Wipe marker is not a regular file.');
      }
      final File marker = File(path);
      await marker.parent.create(recursive: true);
      await marker.writeAsString('pending\n', flush: true);
    } on Object catch (error) {
      throw VaultWipeException(cause: error);
    }
  }

  @override
  Future<void> clear() async {
    try {
      final String path = await pathResolver();
      final FileSystemEntityType type = await FileSystemEntity.type(
        path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) return;
      if (type != FileSystemEntityType.file) {
        throw const FileSystemException('Wipe marker is not a regular file.');
      }
      await File(path).delete();
    } on Object catch (error) {
      throw VaultWipeException(cause: error);
    }
  }
}
