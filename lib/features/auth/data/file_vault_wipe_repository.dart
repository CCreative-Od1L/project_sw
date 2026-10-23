import 'dart:io';

import 'package:project_sw/features/auth/domain/biometric/biometric_key_store.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_repository.dart';
import 'package:project_sw/features/auth/domain/vault_wipe_progress_store.dart';

/// Resolves the explicit app-owned files and directories included in a wipe.
typedef VaultWipeTargetPathsResolver = Future<List<String>> Function();

/// Deletes the hardware key first, then every explicit app-data target.
final class FileVaultWipeRepository implements VaultWipeRepository {
  /// Creates the repository from a platform key store and scoped target list.
  const FileVaultWipeRepository({
    required this.biometricKeyStore,
    required this.targetPathsResolver,
    this.progressStore,
    this.removeTarget,
  });

  /// Platform-owned key material that must confirm deletion before files move.
  final BiometricKeyStore biometricKeyStore;

  /// Explicit paths owned by the application; broad roots are not accepted.
  final VaultWipeTargetPathsResolver targetPathsResolver;

  /// Durable intent, kept outside the deletion targets.
  final VaultWipeProgressStore? progressStore;

  /// Optional filesystem adapter used to exercise partial deletion failures.
  final Future<void> Function(String path)? removeTarget;

  @override
  Future<void> wipeVault() async {
    try {
      final List<String> targets = await targetPathsResolver();
      if (targets.isEmpty || targets.any(_isBroadTarget)) {
        throw const FileSystemException('Wipe target scope is invalid.');
      }
      await progressStore?.markPending();
      await biometricKeyStore.deleteKey();
      for (final String path in targets) {
        await (removeTarget ?? _delete)(path);
      }
      for (final String path in targets) {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const FileSystemException('Wipe target still exists.');
        }
      }
      await progressStore?.clear();
    } on VaultWipeException {
      rethrow;
    } on Object catch (error) {
      throw VaultWipeException(cause: error);
    }
  }

  bool _isBroadTarget(String path) {
    if (path.trim().isEmpty) return true;
    final Directory target = Directory(path).absolute;
    return target.parent.path == target.path;
  }

  Future<void> _delete(String path) async {
    switch (await FileSystemEntity.type(path, followLinks: false)) {
      case FileSystemEntityType.file:
        await File(path).delete();
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw const FileSystemException('Unsupported wipe target type.');
    }
  }
}
