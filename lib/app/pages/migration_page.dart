import 'master_password_step_up_dialog.dart';
import 'session_secret_dialog.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/presentation/step_up_cubit.dart';
import 'package:project_sw/features/migration/domain/migration_transfer.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/migration/data/migration_flow.dart';
import 'package:project_sw/features/migration/domain/migration_models.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Material entry point for the two-device vault migration flow.
final class MigrationPage extends StatefulWidget {
  /// Creates a migration page for an unlocked session.
  const MigrationPage({
    super.key,
    required this.sessionController,
    required this.flow,
    this.stepUpCubit,
    this.entries,
    this.scan,
    this.onImported,
  });

  /// Global session source of truth used by the network flow.
  final SessionController sessionController;

  /// Network and protocol boundary, injectable for widget tests.
  final MigrationFlow flow;

  /// Step-up verifier for biometric sessions; absent verifiers fail closed.
  final StepUpCubit? stepUpCubit;

  /// Reads fresh list-safe entry projections for single-entry selection.
  final List<EntrySummary> Function()? entries;

  /// Optional scanner boundary for platforms and widget tests.
  final Future<MigrationPairingPayload?> Function(BuildContext)? scan;

  /// Refreshes the receiving vault list after the import.
  final VoidCallback? onImported;

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

/// Fallback route used by route-focused tests without production dependencies.
final class MigrationUnavailablePage extends StatelessWidget {
  /// Creates the dependency-free migration route placeholder.
  const MigrationUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SessionPageScaffold(
      title: context.l10n.migration,
      child: Text(context.l10n.migrationFailed),
    );
  }
}

enum _MigrationStage {
  chooseRole,
  waitingForPeer,
  connecting,
  transferring,
  complete,
}

final class _MigrationPageState extends State<MigrationPage>
    implements SessionSecretCleaner {
  _MigrationStage _stage = _MigrationStage.chooseRole;
  MigrationPairingPayload? _payload;
  var _operationId = 0;
  String _selection = 'all';

  @override
  void initState() {
    super.initState();
    widget.sessionController.registerSecretCleaner(this);
  }

  @override
  void clearUnlockedSession() {
    ++_operationId;
    _payload = null;
    _selection = 'all';
    _stage = _MigrationStage.chooseRole;
    unawaited(widget.flow.cancel());
  }

  @override
  void dispose() {
    widget.sessionController.unregisterSecretCleaner(this);
    ++_operationId;
    _payload = null;
    unawaited(widget.flow.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionPageScaffold(
      title: context.l10n.migration,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: switch (_stage) {
          _MigrationStage.chooseRole => _RoleChooser(
            onSend: _startSender,
            onReceive: _startReceiver,
            entries: widget.entries?.call() ?? const <EntrySummary>[],
            selection: _selection,
            onSelectionChanged: (value) => setState(() => _selection = value),
          ),
          _MigrationStage.waitingForPeer => _SenderQrCard(
            payload: _payload!,
            onCancel: _cancel,
          ),
          _MigrationStage.connecting => _ProgressCard(
            label: context.l10n.migrationConnecting,
            onCancel: _cancel,
          ),
          _MigrationStage.transferring => _ProgressCard(
            label: context.l10n.migrationTransferring,
            onCancel: _cancel,
          ),
          _MigrationStage.complete => _CompleteCard(onDone: _reset),
        },
      ),
    );
  }

  Future<bool> _authorize() async {
    final SessionState state = widget.sessionController.state;
    if (state is! UnlockedSession) return false;
    if (state.authStrength == AuthStrength.masterPassword) return true;
    final StepUpCubit? cubit = widget.stepUpCubit;
    if (cubit == null) return false;
    return showMasterPasswordStepUp(context, cubit, widget.sessionController);
  }

  bool _current(int id) =>
      mounted &&
      id == _operationId &&
      widget.sessionController.state is UnlockedSession;

  Future<void> _startSender() async {
    if (_stage != _MigrationStage.chooseRole) return;
    final int operationId = ++_operationId;
    setState(() => _stage = _MigrationStage.connecting);
    try {
      if (!await _authorize()) {
        if (_current(operationId)) _reset();
        return;
      }
      if (!_current(operationId)) return;
      final MigrationSelection selection;
      if (_selection == 'all') {
        selection = const MigrationSelection.all();
      } else {
        final List<EntrySummary> entries =
            widget.entries?.call() ?? <EntrySummary>[];
        final EntrySummary entry = entries.firstWhere(
          (entry) => base64Url.encode(entry.entryId) == _selection,
        );
        selection = MigrationSelection.single(entry.entryId);
      }
      final MigrationPairingPayload payload = await widget.flow.prepareSender(
        selection: selection,
      );
      if (!_current(operationId)) return;
      setState(() {
        _payload = payload;
        _stage = _MigrationStage.waitingForPeer;
      });
      await widget.flow.runSender();
      if (!_current(operationId)) return;
      setState(() {
        _payload = null;
        _stage = _MigrationStage.complete;
      });
    } on Object {
      if (!_current(operationId)) return;
      await widget.flow.cancel();
      if (_current(operationId)) _showFailure();
    }
  }

  Future<void> _startReceiver() async {
    if (_stage != _MigrationStage.chooseRole) return;
    final int operationId = ++_operationId;
    setState(() => _stage = _MigrationStage.connecting);
    try {
      if (!await _authorize()) {
        if (_current(operationId)) _reset();
        return;
      }
      if (!_current(operationId)) return;
      await widget.flow.prepareReceiver();
      if (!mounted || !_current(operationId)) return;
      final MigrationPairingPayload? payload =
          await (widget.scan?.call(context) ??
              Navigator.of(context).push<MigrationPairingPayload>(
                MaterialPageRoute<MigrationPairingPayload>(
                  builder: (_) => MigrationScannerPage(
                    sessionController: widget.sessionController,
                  ),
                ),
              ));
      if (!_current(operationId)) return;
      if (payload == null) {
        await _cancel();
        return;
      }
      setState(() => _stage = _MigrationStage.transferring);
      await widget.flow.runReceiver(payload);
      if (!_current(operationId)) return;
      widget.onImported?.call();
      setState(() => _stage = _MigrationStage.complete);
    } on Object {
      if (!_current(operationId)) return;
      await widget.flow.cancel();
      if (_current(operationId)) _showFailure();
    }
  }

  Future<void> _cancel() async {
    final int operationId = ++_operationId;
    await widget.flow.cancel();
    if (!mounted || operationId != _operationId) return;
    setState(() {
      _payload = null;
      _stage = _MigrationStage.chooseRole;
    });
  }

  void _reset() {
    ++_operationId;
    setState(() {
      _payload = null;
      _stage = _MigrationStage.chooseRole;
    });
  }

  void _showFailure() {
    setState(() {
      _payload = null;
      _stage = _MigrationStage.chooseRole;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.migrationFailed)));
  }
}

