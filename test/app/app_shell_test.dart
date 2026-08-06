import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_sw/app/app_theme.dart';
import 'package:project_sw/app/localization.dart';
import 'package:project_sw/app/pages/app_shell.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

void main() {
  test(
    'system locale resolution supports Chinese and falls back to English',
    () {
      expect(resolveAppLocale(const Locale('zh', 'CN')), const Locale('zh'));
      expect(resolveAppLocale(const Locale('fr')), const Locale('en'));
      expect(resolveAppLocale(null), const Locale('en'));
    },
  );

  test('Material theme exposes matching light and dark design tokens', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
    expect(AppTheme.light.useMaterial3, isTrue);
    expect(AppTheme.dark.useMaterial3, isTrue);
  });

  testWidgets('bottom navigation labels follow the active locale', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppShell(currentLocation: '/generator', child: SizedBox.shrink()),
      ),
    );

    expect(find.text('密码库'), findsOneWidget);
    expect(find.text('密码生成器'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
