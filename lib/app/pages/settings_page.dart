import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/crypto/argon2id_benchmark.dart';
import 'package:project_sw/features/auth/domain/master_password_strength.dart';
import 'package:project_sw/features/auth/domain/vault_repository.dart';
import 'package:project_sw/features/auth/presentation/biometric_settings_cubit.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';
import 'package:project_sw/features/auth/presentation/step_up_cubit.dart';

/// Security policy, active KDF metadata, and optional biometric settings.
final class SettingsPage extends StatefulWidget {
  /// Creates the settings route from process policy and vault metadata.
  const SettingsPage({
    super.key,
    this.config = const AppConfig(),
    this.vaultRepository,
    this.biometricSettingsCubit,
    this.stepUpCubit,
    this.masterPasswordChangeCubit,
  });

  /// Fixed process policy used by the session and clipboard services.
  final AppConfig config;

  /// Repository projection used to read the active non-secret KDF profile.
  final VaultRepository? vaultRepository;

  /// Optional coordinator for the biometric settings card.
  final BiometricSettingsCubit? biometricSettingsCubit;

  /// Optional high-sensitivity master-password challenge coordinator.
  final StepUpCubit? stepUpCubit;

  /// Optional coordinator for the master-password change dialog.
  final MasterPasswordChangeCubit? masterPasswordChangeCubit;

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
        stepUpCubit: widget.stepUpCubit,
        masterPasswordChangeCubit: widget.masterPasswordChangeCubit,
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
            stepUpCubit: widget.stepUpCubit,
            masterPasswordChangeCubit: widget.masterPasswordChangeCubit,
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
    this.stepUpCubit,
    this.masterPasswordChangeCubit,
  });

  final AppConfig config;
  final VaultRepository? vaultRepository;
  final BiometricSettingsCubit? biometricSettingsCubit;
  final BiometricSettingsViewState? biometricState;
  final StepUpCubit? stepUpCubit;
  final MasterPasswordChangeCubit? masterPasswordChangeCubit;

  Future<void> _showMasterPasswordChange(BuildContext context) async {
    final MasterPasswordChangeCubit? cubit = masterPasswordChangeCubit;
    if (cubit == null) return;
    await cubit.reset();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          BlocProvider<MasterPasswordChangeCubit>.value(
            value: cubit,
            child: const _MasterPasswordChangeDialog(),
          ),
    );
  }

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
    if (!context.mounted) return;
    if (!await _authorizeMasterPassword(context)) return;
    if (enable) {
      await biometricSettingsCubit!.enable();
    } else {
      await biometricSettingsCubit!.disable();
    }
  }

  Future<bool> _authorizeMasterPassword(BuildContext context) async {
    final StepUpCubit? cubit = stepUpCubit;
    if (cubit == null || !cubit.requiresMasterPassword) {
      return true;
    }
    final bool? verified = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => BlocProvider<StepUpCubit>.value(
        value: cubit,
        child: _StepUpDialog(stepUpCubit: cubit),
      ),
    );
    return verified == true;
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
          if (masterPasswordChangeCubit != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.password_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.masterPasswordSettings,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(context.l10n.masterPasswordChangeDescription),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.tonal(
                        onPressed: () => _showMasterPasswordChange(context),
                        child: Text(context.l10n.changeMasterPassword),
                      ),
                    ),
                  ],
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
      BiometricSettingsInvalidated() =>
        context.l10n.biometricSettingsInvalidated,
      _ => null,
    };
    final bool available = switch (state) {
      BiometricSettingsReady(:final bool isAvailable) => isAvailable,
      BiometricSettingsWorking(:final bool isAvailable) => isAvailable,
      BiometricSettingsFault(:final bool isAvailable) => isAvailable,
      BiometricSettingsInvalidated(:final bool isAvailable) => isAvailable,
      _ => false,
    };
    final bool configured = switch (state) {
      BiometricSettingsReady(:final bool isConfigured) => isConfigured,
      BiometricSettingsWorking(:final bool isConfigured) => isConfigured,
      BiometricSettingsFault(:final bool isConfigured) => isConfigured,
      BiometricSettingsInvalidated(:final bool isConfigured) => isConfigured,
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
            if (available &&
                !working &&
                state is! BiometricSettingsInvalidated) ...<Widget>[
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

final class _MasterPasswordChangeDialog extends StatefulWidget {
  const _MasterPasswordChangeDialog();

  @override
  State<_MasterPasswordChangeDialog> createState() =>
      _MasterPasswordChangeDialogState();
}

final class _MasterPasswordChangeDialogState
    extends State<_MasterPasswordChangeDialog> {
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();
  final MasterPasswordStrengthEvaluator _strengthEvaluator =
      const MasterPasswordStrengthEvaluator();
  var _recoveryMode = false;
  MasterPasswordStrengthAssessment? _strengthAssessment;

  @override
  void dispose() {
    _currentController
      ..clear()
      ..dispose();
    _newController
      ..clear()
      ..dispose();
    _confirmationController
      ..clear()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<
      MasterPasswordChangeCubit,
      MasterPasswordChangeViewState
    >(
      listener: (BuildContext context, MasterPasswordChangeViewState state) {
        if (state is MasterPasswordChangeCompleted ||
            state is MasterPasswordRecoveryCompleted) {
          final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
            context,
          );
          Navigator.of(context).pop();
          messenger.showSnackBar(
            SnackBar(
              content: state is MasterPasswordRecoveryCompleted
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(context.l10n.masterPasswordRecovered),
                        Text(context.l10n.syncRecoveryBackup),
                      ],
                    )
                  : Text(context.l10n.masterPasswordChanged),
            ),
          );
        }
      },
      builder: (BuildContext context, MasterPasswordChangeViewState state) {
        final bool working =
            state is MasterPasswordChangeWorking ||
            state is MasterPasswordRecoveryWorking;
        final String? errorText = switch (state) {
          MasterPasswordChangeInvalidCurrent() =>
            context.l10n.currentMasterPasswordInvalid,
          MasterPasswordChangeInvalidNew() =>
            context.l10n.newMasterPasswordRequired,
          MasterPasswordChangeConfirmationMismatch() =>
            context.l10n.newMasterPasswordsDoNotMatch,
          MasterPasswordChangeFault() =>
            context.l10n.masterPasswordChangeFailed,
          MasterPasswordRecoveryInvalidNew() =>
            context.l10n.newMasterPasswordRequired,
          MasterPasswordRecoveryWeakNew() =>
            context.l10n.newMasterPasswordTooWeak,
          MasterPasswordRecoveryConfirmationMismatch() =>
            context.l10n.newMasterPasswordsDoNotMatch,
          MasterPasswordRecoveryUnavailable() =>
            context.l10n.masterPasswordRecoveryUnavailable,
          MasterPasswordRecoveryBiometricCancelled() =>
            context.l10n.masterPasswordRecoveryCancelled,
          MasterPasswordRecoveryBiometricUnavailable() =>
            context.l10n.masterPasswordRecoveryBiometricUnavailable,
          MasterPasswordRecoveryFault() =>
            context.l10n.masterPasswordRecoveryFailed,
          _ => null,
        };
        final bool recoveryAvailable = switch (state) {
          MasterPasswordChangeReady(:final bool recoveryAvailable) =>
            recoveryAvailable,
          MasterPasswordChangeInvalidCurrent(:final bool recoveryAvailable) =>
            recoveryAvailable,
          _ => false,
        };
        return AlertDialog(
          title: Text(
            _recoveryMode
                ? context.l10n.recoverMasterPasswordTitle
                : context.l10n.changeMasterPasswordTitle,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_recoveryMode)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.masterPasswordRecoveryWarning,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(context.l10n.masterPasswordChangeWarning),
                const SizedBox(height: 16),
                if (!_recoveryMode) ...<Widget>[
                  TextField(
                    key: const ValueKey<String>('current-master-password'),
                    controller: _currentController,
                    autofocus: true,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !working,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: context.l10n.currentMasterPassword,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const ValueKey<String>('new-master-password'),
                  controller: _newController,
                  autofocus: _recoveryMode,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !working,
                  textInputAction: TextInputAction.next,
                  onChanged: _recoveryMode
                      ? (String value) {
                          setState(() {
                            _strengthAssessment = _strengthEvaluator.evaluate(
                              value,
                            );
                          });
                        }
                      : null,
                  decoration: InputDecoration(
                    labelText: context.l10n.newMasterPassword,
                  ),
                ),
                if (_recoveryMode && _strengthAssessment != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.masterPasswordStrengthLabel(
                      _strengthLabel(context, _strengthAssessment!.strength),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('confirm-new-master-password'),
                  controller: _confirmationController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !working,
                  onSubmitted: working
                      ? null
                      : (_) => _recoveryMode
                            ? _recover(context)
                            : _submit(context),
                  decoration: InputDecoration(
                    labelText: context.l10n.confirmNewMasterPassword,
                    errorText: errorText,
                  ),
                ),
                if (!_recoveryMode && recoveryAvailable) ...<Widget>[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: working ? null : _enterRecoveryMode,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(context.l10n.recoverWithBiometrics),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: working ? null : () => Navigator.of(context).pop(),
              child: Text(context.l10n.close),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () => _recoveryMode ? _recover(context) : _submit(context),
              child: working
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _recoveryMode
                          ? context.l10n.recoverPassword
                          : context.l10n.changePassword,
                    ),
            ),
          ],
        );
      },
    );
  }

  void _submit(BuildContext context) {
    context.read<MasterPasswordChangeCubit>().submit(
      currentMasterPassword: _currentController.text,
      newMasterPassword: _newController.text,
      confirmation: _confirmationController.text,
    );
  }

  void _enterRecoveryMode() {
    _currentController.clear();
    _newController.clear();
    _confirmationController.clear();
    setState(() {
      _recoveryMode = true;
      _strengthAssessment = null;
    });
  }

  void _recover(BuildContext context) {
    context.read<MasterPasswordChangeCubit>().recover(
      newMasterPassword: _newController.text,
      confirmation: _confirmationController.text,
    );
  }

  String _strengthLabel(
    BuildContext context,
    MasterPasswordStrength strength,
  ) => switch (strength) {
    MasterPasswordStrength.weak => context.l10n.strengthWeak,
    MasterPasswordStrength.medium => context.l10n.strengthMedium,
    MasterPasswordStrength.strong => context.l10n.strengthStrong,
    MasterPasswordStrength.veryStrong => context.l10n.strengthVeryStrong,
  };
}

