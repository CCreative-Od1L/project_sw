import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Project SW'**
  String get appTitle;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Project SW'**
  String get setupTitle;

  /// No description provided for @createYourVault.
  ///
  /// In en, this message translates to:
  /// **'Create your vault'**
  String get createYourVault;

  /// No description provided for @vaultDescription.
  ///
  /// In en, this message translates to:
  /// **'Your encrypted vault will be created on this device.'**
  String get vaultDescription;

  /// No description provided for @masterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get masterPassword;

  /// No description provided for @optimizingSecurityParameters.
  ///
  /// In en, this message translates to:
  /// **'Optimizing security parameters…'**
  String get optimizingSecurityParameters;

  /// No description provided for @optimizingSecurityParametersProgress.
  ///
  /// In en, this message translates to:
  /// **'Optimizing security parameters… {completed}/{total}'**
  String optimizingSecurityParametersProgress(int completed, int total);

  /// No description provided for @createVault.
  ///
  /// In en, this message translates to:
  /// **'Create vault'**
  String get createVault;

  /// No description provided for @vaultCreated.
  ///
  /// In en, this message translates to:
  /// **'Vault created'**
  String get vaultCreated;

  /// No description provided for @securityParametersOptimized.
  ///
  /// In en, this message translates to:
  /// **'Security parameters optimized for this device:'**
  String get securityParametersOptimized;

  /// No description provided for @argon2idParameters.
  ///
  /// In en, this message translates to:
  /// **'Argon2id: m={memoryMiB} MiB, t={iterations}, p={parallelism}'**
  String argon2idParameters(int memoryMiB, int iterations, int parallelism);

  /// No description provided for @continueToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Continue to unlock'**
  String get continueToUnlock;

  /// No description provided for @vaultCreationFailed.
  ///
  /// In en, this message translates to:
  /// **'Vault creation could not be completed.'**
  String get vaultCreationFailed;

  /// No description provided for @unlockVault.
  ///
  /// In en, this message translates to:
  /// **'Unlock vault'**
  String get unlockVault;

  /// No description provided for @unlockYourVault.
  ///
  /// In en, this message translates to:
  /// **'Unlock your vault'**
  String get unlockYourVault;

  /// No description provided for @incorrectMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password is incorrect.'**
  String get incorrectMasterPassword;

  /// No description provided for @vaultUnlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Vault unlock could not be completed.'**
  String get vaultUnlockFailed;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @useBiometric.
  ///
  /// In en, this message translates to:
  /// **'Unlock with biometrics'**
  String get useBiometric;

  /// No description provided for @biometricCancelled.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock was cancelled.'**
  String get biometricCancelled;

  /// No description provided for @biometricInvalidated.
  ///
  /// In en, this message translates to:
  /// **'Biometric settings changed. Unlock with your master password to set it up again.'**
  String get biometricInvalidated;

  /// No description provided for @biometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is unavailable. Use your master password.'**
  String get biometricUnavailable;

  /// No description provided for @biometricUnlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock could not be completed.'**
  String get biometricUnlockFailed;

  /// No description provided for @vault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get vault;

  /// No description provided for @generator.
  ///
  /// In en, this message translates to:
  /// **'Generator'**
  String get generator;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @vaultUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Vault unlocked'**
  String get vaultUnlocked;

  /// No description provided for @noEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries have been added yet.'**
  String get noEntries;

  /// No description provided for @addEntry.
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get addEntry;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @url.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get url;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @saveEntry.
  ///
  /// In en, this message translates to:
  /// **'Save entry'**
  String get saveEntry;

  /// No description provided for @lockVault.
  ///
  /// In en, this message translates to:
  /// **'Lock vault'**
  String get lockVault;

  /// No description provided for @entryDetail.
  ///
  /// In en, this message translates to:
  /// **'Entry detail'**
  String get entryDetail;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @entrySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The entry could not be saved.'**
  String get entrySaveFailed;

  /// No description provided for @copySensitiveValue.
  ///
  /// In en, this message translates to:
  /// **'Copy sensitive value'**
  String get copySensitiveValue;

  /// No description provided for @copyPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy password'**
  String get copyPassword;

  /// No description provided for @copySecretField.
  ///
  /// In en, this message translates to:
  /// **'Copy secret field'**
  String get copySecretField;

  /// No description provided for @sensitiveCopied.
  ///
  /// In en, this message translates to:
  /// **'Password copied to clipboard'**
  String get sensitiveCopied;

  /// No description provided for @generationMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get generationMode;

  /// No description provided for @randomMode.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get randomMode;

  /// No description provided for @pronounceableMode.
  ///
  /// In en, this message translates to:
  /// **'Pronounceable'**
  String get pronounceableMode;

  /// No description provided for @generatorLength.
  ///
  /// In en, this message translates to:
  /// **'Length: {length}'**
  String generatorLength(int length);

  /// No description provided for @characterSets.
  ///
  /// In en, this message translates to:
  /// **'Character sets'**
  String get characterSets;

  /// No description provided for @lowercase.
  ///
  /// In en, this message translates to:
  /// **'Lowercase'**
  String get lowercase;

  /// No description provided for @uppercase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase'**
  String get uppercase;

  /// No description provided for @digits.
  ///
  /// In en, this message translates to:
  /// **'Digits'**
  String get digits;

  /// No description provided for @symbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get symbols;

  /// No description provided for @excludeAmbiguous.
  ///
  /// In en, this message translates to:
  /// **'Exclude ambiguous characters'**
  String get excludeAmbiguous;

  /// No description provided for @pronounceableHint.
  ///
  /// In en, this message translates to:
  /// **'Pronounceable mode uses alternating consonants and vowels.'**
  String get pronounceableHint;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @copyGeneratedPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy generated password'**
  String get copyGeneratedPassword;

  /// No description provided for @useInEntry.
  ///
  /// In en, this message translates to:
  /// **'Use in entry'**
  String get useInEntry;

  /// No description provided for @theoreticalEntropy.
  ///
  /// In en, this message translates to:
  /// **'Theoretical entropy: {bits} bits'**
  String theoreticalEntropy(String bits);

  /// No description provided for @strengthWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get strengthWeak;

  /// No description provided for @strengthMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get strengthMedium;

  /// No description provided for @strengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strengthStrong;

  /// No description provided for @strengthVeryStrong.
  ///
  /// In en, this message translates to:
  /// **'Very strong'**
  String get strengthVeryStrong;

  /// No description provided for @generationFailed.
  ///
  /// In en, this message translates to:
  /// **'Password could not be generated.'**
  String get generationFailed;

  /// No description provided for @searchEntries.
  ///
  /// In en, this message translates to:
  /// **'Search entries'**
  String get searchEntries;

  /// No description provided for @favoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'Favorites only'**
  String get favoritesOnly;

  /// No description provided for @noMatchingEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries match your search.'**
  String get noMatchingEntries;

  /// No description provided for @securitySettingsReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Security settings'**
  String get securitySettingsReadOnly;

  /// No description provided for @idleLockPolicy.
  ///
  /// In en, this message translates to:
  /// **'Idle lock'**
  String get idleLockPolicy;

  /// No description provided for @idleLockPolicyValue.
  ///
  /// In en, this message translates to:
  /// **'Locks after {minutes} minutes without interaction.'**
  String idleLockPolicyValue(int minutes);

  /// No description provided for @backgroundLockPolicy.
  ///
  /// In en, this message translates to:
  /// **'Background lock'**
  String get backgroundLockPolicy;

  /// No description provided for @backgroundLockPolicyValue.
  ///
  /// In en, this message translates to:
  /// **'Locks immediately when the app enters the background.'**
  String get backgroundLockPolicyValue;

  /// No description provided for @clipboardPolicy.
  ///
  /// In en, this message translates to:
  /// **'Sensitive clipboard'**
  String get clipboardPolicy;

  /// No description provided for @clipboardPolicyValue.
  ///
  /// In en, this message translates to:
  /// **'The app attempts to clear copied values after {seconds} seconds; Android vendor clipboards and third-party keyboard clipboards may not be cleared.'**
  String clipboardPolicyValue(int seconds);

  /// No description provided for @kdfPolicy.
  ///
  /// In en, this message translates to:
  /// **'Vault key derivation'**
  String get kdfPolicy;

  /// No description provided for @kdfPolicyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Available after the vault is unlocked.'**
  String get kdfPolicyUnavailable;

  /// No description provided for @settingsNoCredentials.
  ///
  /// In en, this message translates to:
  /// **'No credentials or vault plaintext are shown here.'**
  String get settingsNoCredentials;

  /// No description provided for @masterPasswordSettings.
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get masterPasswordSettings;

  /// No description provided for @masterPasswordChangeDescription.
  ///
  /// In en, this message translates to:
  /// **'Changing it creates a fresh salt and re-wraps the vault key without re-encrypting your entries.'**
  String get masterPasswordChangeDescription;

  /// No description provided for @changeMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Change master password'**
  String get changeMasterPassword;

  /// No description provided for @changeMasterPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change master password'**
  String get changeMasterPasswordTitle;

  /// No description provided for @masterPasswordChangeWarning.
  ///
  /// In en, this message translates to:
  /// **'This security-sensitive action verifies your current master password. Keep the new password safe; it cannot be recovered without a valid biometric recovery path.'**
  String get masterPasswordChangeWarning;

  /// No description provided for @currentMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Current master password'**
  String get currentMasterPassword;

  /// No description provided for @newMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'New master password'**
  String get newMasterPassword;

  /// No description provided for @confirmNewMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new master password'**
  String get confirmNewMasterPassword;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @masterPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Master password changed'**
  String get masterPasswordChanged;

  /// No description provided for @currentMasterPasswordInvalid.
  ///
  /// In en, this message translates to:
  /// **'Current master password is incorrect.'**
  String get currentMasterPasswordInvalid;

  /// No description provided for @newMasterPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a new master password.'**
  String get newMasterPasswordRequired;

  /// No description provided for @newMasterPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'The new master passwords do not match.'**
  String get newMasterPasswordsDoNotMatch;

  /// No description provided for @masterPasswordChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'The master password could not be changed.'**
  String get masterPasswordChangeFailed;

  /// No description provided for @recoverWithBiometrics.
  ///
  /// In en, this message translates to:
  /// **'Recover with biometrics'**
  String get recoverWithBiometrics;

  /// No description provided for @recoverMasterPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Recover master password'**
  String get recoverMasterPasswordTitle;

  /// No description provided for @masterPasswordRecoveryWarning.
  ///
  /// In en, this message translates to:
  /// **'Anyone who passes this biometric check can take over the vault by setting a new master password. Continue only on a trusted device.'**
  String get masterPasswordRecoveryWarning;

  /// No description provided for @recoverPassword.
  ///
  /// In en, this message translates to:
  /// **'Recover password'**
  String get recoverPassword;

  /// No description provided for @masterPasswordRecovered.
  ///
  /// In en, this message translates to:
  /// **'Master password recovered'**
  String get masterPasswordRecovered;

  /// No description provided for @syncRecoveryBackup.
  ///
  /// In en, this message translates to:
  /// **'Update any backup device with the new master password.'**
  String get syncRecoveryBackup;

  /// No description provided for @masterPasswordStrengthLabel.
  ///
  /// In en, this message translates to:
  /// **'Password strength: {strength}'**
  String masterPasswordStrengthLabel(String strength);

  /// No description provided for @newMasterPasswordTooWeak.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger master password.'**
  String get newMasterPasswordTooWeak;

  /// No description provided for @masterPasswordRecoveryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Password recovery is no longer available.'**
  String get masterPasswordRecoveryUnavailable;

  /// No description provided for @masterPasswordRecoveryCancelled.
  ///
  /// In en, this message translates to:
  /// **'Biometric confirmation was cancelled.'**
  String get masterPasswordRecoveryCancelled;

  /// No description provided for @masterPasswordRecoveryBiometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometric confirmation is unavailable. Your vault was not changed.'**
  String get masterPasswordRecoveryBiometricUnavailable;

  /// No description provided for @masterPasswordRecoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'The master password could not be recovered.'**
  String get masterPasswordRecoveryFailed;

  /// No description provided for @biometricSettings.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricSettings;

  /// No description provided for @biometricSecurityBoundary.
  ///
  /// In en, this message translates to:
  /// **'Biometrics release a device-protected key for this vault. Your master password is never stored and remains the fallback.'**
  String get biometricSecurityBoundary;

  /// No description provided for @biometricEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is enabled on this device.'**
  String get biometricEnabled;

  /// No description provided for @biometricNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock is not enabled.'**
  String get biometricNotEnabled;

  /// No description provided for @enableBiometric.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric unlock'**
  String get enableBiometric;

  /// No description provided for @disableBiometric.
  ///
  /// In en, this message translates to:
  /// **'Disable biometric unlock'**
  String get disableBiometric;

  /// No description provided for @resetBiometric.
  ///
  /// In en, this message translates to:
  /// **'Reset biometric unlock'**
  String get resetBiometric;

  /// No description provided for @confirmEnableBiometric.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric unlock on this device? You can still use your master password.'**
  String get confirmEnableBiometric;

  /// No description provided for @confirmDisableBiometric.
  ///
  /// In en, this message translates to:
  /// **'Disable biometric unlock? The master password will remain available.'**
  String get confirmDisableBiometric;

  /// No description provided for @biometricSetupFailed.
  ///
  /// In en, this message translates to:
  /// **'Biometric settings could not be changed.'**
  String get biometricSetupFailed;

  /// No description provided for @biometricSettingsInvalidated.
  ///
  /// In en, this message translates to:
  /// **'Biometric settings changed. Unlock with your master password before setting them up again.'**
  String get biometricSettingsInvalidated;

  /// No description provided for @stepUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Master password required'**
  String get stepUpTitle;

  /// No description provided for @stepUpDescription.
  ///
  /// In en, this message translates to:
  /// **'This security-sensitive action requires your master password. Biometric unlock alone is not enough.'**
  String get stepUpDescription;

  /// No description provided for @confirmMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Verify master password'**
  String get confirmMasterPassword;

  /// No description provided for @stepUpInvalidPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password is incorrect. The session was not changed.'**
  String get stepUpInvalidPassword;

  /// No description provided for @stepUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Master-password verification could not be completed.'**
  String get stepUpFailed;

  /// No description provided for @stepUpUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The vault is no longer unlocked. Unlock it again before continuing.'**
  String get stepUpUnavailable;

  /// No description provided for @generatorComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Password generator is coming next.'**
  String get generatorComingSoon;

  /// No description provided for @settingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Security settings are coming next.'**
  String get settingsComingSoon;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
