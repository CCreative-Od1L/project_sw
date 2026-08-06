import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/session_page_scaffold.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_feedback.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard_scope.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_events.dart';
import 'package:project_sw/features/auth/domain/session/session_secret_cleaner.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/vault/domain/vault_entry.dart';
import 'package:project_sw/features/vault/presentation/vault_entries_cubit.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';
import 'package:project_sw/app/pages/generator_page.dart';

/// Unlocked home route with the EntrySummary list and add-entry form.
final class HomePage extends StatelessWidget {
  /// Creates the home route for [sessionController].
  const HomePage({
    super.key,
    required this.sessionController,
    this.vaultEntriesCubit,
    this.generatePassword,
    this.passwordRandomSource,
  });

  /// The session source of truth that owns locking.
  final SessionController sessionController;

  /// The optional list workflow, omitted by route-skeleton tests only.
  final VaultEntriesCubit? vaultEntriesCubit;

  /// Optional generator dependencies supplied by the composition root.
  final GeneratePassword? generatePassword;

  /// Optional unbiased random source for the entry-form generator sheet.
  final PasswordRandomSource? passwordRandomSource;

  @override
  Widget build(BuildContext context) {
    final VaultEntriesCubit? cubit = vaultEntriesCubit;
    if (cubit == null) {
      return _HomeContent(
        sessionController: sessionController,
        generatePassword: generatePassword,
        passwordRandomSource: passwordRandomSource,
      );
    }
    return BlocProvider<VaultEntriesCubit>.value(
      value: cubit,
      child: _HomeContent(
        sessionController: sessionController,
        vaultEntriesCubit: cubit,
        generatePassword: generatePassword,
        passwordRandomSource: passwordRandomSource,
      ),
    );
  }
}

final class _HomeContent extends StatefulWidget {
  const _HomeContent({
    required this.sessionController,
    this.vaultEntriesCubit,
    this.generatePassword,
    this.passwordRandomSource,
  });

  final SessionController sessionController;
  final VaultEntriesCubit? vaultEntriesCubit;
  final GeneratePassword? generatePassword;
  final PasswordRandomSource? passwordRandomSource;

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

final class _HomeContentState extends State<_HomeContent>
    implements SessionSecretCleaner {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  var _favorite = false;

  @override
  void initState() {
    super.initState();
    widget.sessionController.registerSecretCleaner(this);
  }

  @override
  void dispose() {
    widget.sessionController.unregisterSecretCleaner(this);
    _clearForm();
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void clearUnlockedSession() {
    _clearForm();
    _favorite = false;
  }

  @override
  Widget build(BuildContext context) {
    final VaultEntriesCubit? cubit = widget.vaultEntriesCubit;
    return SessionPageScaffold(
      title: context.l10n.vault,
      child: ListView(
        children: <Widget>[
          Text(
            context.l10n.vaultUnlocked,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          if (cubit == null)
            Text(context.l10n.noEntries)
          else
            _EntriesPanel(
              onAdded: _clearForm,
              sessionController: widget.sessionController,
            ),
          if (cubit != null) ...<Widget>[
            const Divider(),
            Text(
              context.l10n.addEntry,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: context.l10n.name),
              textInputAction: TextInputAction.next,
              onChanged: (_) => widget.sessionController.handle(
                SessionEvent.userInteractionObserved,
              ),
            ),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(labelText: context.l10n.url),
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => widget.sessionController.handle(
                SessionEvent.userInteractionObserved,
              ),
            ),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(labelText: context.l10n.username),
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => widget.sessionController.handle(
                SessionEvent.userInteractionObserved,
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: context.l10n.password,
                    ),
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => widget.sessionController.handle(
                      SessionEvent.userInteractionObserved,
                    ),
                  ),
                ),
                if (widget.generatePassword != null &&
                    widget.passwordRandomSource != null)
                  IconButton(
                    tooltip: context.l10n.generator,
                    icon: const Icon(Icons.password_outlined),
                    onPressed: _openGenerator,
                  ),
              ],
            ),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(labelText: context.l10n.notes),
              minLines: 1,
              maxLines: 2,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => widget.sessionController.handle(
                SessionEvent.userInteractionObserved,
              ),
            ),
            Row(
              children: <Widget>[
                Checkbox(
                  value: _favorite,
                  onChanged: (bool? value) {
                    setState(() => _favorite = value ?? false);
                  },
                ),
                Text(context.l10n.favorite),
                const Spacer(),
                BlocBuilder<VaultEntriesCubit, VaultEntriesViewState>(
                  builder: (BuildContext context, VaultEntriesViewState state) {
                    return FilledButton(
                      onPressed: state is VaultEntriesSaving ? null : _submit,
                      child: state is VaultEntriesSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.l10n.saveEntry),
                    );
                  },
                ),
              ],
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: context.l10n.lockVault,
              onPressed: () =>
                  widget.sessionController.lock(LockReason.manualLock),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    widget.sessionController.handle(SessionEvent.userInteractionObserved);
    final VaultEntriesCubit cubit = context.read<VaultEntriesCubit>();
    await cubit.add(
      NewVaultEntry(
        name: _nameController.text,
        url: _urlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        notes: _notesController.text,
        favorite: _favorite,
      ),
    );
    final VaultEntriesViewState state = cubit.state;
    if (state is VaultEntriesReady && state.errorMessage == null) {
      _clearForm();
    }
  }