final class _StepUpDialog extends StatefulWidget {
  const _StepUpDialog({required this.stepUpCubit});

  final StepUpCubit stepUpCubit;

  @override
  State<_StepUpDialog> createState() => _StepUpDialogState();
}

final class _StepUpDialogState extends State<_StepUpDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final bool verified = await widget.stepUpCubit.verify(_controller.text);
    if (verified && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StepUpCubit, StepUpViewState>(
      builder: (BuildContext context, StepUpViewState state) {
        final bool verifying = state is StepUpVerifying;
        final String? error = switch (state) {
          StepUpInvalidPassword() => context.l10n.stepUpInvalidPassword,
          StepUpFault() => context.l10n.stepUpFailed,
          StepUpUnavailable() => context.l10n.stepUpUnavailable,
          _ => null,
        };
        return AlertDialog(
          title: Text(context.l10n.stepUpTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(context.l10n.stepUpDescription),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !verifying,
                decoration: InputDecoration(
                  labelText: context.l10n.masterPassword,
                ),
                onSubmitted: verifying ? null : (_) => _verify(),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: verifying ? null : () => Navigator.of(context).pop(),
              child: Text(context.l10n.close),
            ),
            FilledButton(
              onPressed: verifying ? null : _verify,
              child: verifying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.confirmMasterPassword),
            ),
          ],
        );
      },
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
