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
  String get useBiometric => 'Unlock with biometrics';

  @override
  String get biometricCancelled => 'Biometric unlock was cancelled.';

  @override
  String get biometricInvalidated =>
      'Biometric settings changed. Unlock with your master password to set it up again.';

  @override
  String get biometricUnavailable =>
      'Biometric unlock is unavailable. Use your master password.';

  @override
  String get biometricUnlockFailed =>
      'Biometric unlock could not be completed.';

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
  String get sensitiveCopied => 'Password copied to clipboard';

  @override
  String get generationMode => 'Mode';

  @override
  String get randomMode => 'Random';

  @override
  String get pronounceableMode => 'Pronounceable';

  @override
  String generatorLength(int length) {
    return 'Length: $length';
  }

  @override
  String get characterSets => 'Character sets';

  @override
  String get lowercase => 'Lowercase';

  @override
  String get uppercase => 'Uppercase';

  @override
  String get digits => 'Digits';

  @override
  String get symbols => 'Symbols';

  @override
  String get excludeAmbiguous => 'Exclude ambiguous characters';

  @override
  String get pronounceableHint =>
      'Pronounceable mode uses alternating consonants and vowels.';

  @override
  String get generate => 'Generate';

  @override
  String get copyGeneratedPassword => 'Copy generated password';

  @override
  String get useInEntry => 'Use in entry';

  @override
  String theoreticalEntropy(String bits) {
    return 'Theoretical entropy: $bits bits';
  }

  @override
  String get strengthWeak => 'Weak';

  @override
  String get strengthMedium => 'Medium';

  @override
  String get strengthStrong => 'Strong';

  @override
  String get strengthVeryStrong => 'Very strong';

  @override
  String get generationFailed => 'Password could not be generated.';

  @override
  String get searchEntries => 'Search entries';

  @override
  String get favoritesOnly => 'Favorites only';

  @override
  String get noMatchingEntries => 'No entries match your search.';

  @override
  String get securitySettingsReadOnly => 'Security settings';

  @override
  String get idleLockPolicy => 'Idle lock';

  @override
  String idleLockPolicyValue(int minutes) {
    return 'Locks after $minutes minutes without interaction.';
  }

  @override
  String get backgroundLockPolicy => 'Background lock';

  @override
  String get backgroundLockPolicyValue =>
      'Locks immediately when the app enters the background.';

  @override
  String get clipboardPolicy => 'Sensitive clipboard';

  @override
  String clipboardPolicyValue(int seconds) {
    return 'The app attempts to clear copied values after $seconds seconds; Android vendor clipboards and third-party keyboard clipboards may not be cleared.';
  }

  @override
  String get kdfPolicy => 'Vault key derivation';

  @override
  String get kdfPolicyUnavailable => 'Available after the vault is unlocked.';

  @override
  String get settingsNoCredentials =>
      'No credentials or vault plaintext are shown here.';

  @override
  String get masterPasswordSettings => 'Master password';

  @override
  String get masterPasswordChangeDescription =>
      'Changing it creates a fresh salt and re-wraps the vault key without re-encrypting your entries.';

  @override
  String get changeMasterPassword => 'Change master password';

  @override
  String get changeMasterPasswordTitle => 'Change master password';

  @override
  String get masterPasswordChangeWarning =>
      'This security-sensitive action verifies your current master password. Keep the new password safe; it cannot be recovered without a valid biometric recovery path.';

  @override
  String get currentMasterPassword => 'Current master password';

  @override
  String get newMasterPassword => 'New master password';

  @override
  String get confirmNewMasterPassword => 'Confirm new master password';

  @override
  String get changePassword => 'Change password';

  @override
  String get masterPasswordChanged => 'Master password changed';

  @override
  String get currentMasterPasswordInvalid =>
      'Current master password is incorrect.';

  @override
  String get newMasterPasswordRequired => 'Enter a new master password.';

  @override
  String get newMasterPasswordsDoNotMatch =>
      'The new master passwords do not match.';

  @override
  String get masterPasswordChangeFailed =>
      'The master password could not be changed.';

  @override
  String get biometricSettings => 'Biometric unlock';

  @override
  String get biometricSecurityBoundary =>
      'Biometrics release a device-protected key for this vault. Your master password is never stored and remains the fallback.';

  @override
  String get biometricEnabled => 'Biometric unlock is enabled on this device.';

  @override
  String get biometricNotEnabled => 'Biometric unlock is not enabled.';

  @override
  String get enableBiometric => 'Enable biometric unlock';

  @override
  String get disableBiometric => 'Disable biometric unlock';

  @override
  String get resetBiometric => 'Reset biometric unlock';

  @override
  String get confirmEnableBiometric =>
      'Enable biometric unlock on this device? You can still use your master password.';

  @override
  String get confirmDisableBiometric =>
      'Disable biometric unlock? The master password will remain available.';

  @override
  String get biometricSetupFailed => 'Biometric settings could not be changed.';

  @override
  String get biometricSettingsInvalidated =>
      'Biometric settings changed. Unlock with your master password before setting them up again.';

  @override
  String get stepUpTitle => 'Master password required';

  @override
  String get stepUpDescription =>
      'This security-sensitive action requires your master password. Biometric unlock alone is not enough.';

  @override
  String get confirmMasterPassword => 'Verify master password';

  @override
  String get stepUpInvalidPassword =>
      'Master password is incorrect. The session was not changed.';

  @override
  String get stepUpFailed =>
      'Master-password verification could not be completed.';

  @override
  String get stepUpUnavailable =>
      'The vault is no longer unlocked. Unlock it again before continuing.';

  @override
  String get generatorComingSoon => 'Password generator is coming next.';

  @override
  String get settingsComingSoon => 'Security settings are coming next.';
}
