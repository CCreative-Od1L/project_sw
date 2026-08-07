// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Project SW';

  @override
  String get setupTitle => 'Project SW';

  @override
  String get createYourVault => 'Create your vault';

  @override
  String get vaultDescription =>
      'Your encrypted vault will be created on this device.';

  @override
  String get masterPassword => 'Master password';

  @override
  String get optimizingSecurityParameters => 'Optimizing security parameters…';

  @override
  String optimizingSecurityParametersProgress(int completed, int total) {
    return 'Optimizing security parameters… $completed/$total';
  }

  @override
  String get createVault => 'Create vault';

  @override
  String get vaultCreated => 'Vault created';

  @override
  String get securityParametersOptimized =>
      'Security parameters optimized for this device:';

  @override
  String argon2idParameters(int memoryMiB, int iterations, int parallelism) {
    return 'Argon2id: m=$memoryMiB MiB, t=$iterations, p=$parallelism';
  }

  @override
  String get continueToUnlock => 'Continue to unlock';

  @override
  String get vaultCreationFailed => 'Vault creation could not be completed.';

  @override
  String get unlockVault => 'Unlock vault';

  @override
  String get unlockYourVault => 'Unlock your vault';

  @override
  String get incorrectMasterPassword => 'Master password is incorrect.';

  @override
  String get vaultUnlockFailed => 'Vault unlock could not be completed.';

  @override
  String get unlock => 'Unlock';

  @override
  String get vault => 'Vault';

  @override
  String get generator => 'Generator';

  @override
  String get settings => 'Settings';

  @override
  String get vaultUnlocked => 'Vault unlocked';

  @override
  String get noEntries => 'No entries have been added yet.';

  @override
  String get addEntry => 'Add entry';

  @override
  String get name => 'Name';

  @override
  String get url => 'URL';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get notes => 'Notes';

  @override
  String get favorite => 'Favorite';

  @override
  String get saveEntry => 'Save entry';

  @override
  String get lockVault => 'Lock vault';

  @override
  String get entryDetail => 'Entry detail';

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get entrySaveFailed => 'The entry could not be saved.';

  @override
  String get copySensitiveValue => 'Copy sensitive value';

  @override
  String get copyPassword => 'Copy password';

  @override
  String get copySecretField => 'Copy secret field';

  @override
  String sensitiveCopiedClearsIn(int seconds) {
    return 'Sensitive value copied · clears in ${seconds}s';
  }

  @override
  String get clipboardCleared => 'Clipboard cleared';

  @override
  String get clipboardChangedNewerKept =>
      'Clipboard changed; newer content kept';

  @override
  String get generatorComingSoon => 'Password generator is coming next.';

  @override
  String get settingsComingSoon => 'Security settings are coming next.';
}
