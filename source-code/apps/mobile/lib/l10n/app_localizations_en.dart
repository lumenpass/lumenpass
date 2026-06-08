// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'LumenPass';

  @override
  String get splashTitle => 'Secure access,\nsimplified.';

  @override
  String get splashSubtitle =>
      'Store passwords, passkeys, and private notes\nin one encrypted vault.';

  @override
  String get splashCta => 'Get Started';

  @override
  String get splashBiometricHint => 'Face ID & Touch ID ready';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingSkip => 'Skip tour';

  @override
  String get onboardingSwipeHint => 'Swipe or tap Continue';

  @override
  String get onboardingReadyHint => 'You\'re all set to begin';

  @override
  String get vaultPickerTitle => 'Choose a vault';

  @override
  String get vaultPickerSubtitle =>
      'Select a database to unlock with your master password or PIN.';

  @override
  String get vaultPickerSearchHint => 'Search vaults';

  @override
  String get vaultPickerEmptyTitle => 'No vaults yet';

  @override
  String get vaultPickerEmptyHint =>
      'Tap + to create a new database or open an existing one.';

  @override
  String vaultPickerNoResults(Object query) {
    return 'No results for \"$query\"';
  }

  @override
  String get vaultPickerDefaultBadge => 'Default';

  @override
  String get vaultPickerMenuSetDefault => 'Set default';

  @override
  String get vaultPickerMenuDuplicate => 'Duplicate';

  @override
  String get vaultPickerMenuRemove => 'Remove';

  @override
  String get vaultPickerRemoveTitle => 'Remove vault?';

  @override
  String vaultPickerRemoveMessage(Object name) {
    return 'Remove \"$name\" from your list?\n\nThe database file will not be deleted.';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDone => 'Done';

  @override
  String get unlockTitle => 'Unlock Vault';

  @override
  String unlockSubtitle(Object nickname, Object location) {
    return '$nickname · $location';
  }

  @override
  String get unlockPasswordLabel => 'Master Password';

  @override
  String get unlockPasswordHint => 'Enter password';

  @override
  String get unlockEmptyPassword => 'Empty Password';

  @override
  String get unlockAdvancedKeyFile => 'Advanced (Key File)';

  @override
  String get unlockKeyFileLabel => 'Key File';

  @override
  String get unlockChooseKeyFile => 'Choose key file';

  @override
  String get unlockButton => 'Unlock';

  @override
  String get homeTabHome => 'HOME';

  @override
  String get homeTabItems => 'ITEMS';

  @override
  String get homeTabTotp => 'TOTP';

  @override
  String get homeTabProfile => 'PROFILE';

  @override
  String get homeLastUsed => 'Last used items';

  @override
  String get homeCreateItem => '+ Create item';

  @override
  String get homeQuickAccess => 'Quick access';

  @override
  String get homeTags => 'Tags';

  @override
  String get homeSearchHint => 'Search items';

  @override
  String get homeSearchTotpHint => 'Search TOTP items';

  @override
  String get homeNoItems => 'No items in this vault';

  @override
  String get homeNoMatching => 'No matching items';

  @override
  String get homeNoTags => 'No tags yet';

  @override
  String get homeLockTitle => 'Lock vault?';

  @override
  String get homeLockMessage =>
      'You will need your master password to open this vault again.';

  @override
  String get homeLockAction => 'Lock';

  @override
  String get quickAccessAllItems => 'All items';

  @override
  String get quickAccessTotp => 'TOTP';

  @override
  String get quickAccessSecureNotes => 'Secure Notes';

  @override
  String get quickAccessSsh => 'SSH';

  @override
  String quickAccessItemCount(int count) {
    return '$count items';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionPersonalization => 'PERSONALIZATION';

  @override
  String get settingsSectionNotifications => 'NOTIFICATIONS & EMAIL';

  @override
  String get settingsSectionSecurity => 'SECURITY & PRIVACY';

  @override
  String get settingsSectionSyncBackup => 'SYNC & BACKUP';

  @override
  String get settingsSectionAboutFeedback => 'ABOUT & FEEDBACK';

  @override
  String get settingsGeneralLabel => 'General';

  @override
  String get settingsGeneralSubtitle =>
      'Language, default tab, quick vault selection';

  @override
  String get settingsAppearanceLabel => 'Appearance';

  @override
  String get settingsAppearanceSubtitle =>
      'Theme, accent color, text size, density';

  @override
  String get settingsNotificationsLabel => 'Notifications & Email';

  @override
  String get settingsNotificationsSubtitle =>
      'App notifications, news, product updates';

  @override
  String get settingsSecurityLabel => 'Security';

  @override
  String get settingsSecuritySubtitle =>
      'Unlock, auto-lock, clipboard, privacy';

  @override
  String get settingsAutofillLabel => 'AutoFill';

  @override
  String get settingsAutofillSubtitle =>
      'System AutoFill, inline suggestions, passkeys';

  @override
  String get settingsBackupLabel => 'Backup';

  @override
  String get settingsBackupSubtitle =>
      'Schedule, retention, location, restore from backup';

  @override
  String get settingsAboutLabel => 'About';

  @override
  String get settingsAboutSubtitle =>
      'Version, licenses, privacy policy, terms';

  @override
  String get settingsRateLabel => 'Rate LumenPass';

  @override
  String get settingsRateSubtitle =>
      'Help us out with a quick App Store review';

  @override
  String get generalTitle => 'General';

  @override
  String get generalPreferences => 'PREFERENCES';

  @override
  String get generalLanguage => 'Language';

  @override
  String get generalDefaultTab => 'Default tab';

  @override
  String get generalQuickVaultSelection => 'Quick vault selection';

  @override
  String get generalFooter =>
      'These preferences apply to the entire app and are stored on this device.';

  @override
  String get languageEnglish => 'English';

  @override
  String get defaultTabHome => 'Home';

  @override
  String get defaultTabItems => 'Items';

  @override
  String get defaultTabTotp => 'TOTP';

  @override
  String get defaultTabProfile => 'Profile';

  @override
  String get quickVaultDefault => 'Default Vault';

  @override
  String get quickVaultLastOpened => 'Last Opened';
}
