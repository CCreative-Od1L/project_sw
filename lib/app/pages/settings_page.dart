import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';

/// Security policy, active KDF metadata, and optional biometric settings.
final class SettingsPage extends StatefulWidget {
  /// Creates the settings route from process policy and vault metadata.
  const SettingsPage({
    super.key,
    this.config = const AppConfig(),
    this.vaultRepository,
    this.biometricSettingsCubit,
  });

  /// Fixed process policy used by the session and clipboard services.
  final AppConfig config;

  /// Repository projection used to read the active non-secret KDF profile.
  final VaultRepository? vaultRepository;

  /// Optional coordinator for the biometric settings card.
  final BiometricSettingsCubit? biometricSettingsCubit;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

final class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    widget.biometricSettingsCubit?.load();
  }

  @override
  Widget build(BuildContext context) {
    final BiometricSettingsCubit? cubit = widget.biometricSettingsCubit;
    if (cubit == null) {
      return _SettingsContent(
        config: widget.config,
        vaultRepository: widget.vaultRepository,
      );
    }
    return BlocProvider<BiometricSettingsCubit>.value(
      value: cubit,
      child: BlocBuilder<BiometricSettingsCubit, BiometricSettingsViewState>(
        builder: (BuildContext context, BiometricSettingsViewState state) {
          return _SettingsContent(
            config: widget.config,
            vaultRepository: widget.vaultRepository,
            biometricSettingsCubit: cubit,
            biometricState: state,
          );
        },
      ),
    );
  }
}

final class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.config,
    required this.vaultRepository,
    this.biometricSettingsCubit,
    this.biometricState,
  });

  final AppConfig config;
  final VaultRepository? vaultRepository;
  final BiometricSettingsCubit? biometricSettingsCubit;
  final BiometricSettingsViewState? biometricState;

  Future<void> _confirmAndRun(
    BuildContext context, {
    required bool enable,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.biometricSettings),
        content: Text(
          enable
              ? context.l10n.confirmEnableBiometric
              : context.l10n.confirmDisableBiometric,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.close),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              enable
                  ? context.l10n.enableBiometric
                  : context.l10n.disableBiometric,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || biometricSettingsCubit == null) return;
    if (enable) {
      await biometricSettingsCubit!.enable();
    } else {
      await biometricSettingsCubit!.disable();
    }
  }

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
          if (biometricSettingsCubit != null && biometricState != null)
            _BiometricSettingsCard(
              state: biometricState!,
              onEnable: () => _confirmAndRun(context, enable: true),
              onDisable: () => _confirmAndRun(context, enable: false),
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

final class _BiometricSettingsCard extends StatelessWidget {
  const _BiometricSettingsCard({
    required this.state,
    required this.onEnable,
    required this.onDisable,
  });

  final BiometricSettingsViewState state;
  final VoidCallback onEnable;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final String? status = switch (state) {
      BiometricSettingsReady(:final bool isConfigured) =>
        isConfigured
            ? context.l10n.biometricEnabled
            : context.l10n.biometricNotEnabled,
      BiometricSettingsFault() => context.l10n.biometricSetupFailed,
      _ => null,
    };
    final bool available = switch (state) {
      BiometricSettingsReady(:final bool isAvailable) => isAvailable,
      BiometricSettingsWorking(:final bool isAvailable) => isAvailable,
      BiometricSettingsFault(:final bool isAvailable) => isAvailable,
      _ => false,
    };
    final bool configured = switch (state) {
      BiometricSettingsReady(:final bool isConfigured) => isConfigured,
      BiometricSettingsWorking(:final bool isConfigured) => isConfigured,
      BiometricSettingsFault(:final bool isConfigured) => isConfigured,
      _ => false,
    };
    final bool working = state is BiometricSettingsWorking;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.fingerprint),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.biometricSettings,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (working)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.l10n.biometricSecurityBoundary),
            if (status != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(status),
            ],
            if (!available && state is BiometricSettingsReady) ...<Widget>[
              const SizedBox(height: 8),
              Text(context.l10n.biometricUnavailable),
            ],
            if (available && !working) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: configured ? onDisable : onEnable,
                    child: Text(
                      configured
                          ? context.l10n.disableBiometric
                          : context.l10n.enableBiometric,
                    ),
                  ),
                  if (configured)
                    OutlinedButton(
                      onPressed: onEnable,
                      child: Text(context.l10n.resetBiometric),
                    ),
                ],
              ),
            ],
          ],
        ),
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
