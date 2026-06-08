import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
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
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'LumenPass'**
  String get appName;

  /// No description provided for @splashTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure access,\nsimplified.'**
  String get splashTitle;

  /// No description provided for @splashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Store passwords, passkeys, and private notes\nin one encrypted vault.'**
  String get splashSubtitle;

  /// No description provided for @splashCta.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get splashCta;

  /// No description provided for @splashBiometricHint.
  ///
  /// In en, this message translates to:
  /// **'Face ID & Touch ID ready'**
  String get splashBiometricHint;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip tour'**
  String get onboardingSkip;

  /// No description provided for @onboardingSwipeHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe or tap Continue'**
  String get onboardingSwipeHint;

  /// No description provided for @onboardingReadyHint.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set to begin'**
  String get onboardingReadyHint;

  /// No description provided for @vaultPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a vault'**
  String get vaultPickerTitle;

  /// No description provided for @vaultPickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a database to unlock with your master password or PIN.'**
  String get vaultPickerSubtitle;

  /// No description provided for @vaultPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search vaults'**
  String get vaultPickerSearchHint;

  /// No description provided for @vaultPickerEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No vaults yet'**
  String get vaultPickerEmptyTitle;

  /// No description provided for @vaultPickerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create a new database or open an existing one.'**
  String get vaultPickerEmptyHint;

  /// No description provided for @vaultPickerNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String vaultPickerNoResults(Object query);

  /// No description provided for @vaultPickerDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get vaultPickerDefaultBadge;

  /// No description provided for @vaultPickerMenuSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set default'**
  String get vaultPickerMenuSetDefault;

  /// No description provided for @vaultPickerMenuDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get vaultPickerMenuDuplicate;

  /// No description provided for @vaultPickerMenuRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get vaultPickerMenuRemove;

  /// No description provided for @vaultPickerRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove vault?'**
  String get vaultPickerRemoveTitle;

  /// No description provided for @vaultPickerRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from your list?\n\nThe database file will not be deleted.'**
  String vaultPickerRemoveMessage(Object name);

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @unlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock Vault'**
  String get unlockTitle;

  /// No description provided for @unlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{nickname} · {location}'**
  String unlockSubtitle(Object nickname, Object location);

  /// No description provided for @unlockPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get unlockPasswordLabel;

  /// No description provided for @unlockPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get unlockPasswordHint;

  /// No description provided for @unlockEmptyPassword.
  ///
  /// In en, this message translates to:
  /// **'Empty Password'**
  String get unlockEmptyPassword;

  /// No description provided for @unlockAdvancedKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Advanced (Key File)'**
  String get unlockAdvancedKeyFile;

  /// No description provided for @unlockKeyFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Key File'**
  String get unlockKeyFileLabel;

  /// No description provided for @unlockChooseKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Choose key file'**
  String get unlockChooseKeyFile;

  /// No description provided for @unlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// No description provided for @homeTabHome.
  ///
  /// In en, this message translates to:
  /// **'HOME'**
  String get homeTabHome;

  /// No description provided for @homeTabItems.
  ///
  /// In en, this message translates to:
  /// **'ITEMS'**
  String get homeTabItems;

  /// No description provided for @homeTabTotp.
  ///
  /// In en, this message translates to:
  /// **'TOTP'**
  String get homeTabTotp;

  /// No description provided for @homeTabProfile.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get homeTabProfile;

  /// No description provided for @homeLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used items'**
  String get homeLastUsed;

  /// No description provided for @homeCreateItem.
  ///
  /// In en, this message translates to:
  /// **'+ Create item'**
  String get homeCreateItem;

  /// No description provided for @homeQuickAccess.
  ///
  /// In en, this message translates to:
  /// **'Quick access'**
  String get homeQuickAccess;

  /// No description provided for @homeTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get homeTags;

  /// No description provided for @homeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get homeSearchHint;

  /// No description provided for @homeSearchTotpHint.
  ///
  /// In en, this message translates to:
  /// **'Search TOTP items'**
  String get homeSearchTotpHint;

  /// No description provided for @homeNoItems.
  ///
  /// In en, this message translates to:
  /// **'No items in this vault'**
  String get homeNoItems;

  /// No description provided for @homeNoMatching.
  ///
  /// In en, this message translates to:
  /// **'No matching items'**
  String get homeNoMatching;

  /// No description provided for @homeNoTags.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get homeNoTags;

  /// No description provided for @homeLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock vault?'**
  String get homeLockTitle;

  /// No description provided for @homeLockMessage.
  ///
  /// In en, this message translates to:
  /// **'You will need your master password to open this vault again.'**
  String get homeLockMessage;

  /// No description provided for @homeLockAction.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get homeLockAction;

  /// No description provided for @quickAccessAllItems.
  ///
  /// In en, this message translates to:
  /// **'All items'**
  String get quickAccessAllItems;

  /// No description provided for @quickAccessTotp.
  ///
  /// In en, this message translates to:
  /// **'TOTP'**
  String get quickAccessTotp;

  /// No description provided for @quickAccessSecureNotes.
  ///
  /// In en, this message translates to:
  /// **'Secure Notes'**
  String get quickAccessSecureNotes;

  /// No description provided for @quickAccessSsh.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get quickAccessSsh;

  /// No description provided for @quickAccessItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String quickAccessItemCount(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionPersonalization.
  ///
  /// In en, this message translates to:
  /// **'PERSONALIZATION'**
  String get settingsSectionPersonalization;

  /// No description provided for @settingsSectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS & EMAIL'**
  String get settingsSectionNotifications;

  /// No description provided for @settingsSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'SECURITY & PRIVACY'**
  String get settingsSectionSecurity;

  /// No description provided for @settingsSectionSyncBackup.
  ///
  /// In en, this message translates to:
  /// **'SYNC & BACKUP'**
  String get settingsSectionSyncBackup;

  /// No description provided for @settingsSectionAboutFeedback.
  ///
  /// In en, this message translates to:
  /// **'ABOUT & FEEDBACK'**
  String get settingsSectionAboutFeedback;

  /// No description provided for @settingsGeneralLabel.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneralLabel;

  /// No description provided for @settingsGeneralSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Language, default tab, quick vault selection'**
  String get settingsGeneralSubtitle;

  /// No description provided for @settingsAppearanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceLabel;

  /// No description provided for @settingsAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme, accent color, text size, density'**
  String get settingsAppearanceSubtitle;

  /// No description provided for @settingsNotificationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Notifications & Email'**
  String get settingsNotificationsLabel;

  /// No description provided for @settingsNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App notifications, news, product updates'**
  String get settingsNotificationsSubtitle;

  /// No description provided for @settingsSecurityLabel.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurityLabel;

  /// No description provided for @settingsSecuritySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock, auto-lock, clipboard, privacy'**
  String get settingsSecuritySubtitle;

  /// No description provided for @settingsAutofillLabel.
  ///
  /// In en, this message translates to:
  /// **'AutoFill'**
  String get settingsAutofillLabel;

  /// No description provided for @settingsAutofillSubtitle.
  ///
  /// In en, this message translates to:
  /// **'System AutoFill, inline suggestions, passkeys'**
  String get settingsAutofillSubtitle;

  /// No description provided for @settingsBackupLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get settingsBackupLabel;

  /// No description provided for @settingsBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule, retention, location, restore from backup'**
  String get settingsBackupSubtitle;

  /// No description provided for @settingsAboutLabel.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutLabel;

  /// No description provided for @settingsAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version, licenses, privacy policy, terms'**
  String get settingsAboutSubtitle;

  /// No description provided for @settingsRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Rate LumenPass'**
  String get settingsRateLabel;

  /// No description provided for @settingsRateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Help us out with a quick App Store review'**
  String get settingsRateSubtitle;

  /// No description provided for @generalTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalTitle;

  /// No description provided for @generalPreferences.
  ///
  /// In en, this message translates to:
  /// **'PREFERENCES'**
  String get generalPreferences;

  /// No description provided for @generalLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get generalLanguage;

  /// No description provided for @generalDefaultTab.
  ///
  /// In en, this message translates to:
  /// **'Default tab'**
  String get generalDefaultTab;

  /// No description provided for @generalQuickVaultSelection.
  ///
  /// In en, this message translates to:
  /// **'Quick vault selection'**
  String get generalQuickVaultSelection;

  /// No description provided for @generalFooter.
  ///
  /// In en, this message translates to:
  /// **'These preferences apply to the entire app and are stored on this device.'**
  String get generalFooter;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @defaultTabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get defaultTabHome;

  /// No description provided for @defaultTabItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get defaultTabItems;

  /// No description provided for @defaultTabTotp.
  ///
  /// In en, this message translates to:
  /// **'TOTP'**
  String get defaultTabTotp;

  /// No description provided for @defaultTabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get defaultTabProfile;

  /// No description provided for @quickVaultDefault.
  ///
  /// In en, this message translates to:
  /// **'Default Vault'**
  String get quickVaultDefault;

  /// No description provided for @quickVaultLastOpened.
  ///
  /// In en, this message translates to:
  /// **'Last Opened'**
  String get quickVaultLastOpened;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
