import 'dart:async';

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
  });

  /// Global session source of truth used by the network flow.
  final SessionController sessionController;

  /// Network and protocol boundary, injectable for widget tests.
  final MigrationFlow flow;

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

final class _MigrationPageState extends State<MigrationPage> {
  _MigrationStage _stage = _MigrationStage.chooseRole;
  MigrationPairingPayload? _payload;
  var _operationId = 0;

  @override
  void dispose() {
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

  Future<void> _startSender() async {
    final int operationId = ++_operationId;
    try {
      final MigrationPairingPayload payload = await widget.flow.prepareSender();
      if (!mounted || operationId != _operationId) return;
      setState(() {
        _payload = payload;
        _stage = _MigrationStage.waitingForPeer;
      });
      await widget.flow.runSender();
      if (!mounted || operationId != _operationId) return;
      setState(() => _stage = _MigrationStage.complete);
    } catch (_) {
      if (!mounted || operationId != _operationId) return;
      _showFailure();
    }
  }

  Future<void> _startReceiver() async {
    final MigrationPairingPayload? payload = await Navigator.of(context).push(
      MaterialPageRoute<MigrationPairingPayload>(
        builder: (BuildContext context) => const MigrationScannerPage(),
      ),
    );
    if (!mounted || payload == null) return;
    final int operationId = ++_operationId;
    setState(() => _stage = _MigrationStage.connecting);
    try {
      await widget.flow.runReceiver(payload);
      if (!mounted || operationId != _operationId) return;
      setState(() => _stage = _MigrationStage.complete);
    } catch (_) {
      if (!mounted || operationId != _operationId) return;
      _showFailure();
    }
  }

  Future<void> _cancel() async {
    ++_operationId;
    await widget.flow.cancel();
    if (!mounted) return;
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
  const _RoleChooser({required this.onSend, required this.onReceive});

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
  const MigrationScannerPage({super.key});

  @override
  State<MigrationScannerPage> createState() => _MigrationScannerPageState();
}

final class _MigrationScannerPageState extends State<MigrationScannerPage> {
  final MobileScannerController _scanner = MobileScannerController();
  String? _error;
  var _hasResult = false;

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
                  MobileScanner(controller: _scanner, onDetect: _onDetect),
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