final class _RoleChooser extends StatelessWidget {
  const _RoleChooser({
    required this.onSend,
    required this.onReceive,
    required this.entries,
    required this.selection,
    required this.onSelectionChanged,
  });

  final List<EntrySummary> entries;
  final String selection;
  final ValueChanged<String> onSelectionChanged;

  final VoidCallback onSend;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('migration-role-chooser'),
      children: <Widget>[
        Text(
          context.l10n.migrationChooseRole,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: const ValueKey<String>('migration-selection'),
          initialValue: selection,
          decoration: InputDecoration(labelText: context.l10n.migrationScope),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem(
              value: 'all',
              child: Text(context.l10n.migrationAllEntries),
            ),
            if (selection != 'all' &&
                !entries.any(
                  (entry) => base64Url.encode(entry.entryId) == selection,
                ))
              DropdownMenuItem(
                value: selection,
                child: Text(context.l10n.migrationFailed),
              ),
            for (final EntrySummary entry in entries)
              DropdownMenuItem(
                value: base64Url.encode(entry.entryId),
                child: Text(entry.name),
              ),
          ],
          onChanged: (value) {
            if (value != null) onSelectionChanged(value);
          },
        ),
        const SizedBox(height: 16),
        _RoleCard(
          icon: Icons.qr_code_2,
          title: context.l10n.migrationSendTitle,
          description: context.l10n.migrationSendDescription,
          actionLabel: context.l10n.migrationShowQr,
          onPressed: onSend,
        ),
        _RoleCard(
          icon: Icons.qr_code_scanner,
          title: context.l10n.migrationReceiveTitle,
          description: context.l10n.migrationReceiveDescription,
          actionLabel: context.l10n.migrationScanQr,
          onPressed: onReceive,
        ),
      ],
    );
  }
}

final class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 32),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(description),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SenderQrCard extends StatelessWidget {
  const _SenderQrCard({required this.payload, required this.onCancel});

  final MigrationPairingPayload payload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('migration-sender-qr'),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                QrImageView(
                  key: const ValueKey<String>('migration-qr-code'),
                  data: payload.encode(),
                  version: QrVersions.auto,
                  size: 260,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.migrationWaitingForPeer,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.migrationPairingAddress(
                    payload.host,
                    payload.port,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        Text(context.l10n.migrationQrExpires),
        const SizedBox(height: 6),
        Text(context.l10n.migrationKeepForeground),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          label: Text(context.l10n.migrationCancel),
        ),
      ],
    );
  }
}

final class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.label, required this.onCancel});

  final String label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('migration-progress'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(context.l10n.migrationKeepForeground, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextButton(
          onPressed: onCancel,
          child: Text(context.l10n.migrationCancel),
        ),
      ],
    );
  }
}

final class _CompleteCard extends StatelessWidget {
  const _CompleteCard({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('migration-complete'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.migrationComplete,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.migrationCompleteDescription,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onDone,
          child: Text(context.l10n.migrationBack),
        ),
      ],
    );
  }
}

/// Camera route that returns the first valid, unexpired migration payload.
final class MigrationScannerPage extends StatefulWidget {
  /// Creates the QR scanner route.
  const MigrationScannerPage({super.key, required this.sessionController});

  /// Session that revokes camera access on lock.
  final SessionController sessionController;

  @override
  State<MigrationScannerPage> createState() => _MigrationScannerPageState();
}

final class _MigrationScannerPageState extends State<MigrationScannerPage>
    with SessionSecretDialogState<MigrationScannerPage> {
  final MobileScannerController _scanner = MobileScannerController();
  String? _error;
  var _hasResult = false;

  @override
  SessionController get sessionController => widget.sessionController;

  @override
  void clearDialogSecrets() {
    _hasResult = true;
    unawaited(_scanner.stop());
    _error = null;
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.migrationScanQr)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => Center(
                      child: Text(context.l10n.migrationCameraUnavailable),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error ?? context.l10n.migrationScanHint,
                textAlign: TextAlign.center,
                style: _error == null
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasResult) return;
    for (final Barcode barcode in capture.barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.isEmpty) continue;
      try {
        final MigrationPairingPayload payload = MigrationPairingPayload.decode(
          rawValue,
        );
        _hasResult = true;
        unawaited(_scanner.stop());
        if (mounted) Navigator.of(context).pop(payload);
        return;
      } on Object {
        if (mounted) setState(() => _error = context.l10n.migrationInvalidQr);
      }
    }
  }
}
