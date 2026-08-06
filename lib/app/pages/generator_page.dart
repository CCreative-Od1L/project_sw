import 'package:flutter/material.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_feedback.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';

/// Password generator route, available regardless of vault lock state.
final class GeneratorPage extends StatelessWidget {
  /// Creates the generator route from injected domain and hygiene services.
  const GeneratorPage({
    super.key,
    this.generatePassword,
    this.randomSource,
    this.sensitiveClipboardController,
    this.sessionController,
  });

  /// Generator use case.
  final GeneratePassword? generatePassword;

  /// Unbiased random source used by [generatePassword].
  final PasswordRandomSource? randomSource;

  /// Shared sensitive clipboard service.
  final SensitiveClipboardController? sensitiveClipboardController;

  /// Optional session cleaner for generated plaintext.
  final SessionController? sessionController;

  @override
  Widget build(BuildContext context) {
    final GeneratePassword? generator = generatePassword;
    final PasswordRandomSource? random = randomSource;
    final SensitiveClipboardController? clipboard =
        sensitiveClipboardController;
    if (generator == null || random == null || clipboard == null) {
      return SessionPageScaffold(
        title: context.l10n.generator,
        child: Center(child: Text(context.l10n.generatorComingSoon)),
      );
    }
    return SessionPageScaffold(
      title: context.l10n.generator,
      child: PasswordGeneratorPanel(
        generatePassword: generator,
        randomSource: random,
        sensitiveClipboardController: clipboard,
        sessionController: sessionController,
      ),
    );
  }
}

/// Reusable generator controls used by the standalone route and entry form.
final class PasswordGeneratorPanel extends StatefulWidget {
  /// Creates a generator panel with an optional entry insertion callback.
  const PasswordGeneratorPanel({
    super.key,
    required this.generatePassword,
    required this.randomSource,
    required this.sensitiveClipboardController,
    this.sessionController,
    this.onGenerated,
  });

  /// Generator use case.
  final GeneratePassword generatePassword;

  /// Random source retained for explicit dependency visibility in the panel.
  final PasswordRandomSource randomSource;

  /// Shared sensitive clipboard service.
  final SensitiveClipboardController sensitiveClipboardController;

  /// Session source used to clear generated output before a lock transition.
  final SessionController? sessionController;

  /// Called after the user explicitly chooses to insert the result.
  final ValueChanged<String>? onGenerated;

  @override
  State<PasswordGeneratorPanel> createState() => _PasswordGeneratorPanelState();
}

final class _PasswordGeneratorPanelState extends State<PasswordGeneratorPanel>
    implements SessionSecretCleaner {
  GenerationProfile _profile = const GenerationProfile();
  String? _generatedPassword;
  PasswordEntropy? _entropy;
  var _error = false;

  @override
  void initState() {
    super.initState();
    widget.sessionController?.registerSecretCleaner(this);
  }

  @override
  void dispose() {
    widget.sessionController?.unregisterSecretCleaner(this);
    _generatedPassword = null;
    _entropy = null;
    super.dispose();
  }

  @override
  void clearUnlockedSession() {
    if (!mounted) {
      _generatedPassword = null;
      _entropy = null;
      _error = false;
      return;
    }
    setState(() {
      _generatedPassword = null;
      _entropy = null;
      _error = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool pronounceable = _profile.mode == GenerationMode.pronounceable;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        Text(
          context.l10n.generationMode,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<GenerationMode>(
          segments: <ButtonSegment<GenerationMode>>[
            ButtonSegment<GenerationMode>(
              value: GenerationMode.random,
              icon: const Icon(Icons.shuffle),
              label: Text(context.l10n.randomMode),
            ),
            ButtonSegment<GenerationMode>(
              value: GenerationMode.pronounceable,
              icon: const Icon(Icons.record_voice_over_outlined),
              label: Text(context.l10n.pronounceableMode),
            ),
          ],
          selected: <GenerationMode>{_profile.mode},
          onSelectionChanged: (Set<GenerationMode> selected) {
            setState(() {
              _profile = _profile.copyWith(mode: selected.first);
              _error = false;
            });
          },
        ),
        const SizedBox(height: 20),
        Text(context.l10n.generatorLength(_profile.length)),
        Slider(
          min: GenerationProfile.minLength.toDouble(),
          max: GenerationProfile.maxLength.toDouble(),
          divisions: GenerationProfile.maxLength - GenerationProfile.minLength,
          value: _profile.length.toDouble(),
          label: _profile.length.toString(),
          onChanged: (double value) => setState(
            () => _profile = _profile.copyWith(length: value.round()),
          ),
        ),
        if (pronounceable)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.l10n.pronounceableHint),
            ),
          )
        else ...<Widget>[
          Text(
            context.l10n.characterSets,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          _toggle(
            context.l10n.lowercase,
            _profile.lowercase,
            (bool value) =>
                setState(() => _profile = _profile.copyWith(lowercase: value)),
          ),
          _toggle(
            context.l10n.uppercase,
            _profile.uppercase,
            (bool value) =>
                setState(() => _profile = _profile.copyWith(uppercase: value)),
          ),
          _toggle(
            context.l10n.digits,
            _profile.digits,
            (bool value) =>
                setState(() => _profile = _profile.copyWith(digits: value)),
          ),
          _toggle(
            context.l10n.symbols,
            _profile.symbols,
            (bool value) =>
                setState(() => _profile = _profile.copyWith(symbols: value)),
          ),
          _toggle(
            context.l10n.excludeAmbiguous,
            _profile.excludeAmbiguous,
            (bool value) => setState(
              () => _profile = _profile.copyWith(excludeAmbiguous: value),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.autorenew),
          label: Text(context.l10n.generate),
        ),
        if (_error) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            context.l10n.generationFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_generatedPassword != null && _entropy != null) ...<Widget>[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(
                    _generatedPassword!,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.theoreticalEntropy(
                      _entropy!.bits.toStringAsFixed(1),
                    ),
                  ),
                  Text(_strengthLabel(context, _entropy!.strength)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      SensitiveCopyButton(
                        value: _generatedPassword!,
                        controller: widget.sensitiveClipboardController,
                        tooltip: context.l10n.copyGeneratedPassword,
                      ),
                      if (widget.onGenerated != null)
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              widget.onGenerated!(_generatedPassword!),
                          icon: const Icon(Icons.input),
                          label: Text(context.l10n.useInEntry),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );

  void _generate() {
    try {
      final String password = widget.generatePassword(_profile);
      final PasswordEntropy entropy = widget.generatePassword.estimateEntropy(
        _profile,
      );
      setState(() {
        _generatedPassword = password;
        _entropy = entropy;
        _error = false;
      });
    } on Object {
      setState(() {
        _generatedPassword = null;
        _entropy = null;
        _error = true;
      });
    }
  }

  String _strengthLabel(BuildContext context, PasswordStrength strength) =>
      switch (strength) {
        PasswordStrength.weak => context.l10n.strengthWeak,
        PasswordStrength.medium => context.l10n.strengthMedium,
        PasswordStrength.strong => context.l10n.strengthStrong,
        PasswordStrength.veryStrong => context.l10n.strengthVeryStrong,
      };
}
