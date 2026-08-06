import 'package:flutter/material.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';

/// Read-only security policy and active vault KDF information.
final class SettingsPage extends StatelessWidget {
  /// Creates the settings route from process policy and vault metadata.
  const SettingsPage({
    super.key,
    this.config = const AppConfig(),
    this.vaultRepository,
  });

  /// Fixed process policy used by the session and clipboard services.
  final AppConfig config;

  /// Repository projection used to read the active non-secret KDF profile.
  final VaultRepository? vaultRepository;

  @override
  Widget build(BuildContext context) {
    final Argon2idParameters? kdf = vaultRepository?.activeKdfParameters;
    return SessionPageScaffold(
      title: context.l10n.settings,
      child: ListView(
        children: <Widget>[
          Text(
            context.l10n.securitySettingsReadOnly,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          _PolicyCard(
            icon: Icons.timer_outlined,
            title: context.l10n.idleLockPolicy,
            value: context.l10n.idleLockPolicyValue(
              config.idleTimeout.inMinutes,
            ),
          ),
          _PolicyCard(
            icon: Icons.phonelink_lock_outlined,
            title: context.l10n.backgroundLockPolicy,
            value: context.l10n.backgroundLockPolicyValue,
          ),
          _PolicyCard(
            icon: Icons.content_paste_off_outlined,
            title: context.l10n.clipboardPolicy,
            value: context.l10n.clipboardPolicyValue(
              config.sensitiveClipboardTimeout.inSeconds,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.security_outlined),
              title: Text(context.l10n.kdfPolicy),
              subtitle: Text(
                kdf == null
                    ? context.l10n.kdfPolicyUnavailable
                    : context.l10n.argon2idParameters(
                        kdf.memoryKiB ~/ 1024,
                        kdf.iterations,
                        kdf.parallelism,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsNoCredentials,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
    ),
  );
}