  Future<void> _openGenerator() async {
    final GeneratePassword? generator = widget.generatePassword;
    final PasswordRandomSource? random = widget.passwordRandomSource;
    final SensitiveClipboardController? clipboard =
        SensitiveClipboardScope.maybeOf(context);
    if (generator == null || random == null || clipboard == null) return;
    final String? generated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: PasswordGeneratorPanel(
            generatePassword: generator,
            randomSource: random,
            sensitiveClipboardController: clipboard,
            sessionController: widget.sessionController,
            onGenerated: (String value) => Navigator.pop(sheetContext, value),
          ),
        ),
      ),
    );
    if (!mounted || generated == null) return;
    _passwordController
      ..text = generated
      ..selection = TextSelection.collapsed(offset: generated.length);
    widget.sessionController.handle(SessionEvent.userInteractionObserved);
  }

  void _clearForm() {
    _nameController.clear();
    _urlController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _notesController.clear();
  }
}

final class _EntriesPanel extends StatelessWidget {
  const _EntriesPanel({required this.onAdded, required this.sessionController});

  final VoidCallback onAdded;
  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    return BlocListener<VaultEntriesCubit, VaultEntriesViewState>(
      listenWhen:
          (VaultEntriesViewState previous, VaultEntriesViewState current) =>
              previous is VaultEntriesSaving && current is VaultEntriesReady,
      listener: (BuildContext context, VaultEntriesViewState state) {
        final VaultEntriesReady ready = state as VaultEntriesReady;
        if (ready.errorMessage == null) {
          onAdded();
        }
      },
      child: BlocBuilder<VaultEntriesCubit, VaultEntriesViewState>(
        builder: (BuildContext context, VaultEntriesViewState state) {
          if (state.summaries.isEmpty) {
            return Text(context.l10n.noEntries);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (state is VaultEntriesReady && state.errorMessage != null)
                Text(
                  context.l10n.entrySaveFailed,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (state.summaries.isEmpty)
                Text(context.l10n.noEntries)
              else
                for (final EntrySummary summary in state.summaries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(summary.name),
                    subtitle: Text(
                      <String>[
                        summary.url,
                        summary.username,
                      ].where((String value) => value.isNotEmpty).join(' · '),
                    ),
                    trailing: summary.favorite
                        ? Icon(Icons.star, semanticLabel: context.l10n.favorite)
                        : null,
                    onTap: () => _showDetail(context, summary),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, EntrySummary summary) async {
    final VaultEntriesCubit cubit = context.read<VaultEntriesCubit>();
    final EntryDetail detail = await cubit.detail(summary.entryId);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _EntryDetailDialog(
        cubit: cubit,
        detail: detail,
        sessionController: sessionController,
        sensitiveClipboardController: SensitiveClipboardScope.maybeOf(context),
      ),
    );
  }
}

/// Owns detail plaintext and field controllers for exactly one modal route.
final class _EntryDetailDialog extends StatefulWidget {
  const _EntryDetailDialog({
    required this.cubit,
    required this.detail,
    required this.sessionController,
    this.sensitiveClipboardController,
  });

  final VaultEntriesCubit cubit;
  final EntryDetail detail;
  final SessionController sessionController;
  final SensitiveClipboardController? sensitiveClipboardController;

  @override
  State<_EntryDetailDialog> createState() => _EntryDetailDialogState();
}

final class _EntryDetailDialogState extends State<_EntryDetailDialog>
    implements SessionSecretCleaner {
  late final TextEditingController _name = TextEditingController(
    text: widget.detail.entry.name,
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.detail.entry.url,
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.detail.entry.username,
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.detail.entry.password,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.detail.entry.notes,
  );
  late var _favorite = widget.detail.entry.favorite;

  @override
  void initState() {
    super.initState();
    widget.sessionController.registerSecretCleaner(this);
  }

  @override
  void dispose() {
    widget.sessionController.unregisterSecretCleaner(this);
    _name.clear();
    _url.clear();
    _username.clear();
    _password.clear();
    _notes.clear();
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  void clearUnlockedSession() {
    _name.clear();
    _url.clear();
    _username.clear();
    _password.clear();
    _notes.clear();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.entryDetail),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.name),
          ),
          TextField(
            controller: _url,
            decoration: InputDecoration(labelText: context.l10n.url),
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
          ),
          TextField(
            controller: _username,
            decoration: InputDecoration(labelText: context.l10n.username),
            autocorrect: false,
            enableSuggestions: false,
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _password,
                  decoration: InputDecoration(labelText: context.l10n.password),
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              if (widget.sensitiveClipboardController != null)
                SensitiveCopyButton(
                  value: widget.detail.entry.password,
                  controller: widget.sensitiveClipboardController!,
                  tooltip: context.l10n.copyPassword,
                ),
            ],
          ),
          for (final CustomField field in widget.detail.entry.customFields)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(field.label),
              subtitle: Text(field.secret ? '••••••••' : field.value),
              trailing:
                  field.secret && widget.sensitiveClipboardController != null
                  ? SensitiveCopyButton(
                      value: field.value,
                      controller: widget.sensitiveClipboardController!,
                      tooltip: context.l10n.copySecretField,
                    )
                  : null,
            ),
          TextField(
            controller: _notes,
            decoration: InputDecoration(labelText: context.l10n.notes),
            minLines: 1,
            maxLines: 3,
            autocorrect: false,
            enableSuggestions: false,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _favorite,
            onChanged: (bool? value) {
              setState(() => _favorite = value ?? false);
            },
            title: Text(context.l10n.favorite),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(onPressed: _delete, child: Text(context.l10n.delete)),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.close),
      ),
      FilledButton(onPressed: _save, child: Text(context.l10n.save)),
    ],
  );

  Future<void> _delete() async {
    await widget.cubit.delete(widget.detail.entry.entryId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    await widget.cubit.update(
      widget.detail.entry.copyWith(
        name: _name.text,
        url: _url.text,
        username: _username.text,
        password: _password.text,
        notes: _notes.text,
        favorite: _favorite,
      ),
    );
    if (mounted) Navigator.pop(context);
  }
}
