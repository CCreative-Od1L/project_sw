import 'package:flutter/widgets.dart';
import 'package:project_sw/l10n/generated/app_localizations.dart';

/// Convenient access to the generated application translations.
extension AppLocalizationContext on BuildContext {
  /// The active app localization; the root app always installs the delegate.
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

/// Resolves system locales to the supported language set with English fallback.
Locale resolveAppLocale(Locale? deviceLocale) =>
    deviceLocale?.languageCode == 'zh'
    ? const Locale('zh')
    : const Locale('en');
