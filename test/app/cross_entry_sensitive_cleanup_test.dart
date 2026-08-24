import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:project_sw/app/app_dependencies.dart';
import 'package:project_sw/app/pages/generator_page.dart';
import 'package:project_sw/app/pages/settings_page.dart';
import 'package:project_sw/app/project_sw_app.dart';
import 'package:project_sw/core/config/app_config.dart';
import 'package:project_sw/core/data_hygiene/sensitive_clipboard.dart';
import 'package:project_sw/features/auth/domain/change_master_password.dart';
import 'package:project_sw/features/auth/domain/master_password_change_repository.dart';
import 'package:project_sw/features/auth/domain/session/session_activity_guard.dart';
import 'package:project_sw/features/auth/domain/session/session_controller.dart';
import 'package:project_sw/features/auth/domain/session/session_state.dart';
import 'package:project_sw/features/auth/presentation/auth_cubit.dart';
import 'package:project_sw/features/auth/presentation/master_password_change_cubit.dart';
import 'package:project_sw/features/generator/domain/password_generator.dart';

void main() {
  testWidgets(
    'lock clears generator, clipboard, and settings dialog secrets across routes',
    (WidgetTester tester) async {
      final GetIt locator = GetIt.asNewInstance();
      final _TestClipboard clipboard = _TestClipboard();
      registerAppDependencies(
        locator,
        config: const AppConfig(vaultExistsAtLaunch: true),
        clipboardPort: clipboard,
      );
      final SensitiveClipboardController clipboardController =
          locator<SensitiveClipboardController>();
      final SessionController sessionController = locator<SessionController>();
      final AuthCubit authCubit = locator<AuthCubit>();
      sessionController.unlock(AuthStrength.masterPassword);
      final MasterPasswordChangeCubit changeCubit = MasterPasswordChangeCubit(
        ChangeMasterPassword(_NoopPasswordChangeRepository()),
        sessionController,
      );
      addTearDown(() async => locator.reset());
      addTearDown(authCubit.close);
      addTearDown(changeCubit.close);

      await tester.pumpWidget(
        ProjectSwApp(
          sessionController: sessionController,
          authCubit: authCubit,
          sensitiveClipboardController: clipboardController,
          generatorPageBuilder: (BuildContext context) => GeneratorPage(
            generatePassword: GeneratePassword(
              SequenceRandomSource(List<int>.filled(20, 0)),
            ),
            randomSource: SequenceRandomSource(const <int>[0]),
            sensitiveClipboardController: clipboardController,
            sessionController: sessionController,
          ),
          settingsPageBuilder: (BuildContext context) => SettingsPage(
            sessionController: sessionController,
            masterPasswordChangeCubit: changeCubit,
          ),
        ),
      );

      await _openShellDestination(tester, 1);
      await _scrollTo(tester, find.text('Generate'));
      await tester.tap(find.text('Generate'));
      await tester.pump();

      const String generatedPassword = 'aaaaaaaaaaaaaaaaaaaa';
      expect(find.text(generatedPassword), findsOneWidget);
      await _scrollTo(tester, find.byTooltip('Copy generated password'));
      await tester.tap(find.byTooltip('Copy generated password'));
      await tester.pumpAndSettle();
      expect(clipboard.value, generatedPassword);
      expect(clipboardController.state.status, SensitiveClipboardStatus.active);

      sessionController.lock(LockReason.manualLock);
      await clipboard.clearStarted.future;
      await tester.pumpAndSettle();

      expect(find.byType(PasswordGeneratorPanel), findsOneWidget);
      expect(find.text(generatedPassword), findsNothing);
      expect(clipboard.value, isEmpty);
      expect(clipboardController.state.status, SensitiveClipboardStatus.idle);

      sessionController.unlock(AuthStrength.masterPassword);
      await tester.pumpAndSettle();
      expect(find.text(generatedPassword), findsNothing);

      await _openShellDestination(tester, 2);
      await _scrollTo(tester, find.text('Change master password'));
      await tester.tap(find.text('Change master password'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('current-master-password')),
        'current residual secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('new-master-password')),
        'new residual secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('confirm-new-master-password')),
        'new residual secret',
      );
      final TextEditingController currentPasswordController = tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('current-master-password')),
          )
          .controller!;
      final TextEditingController newPasswordController = tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('new-master-password')),
          )
          .controller!;
      final TextEditingController confirmationController = tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('confirm-new-master-password')),
          )
          .controller!;

      sessionController.lock(LockReason.manualLock);

      expect(currentPasswordController.text, isEmpty);
      expect(newPasswordController.text, isEmpty);
      expect(confirmationController.text, isEmpty);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('current-master-password')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('new-master-password')),
        findsNothing,
      );
      expect(find.text('Unlock your vault'), findsOneWidget);

      sessionController.unlock(AuthStrength.masterPassword);
      await tester.pumpAndSettle();
      await _openShellDestination(tester, 2);
      await _scrollTo(tester, find.text('Change master password'));
      await tester.tap(find.text('Change master password'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('current-master-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('new-master-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('confirm-new-master-password')),
            )
            .controller!
            .text,
        isEmpty,
      );

      sessionController.lock(LockReason.manualLock);
      await tester.pumpAndSettle();
    },
  );
}

Future<void> _openShellDestination(WidgetTester tester, int index) async {
  final String label = switch (index) {
    1 => 'Generator',
    2 => 'Settings',
    _ => 'Vault',
  };
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.drag(find.byType(ListView), const Offset(0, -500));
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
}

final class _TestClipboard implements ClipboardPort {
  String value = '';
  final Completer<void> clearStarted = Completer<void>();

  @override
  Future<void> writeText(String value) async => this.value = value;

  @override
  Future<String?> readText() async => value;

  @override
  Future<void> clearText() async {
    value = '';
    if (!clearStarted.isCompleted) clearStarted.complete();
  }
}

final class _NoopPasswordChangeRepository
    implements MasterPasswordChangeRepository {
  @override
  Future<void> changeMasterPassword({
    required String currentMasterPassword,
    required String newMasterPassword,
    required SessionActivityGuard activityGuard,
  }) async {}
}

final class SequenceRandomSource implements PasswordRandomSource {
  SequenceRandomSource(this._values);

  final List<int> _values;
  var _index = 0;

  @override
  int nextInt(int upperBound) {
    final int value = _values[_index % _values.length];
    _index++;
    return value % upperBound;
  }
}
