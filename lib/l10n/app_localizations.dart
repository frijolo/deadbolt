import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('es'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @loadingProjects.
  ///
  /// In en, this message translates to:
  /// **'Loading projects...'**
  String get loadingProjects;

  /// No description provided for @projectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsTitle;

  /// No description provided for @menuNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get menuNew;

  /// No description provided for @noProjects.
  ///
  /// In en, this message translates to:
  /// **'No projects yet.\nTap + to create one.'**
  String get noProjects;

  /// No description provided for @deleteProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProjectTitle;

  /// No description provided for @deleteProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteProjectConfirm(String name);

  /// No description provided for @couldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read file'**
  String get couldNotReadFile;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @importDescriptorMode.
  ///
  /// In en, this message translates to:
  /// **'Import descriptor'**
  String get importDescriptorMode;

  /// No description provided for @fromScratchMode.
  ///
  /// In en, this message translates to:
  /// **'Start from scratch'**
  String get fromScratchMode;

  /// No description provided for @projectNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectNameLabel;

  /// No description provided for @descriptorLabel.
  ///
  /// In en, this message translates to:
  /// **'Descriptor'**
  String get descriptorLabel;

  /// No description provided for @descriptorHint.
  ///
  /// In en, this message translates to:
  /// **'Paste your Bitcoin descriptor here...'**
  String get descriptorHint;

  /// No description provided for @descriptorViewAlias.
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get descriptorViewAlias;

  /// No description provided for @descriptorViewRaw.
  ///
  /// In en, this message translates to:
  /// **'Raw'**
  String get descriptorViewRaw;

  /// No description provided for @networkLabel.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkLabel;

  /// No description provided for @selectNetworkTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select network'**
  String get selectNetworkTooltip;

  /// No description provided for @walletTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Wallet type'**
  String get walletTypeLabel;

  /// No description provided for @analyzeAndSave.
  ///
  /// In en, this message translates to:
  /// **'Analyze & Save'**
  String get analyzeAndSave;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create Project'**
  String get createProject;

  /// No description provided for @projectNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Project name is required'**
  String get projectNameRequired;

  /// No description provided for @descriptorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Descriptor cannot be empty'**
  String get descriptorEmpty;

  /// No description provided for @analyzingDescriptor.
  ///
  /// In en, this message translates to:
  /// **'Analyzing descriptor...'**
  String get analyzingDescriptor;

  /// No description provided for @creatingProject.
  ///
  /// In en, this message translates to:
  /// **'Creating project...'**
  String get creatingProject;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @loadingAppInfo.
  ///
  /// In en, this message translates to:
  /// **'Loading app info...'**
  String get loadingAppInfo;

  /// No description provided for @bitcoinDescriptorAnalyzer.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin Descriptor Analyzer'**
  String get bitcoinDescriptorAnalyzer;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionLabel;

  /// No description provided for @projectSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get projectSectionTitle;

  /// No description provided for @githubRepository.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get githubRepository;

  /// No description provided for @securityGpg.
  ///
  /// In en, this message translates to:
  /// **'Security & GPG'**
  String get securityGpg;

  /// No description provided for @licenseLabel.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get licenseLabel;

  /// No description provided for @mitLicense.
  ///
  /// In en, this message translates to:
  /// **'MIT License'**
  String get mitLicense;

  /// No description provided for @openSourceDescription.
  ///
  /// In en, this message translates to:
  /// **'Open source Bitcoin wallet descriptor analysis'**
  String get openSourceDescription;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @activeNetworkLabel.
  ///
  /// In en, this message translates to:
  /// **'Active Network'**
  String get activeNetworkLabel;

  /// No description provided for @walletsHiddenOnOtherNetworks.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, one{wallet} other{wallets}} on other networks — change in Settings'**
  String walletsHiddenOnOtherNetworks(int count);

  /// No description provided for @restoringToNetwork.
  ///
  /// In en, this message translates to:
  /// **'Restoring to: {network}'**
  String restoringToNetwork(String network);

  /// No description provided for @preferredWalletTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Default Wallet Type'**
  String get preferredWalletTypeLabel;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsLanguageEs.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get settingsLanguageEs;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @screenshotProtectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Screenshot Protection'**
  String get screenshotProtectionLabel;

  /// No description provided for @screenshotProtectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prevent screenshots and screen recording'**
  String get screenshotProtectionSubtitle;

  /// No description provided for @settingsSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSectionSecurity;

  /// No description provided for @biometricLockLabel.
  ///
  /// In en, this message translates to:
  /// **'Biometric Lock'**
  String get biometricLockLabel;

  /// No description provided for @biometricLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Require biometrics to open the app'**
  String get biometricLockSubtitle;

  /// No description provided for @biometricTimeoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Lock after'**
  String get biometricTimeoutLabel;

  /// No description provided for @biometricTimeoutImmediate.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get biometricTimeoutImmediate;

  /// No description provided for @biometricTimeout1Min.
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get biometricTimeout1Min;

  /// No description provided for @biometricTimeout5Min.
  ///
  /// In en, this message translates to:
  /// **'5 minutes'**
  String get biometricTimeout5Min;

  /// No description provided for @biometricUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Authenticate to access Deadbolt'**
  String get biometricUnlockReason;

  /// No description provided for @biometricUnlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get biometricUnlockButton;

  /// No description provided for @biometricSetupFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Biometric lock was not enabled.'**
  String get biometricSetupFailed;

  /// No description provided for @biometricWalletSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get biometricWalletSectionTitle;

  /// No description provided for @biometricWalletUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Authenticate to open wallet'**
  String get biometricWalletUnlockReason;

  /// No description provided for @discardChangesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get discardChangesTooltip;

  /// No description provided for @moreOptionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptionsTooltip;

  /// No description provided for @buildFabLabel.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get buildFabLabel;

  /// No description provided for @descriptorOutdatedBanner.
  ///
  /// In en, this message translates to:
  /// **'Descriptor outdated · tap Build to regenerate'**
  String get descriptorOutdatedBanner;

  /// No description provided for @keySectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get keySectionLabel;

  /// No description provided for @keysSection.
  ///
  /// In en, this message translates to:
  /// **'Keys ({count})'**
  String keysSection(int count);

  /// No description provided for @addKeyButton.
  ///
  /// In en, this message translates to:
  /// **'Add key'**
  String get addKeyButton;

  /// No description provided for @spendPathsSection.
  ///
  /// In en, this message translates to:
  /// **'Spend paths ({count})'**
  String spendPathsSection(int count);

  /// No description provided for @addSpendPath.
  ///
  /// In en, this message translates to:
  /// **'Add spend path'**
  String get addSpendPath;

  /// No description provided for @addKeyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Key'**
  String get addKeyDialogTitle;

  /// No description provided for @invalidKeyspecFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid keyspec format. Expected: [mfp/path]xpub'**
  String get invalidKeyspecFormat;

  /// No description provided for @duplicateMfp.
  ///
  /// In en, this message translates to:
  /// **'A key with MFP {mfp} already exists'**
  String duplicateMfp(String mfp);

  /// No description provided for @copyDescriptorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Export descriptor'**
  String get copyDescriptorTooltip;

  /// No description provided for @descriptorCopied.
  ///
  /// In en, this message translates to:
  /// **'Descriptor copied'**
  String get descriptorCopied;

  /// No description provided for @copyToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get copyToClipboard;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save as…'**
  String get saveAs;

  /// No description provided for @shareFile.
  ///
  /// In en, this message translates to:
  /// **'Share file'**
  String get shareFile;

  /// No description provided for @shareText.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareText;

  /// No description provided for @showQrCode.
  ///
  /// In en, this message translates to:
  /// **'Show QR code'**
  String get showQrCode;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrCode;

  /// No description provided for @fromFile.
  ///
  /// In en, this message translates to:
  /// **'From file'**
  String get fromFile;

  /// No description provided for @showAsText.
  ///
  /// In en, this message translates to:
  /// **'Show as text'**
  String get showAsText;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @pasteText.
  ///
  /// In en, this message translates to:
  /// **'Paste text'**
  String get pasteText;

  /// No description provided for @pasteTextHint.
  ///
  /// In en, this message translates to:
  /// **'Paste your content here…'**
  String get pasteTextHint;

  /// No description provided for @clipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty'**
  String get clipboardEmpty;

  /// No description provided for @clipboardWillClear.
  ///
  /// In en, this message translates to:
  /// **'Clipboard will be cleared in {seconds}s'**
  String clipboardWillClear(int seconds);

  /// No description provided for @clipboardCleared.
  ///
  /// In en, this message translates to:
  /// **'Clipboard cleared'**
  String get clipboardCleared;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @qrNotFoundInImage.
  ///
  /// In en, this message translates to:
  /// **'No QR code found in image'**
  String get qrNotFoundInImage;

  /// No description provided for @cameraError.
  ///
  /// In en, this message translates to:
  /// **'Camera not available on this platform'**
  String get cameraError;

  /// No description provided for @importFromQrImage.
  ///
  /// In en, this message translates to:
  /// **'Import QR image'**
  String get importFromQrImage;

  /// No description provided for @qrDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrDialogTitle;

  /// No description provided for @qrAnimatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Animated (BC-UR)'**
  String get qrAnimatedLabel;

  /// No description provided for @qrPart.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String qrPart(int current, int total);

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @savedToDownloads.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get savedToDownloads;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @projectNameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectNameDialogTitle;

  /// No description provided for @discardChangesDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesDialogTitle;

  /// No description provided for @discardChangesContent.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. This action cannot be undone.'**
  String get discardChangesContent;

  /// No description provided for @changeWalletTypeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change wallet type'**
  String get changeWalletTypeTooltip;

  /// No description provided for @buildingDescriptor.
  ///
  /// In en, this message translates to:
  /// **'Building descriptor...'**
  String get buildingDescriptor;

  /// No description provided for @buildingDescriptorMultiPath.
  ///
  /// In en, this message translates to:
  /// **'Building descriptor with multiple paths...'**
  String get buildingDescriptorMultiPath;

  /// No description provided for @buildingComplexDescriptor.
  ///
  /// In en, this message translates to:
  /// **'Building complex descriptor...\nThis may take some time'**
  String get buildingComplexDescriptor;

  /// No description provided for @analyzingDescriptorLoading.
  ///
  /// In en, this message translates to:
  /// **'Analyzing descriptor...'**
  String get analyzingDescriptorLoading;

  /// No description provided for @analyzingComplexDescriptor.
  ///
  /// In en, this message translates to:
  /// **'Analyzing complex descriptor...'**
  String get analyzingComplexDescriptor;

  /// No description provided for @analyzingAndSaving.
  ///
  /// In en, this message translates to:
  /// **'Analyzing and saving...'**
  String get analyzingAndSaving;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get enterName;

  /// No description provided for @nameAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'This name is already used by another key'**
  String get nameAlreadyUsed;

  /// No description provided for @copyKeyspecTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy keyspec'**
  String get copyKeyspecTooltip;

  /// No description provided for @keyCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get keyCopied;

  /// No description provided for @rootPath.
  ///
  /// In en, this message translates to:
  /// **'(root)'**
  String get rootPath;

  /// No description provided for @keyNameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Key name'**
  String get keyNameDialogTitle;

  /// No description provided for @keyFingerprintLabel.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get keyFingerprintLabel;

  /// No description provided for @keyDerivPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Derivation path'**
  String get keyDerivPathLabel;

  /// No description provided for @keyXpubLabel.
  ///
  /// In en, this message translates to:
  /// **'Extended public key'**
  String get keyXpubLabel;

  /// No description provided for @removeKeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove key from project'**
  String get removeKeyTooltip;

  /// No description provided for @keyInUseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Key in use, cannot remove'**
  String get keyInUseTooltip;

  /// No description provided for @hotKeyBadge.
  ///
  /// In en, this message translates to:
  /// **'HOT'**
  String get hotKeyBadge;

  /// No description provided for @privateKeySection.
  ///
  /// In en, this message translates to:
  /// **'Stored seed'**
  String get privateKeySection;

  /// No description provided for @viewPrivateKeyButton.
  ///
  /// In en, this message translates to:
  /// **'View seed phrase'**
  String get viewPrivateKeyButton;

  /// No description provided for @deletePrivateKeyButton.
  ///
  /// In en, this message translates to:
  /// **'Delete stored seed'**
  String get deletePrivateKeyButton;

  /// No description provided for @viewPrivateKeyDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Make sure no one can see your screen. Your seed phrase gives full access to your funds.'**
  String get viewPrivateKeyDisclaimer;

  /// No description provided for @deletePrivateKeyDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This deletes the seed phrase stored in this project. If you don\'t have a backup, you will permanently lose access to this key. The public key will remain in the project as watch-only.'**
  String get deletePrivateKeyDisclaimer;

  /// No description provided for @deleteWalletPrivateKeyDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This removes the signing key from this wallet. You will no longer be able to sign transactions with it.'**
  String get deleteWalletPrivateKeyDisclaimer;

  /// No description provided for @viewPrivateKeyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Show seed'**
  String get viewPrivateKeyConfirm;

  /// No description provided for @deletePrivateKeyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete seed'**
  String get deletePrivateKeyConfirm;

  /// No description provided for @seedPhraseDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Seed phrase'**
  String get seedPhraseDialogTitle;

  /// No description provided for @seedPhraseCopied.
  ///
  /// In en, this message translates to:
  /// **'Seed phrase copied'**
  String get seedPhraseCopied;

  /// No description provided for @seedExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Seed Export'**
  String get seedExportTitle;

  /// No description provided for @seedExportTabWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get seedExportTabWords;

  /// No description provided for @seedExportTabQr.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get seedExportTabQr;

  /// No description provided for @seedExportTabGuide.
  ///
  /// In en, this message translates to:
  /// **'Paper Guide'**
  String get seedExportTabGuide;

  /// No description provided for @seedQrStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard SeedQR'**
  String get seedQrStandard;

  /// No description provided for @seedQrCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact SeedQR'**
  String get seedQrCompact;

  /// No description provided for @seedPassphraseWarning.
  ///
  /// In en, this message translates to:
  /// **'This seed has a passphrase that is not shown here.'**
  String get seedPassphraseWarning;

  /// No description provided for @seedPassphraseNotIncluded.
  ///
  /// In en, this message translates to:
  /// **'Passphrase not included in QR'**
  String get seedPassphraseNotIncluded;

  /// No description provided for @seedMfpSeedOnly.
  ///
  /// In en, this message translates to:
  /// **'Seed only'**
  String get seedMfpSeedOnly;

  /// No description provided for @seedMfpWithPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Seed + passphrase'**
  String get seedMfpWithPassphrase;

  /// No description provided for @seedGuideSegmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Segment {label} of {total}'**
  String seedGuideSegmentLabel(String label, int total);

  /// No description provided for @seedGuideDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'All segments transcribed'**
  String get seedGuideDoneTitle;

  /// No description provided for @seedGuideDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Verify by scanning your paper QR with a camera.'**
  String get seedGuideDoneBody;

  /// No description provided for @seedGuideVerifyQr.
  ///
  /// In en, this message translates to:
  /// **'Verify QR'**
  String get seedGuideVerifyQr;

  /// No description provided for @seedGuideVerifySuccess.
  ///
  /// In en, this message translates to:
  /// **'QR verified correctly.'**
  String get seedGuideVerifySuccess;

  /// No description provided for @seedGuideVerifyMismatch.
  ///
  /// In en, this message translates to:
  /// **'QR does not match the seed.'**
  String get seedGuideVerifyMismatch;

  /// No description provided for @seedGuideInstructions.
  ///
  /// In en, this message translates to:
  /// **'Transcribe each segment to paper. Filled squares = dark modules.'**
  String get seedGuideInstructions;

  /// No description provided for @seedGuideTapToAdvance.
  ///
  /// In en, this message translates to:
  /// **'Tap QR to advance'**
  String get seedGuideTapToAdvance;

  /// No description provided for @seedGuideRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get seedGuideRestart;

  /// No description provided for @seedQrSize.
  ///
  /// In en, this message translates to:
  /// **'{format} · {size}×{size}'**
  String seedQrSize(String format, int size);

  /// No description provided for @spendPathNameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Spend path name'**
  String get spendPathNameDialogTitle;

  /// No description provided for @keyPathBadge.
  ///
  /// In en, this message translates to:
  /// **'KEY PATH'**
  String get keyPathBadge;

  /// No description provided for @setAsKeyPath.
  ///
  /// In en, this message translates to:
  /// **'Set as key path'**
  String get setAsKeyPath;

  /// No description provided for @removePathTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove path'**
  String get removePathTooltip;

  /// No description provided for @keysLabel.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get keysLabel;

  /// No description provided for @newKey.
  ///
  /// In en, this message translates to:
  /// **'New key'**
  String get newKey;

  /// No description provided for @noTimelock.
  ///
  /// In en, this message translates to:
  /// **'No timelock'**
  String get noTimelock;

  /// No description provided for @priorityBadge.
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String priorityBadge(int priority);

  /// No description provided for @changeThresholdTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change threshold'**
  String get changeThresholdTooltip;

  /// No description provided for @ofCount.
  ///
  /// In en, this message translates to:
  /// **'of {count}'**
  String ofCount(int count);

  /// No description provided for @thresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get thresholdLabel;

  /// No description provided for @sweepCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Sweep cost'**
  String get sweepCostLabel;

  /// No description provided for @trDepthLabel.
  ///
  /// In en, this message translates to:
  /// **'TR depth'**
  String get trDepthLabel;

  /// No description provided for @changePriorityTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change priority'**
  String get changePriorityTooltip;

  /// No description provided for @timelockDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Timelock'**
  String get timelockDialogTitle;

  /// No description provided for @relativeTimelock.
  ///
  /// In en, this message translates to:
  /// **'Relative'**
  String get relativeTimelock;

  /// No description provided for @absoluteTimelock.
  ///
  /// In en, this message translates to:
  /// **'Absolute'**
  String get absoluteTimelock;

  /// No description provided for @blocksTimelock.
  ///
  /// In en, this message translates to:
  /// **'Blocks'**
  String get blocksTimelock;

  /// No description provided for @timeTimelock.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeTimelock;

  /// No description provided for @timestampTimelock.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get timestampTimelock;

  /// No description provided for @selectDateAndTime.
  ///
  /// In en, this message translates to:
  /// **'Select date and time'**
  String get selectDateAndTime;

  /// No description provided for @blocksRelHint.
  ///
  /// In en, this message translates to:
  /// **'Blocks (0-65,535)'**
  String get blocksRelHint;

  /// No description provided for @timeUnitsHint.
  ///
  /// In en, this message translates to:
  /// **'Units × 512s (0-65,535)'**
  String get timeUnitsHint;

  /// No description provided for @blocksAbsHint.
  ///
  /// In en, this message translates to:
  /// **'Blocks (0-499,999,999)'**
  String get blocksAbsHint;

  /// No description provided for @timelockValueMax.
  ///
  /// In en, this message translates to:
  /// **'Value must be ≤ 65,535'**
  String get timelockValueMax;

  /// No description provided for @blockHeightMax.
  ///
  /// In en, this message translates to:
  /// **'Block height must be < 500,000,000'**
  String get blockHeightMax;

  /// No description provided for @timestampMin.
  ///
  /// In en, this message translates to:
  /// **'Timestamp must be ≥ 500,000,000'**
  String get timestampMin;

  /// No description provided for @mustHaveAtLeastOneKey.
  ///
  /// In en, this message translates to:
  /// **'Must have at least one key'**
  String get mustHaveAtLeastOneKey;

  /// No description provided for @thresholdMustBeAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Threshold must be at least 1'**
  String get thresholdMustBeAtLeastOne;

  /// No description provided for @thresholdCannotExceed.
  ///
  /// In en, this message translates to:
  /// **'Threshold cannot exceed number of keys'**
  String get thresholdCannotExceed;

  /// No description provided for @errorCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Error copied to clipboard'**
  String get errorCopiedToClipboard;

  /// No description provided for @projectExportedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Project exported successfully'**
  String get projectExportedSuccess;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @networkMainnet.
  ///
  /// In en, this message translates to:
  /// **'Mainnet'**
  String get networkMainnet;

  /// No description provided for @networkTestnet.
  ///
  /// In en, this message translates to:
  /// **'Testnet'**
  String get networkTestnet;

  /// No description provided for @networkTestnet4.
  ///
  /// In en, this message translates to:
  /// **'Testnet4'**
  String get networkTestnet4;

  /// No description provided for @networkSignet.
  ///
  /// In en, this message translates to:
  /// **'Signet'**
  String get networkSignet;

  /// No description provided for @networkRegtest.
  ///
  /// In en, this message translates to:
  /// **'Regtest'**
  String get networkRegtest;

  /// No description provided for @walletTypeP2pkh.
  ///
  /// In en, this message translates to:
  /// **'Legacy (P2PKH)'**
  String get walletTypeP2pkh;

  /// No description provided for @walletTypeP2wpkh.
  ///
  /// In en, this message translates to:
  /// **'Segwit (P2WPKH)'**
  String get walletTypeP2wpkh;

  /// No description provided for @walletTypeP2sh.
  ///
  /// In en, this message translates to:
  /// **'Legacy (P2SH)'**
  String get walletTypeP2sh;

  /// No description provided for @walletTypeP2wsh.
  ///
  /// In en, this message translates to:
  /// **'Segwit (P2WSH)'**
  String get walletTypeP2wsh;

  /// No description provided for @walletTypeP2tr.
  ///
  /// In en, this message translates to:
  /// **'Taproot (P2TR)'**
  String get walletTypeP2tr;

  /// No description provided for @walletTypeP2shWpkh.
  ///
  /// In en, this message translates to:
  /// **'Nested Segwit (P2SH-WPKH)'**
  String get walletTypeP2shWpkh;

  /// No description provided for @walletTypeP2shWsh.
  ///
  /// In en, this message translates to:
  /// **'Nested Segwit (P2SH-WSH)'**
  String get walletTypeP2shWsh;

  /// No description provided for @walletTypeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get walletTypeUnknown;

  /// No description provided for @walletPolicySingleSig.
  ///
  /// In en, this message translates to:
  /// **'SingleSig'**
  String get walletPolicySingleSig;

  /// No description provided for @walletPolicyMiniscript.
  ///
  /// In en, this message translates to:
  /// **'Miniscript'**
  String get walletPolicyMiniscript;

  /// No description provided for @walletAddressLegacy.
  ///
  /// In en, this message translates to:
  /// **'Legacy'**
  String get walletAddressLegacy;

  /// No description provided for @walletAddressSegwit.
  ///
  /// In en, this message translates to:
  /// **'SegWit'**
  String get walletAddressSegwit;

  /// No description provided for @walletAddressNested.
  ///
  /// In en, this message translates to:
  /// **'Nested'**
  String get walletAddressNested;

  /// No description provided for @walletAddressTaproot.
  ///
  /// In en, this message translates to:
  /// **'Taproot'**
  String get walletAddressTaproot;

  /// No description provided for @navDesigner.
  ///
  /// In en, this message translates to:
  /// **'Designer'**
  String get navDesigner;

  /// No description provided for @navWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get navWallet;

  /// No description provided for @walletsTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallets'**
  String get walletsTitle;

  /// No description provided for @noWallets.
  ///
  /// In en, this message translates to:
  /// **'No wallets yet.\nTap + to create one.'**
  String get noWallets;

  /// No description provided for @createWalletFromProject.
  ///
  /// In en, this message translates to:
  /// **'Create wallet'**
  String get createWalletFromProject;

  /// No description provided for @generateProjectFromWallet.
  ///
  /// In en, this message translates to:
  /// **'Analyze in Designer'**
  String get generateProjectFromWallet;

  /// No description provided for @projectHasNoDescriptor.
  ///
  /// In en, this message translates to:
  /// **'This project has no descriptor yet. Build one first.'**
  String get projectHasNoDescriptor;

  /// No description provided for @loadingWallets.
  ///
  /// In en, this message translates to:
  /// **'Loading wallets...'**
  String get loadingWallets;

  /// No description provided for @openingWallet.
  ///
  /// In en, this message translates to:
  /// **'Opening wallet…'**
  String get openingWallet;

  /// No description provided for @loadingWalletData.
  ///
  /// In en, this message translates to:
  /// **'Loading wallet data…'**
  String get loadingWalletData;

  /// No description provided for @loadingAddresses.
  ///
  /// In en, this message translates to:
  /// **'Loading addresses…'**
  String get loadingAddresses;

  /// No description provided for @loadingCoins.
  ///
  /// In en, this message translates to:
  /// **'Loading coins…'**
  String get loadingCoins;

  /// No description provided for @initializingCamera.
  ///
  /// In en, this message translates to:
  /// **'Initializing camera…'**
  String get initializingCamera;

  /// No description provided for @switchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get switchCamera;

  /// No description provided for @deleteWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete wallet'**
  String get deleteWalletTitle;

  /// No description provided for @deleteWalletConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteWalletConfirm(String name);

  /// No description provided for @createWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'New Wallet'**
  String get createWalletTitle;

  /// No description provided for @walletNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Wallet name'**
  String get walletNameLabel;

  /// No description provided for @walletNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Wallet name is required'**
  String get walletNameRequired;

  /// No description provided for @deleteProjectAfterCreate.
  ///
  /// In en, this message translates to:
  /// **'Delete this project after creating the wallet'**
  String get deleteProjectAfterCreate;

  /// No description provided for @createWalletButton.
  ///
  /// In en, this message translates to:
  /// **'Create wallet'**
  String get createWalletButton;

  /// No description provided for @creatingWallet.
  ///
  /// In en, this message translates to:
  /// **'Creating wallet...'**
  String get creatingWallet;

  /// No description provided for @balanceConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get balanceConfirmed;

  /// No description provided for @balancePending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get balancePending;

  /// No description provided for @balanceImmature.
  ///
  /// In en, this message translates to:
  /// **'Immature'**
  String get balanceImmature;

  /// No description provided for @balanceSats.
  ///
  /// In en, this message translates to:
  /// **'{sats} sats'**
  String balanceSats(int sats);

  /// No description provided for @balanceBtc.
  ///
  /// In en, this message translates to:
  /// **'{btc} BTC'**
  String balanceBtc(String btc);

  /// No description provided for @walletPasswordProtected.
  ///
  /// In en, this message translates to:
  /// **'Password protected'**
  String get walletPasswordProtected;

  /// No description provided for @lockWallet.
  ///
  /// In en, this message translates to:
  /// **'Lock wallet'**
  String get lockWallet;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSaved;

  /// No description provided for @changeProtectionMenu.
  ///
  /// In en, this message translates to:
  /// **'Change protection'**
  String get changeProtectionMenu;

  /// No description provided for @renameWalletMenu.
  ///
  /// In en, this message translates to:
  /// **'Rename wallet'**
  String get renameWalletMenu;

  /// No description provided for @renameWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename wallet'**
  String get renameWalletTitle;

  /// No description provided for @walletRenamedToast.
  ///
  /// In en, this message translates to:
  /// **'Renamed to \"{name}\"'**
  String walletRenamedToast(String name);

  /// No description provided for @walletSecurityLabel.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get walletSecurityLabel;

  /// No description provided for @walletSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet Security'**
  String get walletSecurityTitle;

  /// No description provided for @encryptionSection.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get encryptionSection;

  /// No description provided for @descriptorSigsSection.
  ///
  /// In en, this message translates to:
  /// **'Descriptor Signatures'**
  String get descriptorSigsSection;

  /// No description provided for @manageSignatures.
  ///
  /// In en, this message translates to:
  /// **'Manage Signatures'**
  String get manageSignatures;

  /// No description provided for @goToSecurity.
  ///
  /// In en, this message translates to:
  /// **'Go to Security'**
  String get goToSecurity;

  /// No description provided for @noParticipatingKeys.
  ///
  /// In en, this message translates to:
  /// **'No participating keys found'**
  String get noParticipatingKeys;

  /// No description provided for @descriptorSigAbsent.
  ///
  /// In en, this message translates to:
  /// **'No signatures'**
  String get descriptorSigAbsent;

  /// No description provided for @descriptorSigVerified.
  ///
  /// In en, this message translates to:
  /// **'Signatures verified'**
  String get descriptorSigVerified;

  /// No description provided for @descriptorSigInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid signatures'**
  String get descriptorSigInvalid;

  /// No description provided for @descriptorSigOwnerUnsigned.
  ///
  /// In en, this message translates to:
  /// **'Owner xpub not signed'**
  String get descriptorSigOwnerUnsigned;

  /// No description provided for @descriptorSigUnknown.
  ///
  /// In en, this message translates to:
  /// **'Signature status unknown'**
  String get descriptorSigUnknown;

  /// No description provided for @walletBalanceUnknown.
  ///
  /// In en, this message translates to:
  /// **'–'**
  String get walletBalanceUnknown;

  /// No description provided for @notYetSynced.
  ///
  /// In en, this message translates to:
  /// **'Not yet synced'**
  String get notYetSynced;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced: {time}'**
  String lastSynced(String time);

  /// No description provided for @syncButton.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncButton;

  /// No description provided for @syncTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sync wallet'**
  String get syncTooltip;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// No description provided for @rescanButton.
  ///
  /// In en, this message translates to:
  /// **'Full rescan'**
  String get rescanButton;

  /// No description provided for @rescanConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Full rescan'**
  String get rescanConfirmTitle;

  /// No description provided for @rescanConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will re-scan all addresses from scratch. It may take longer than a normal sync.'**
  String get rescanConfirmBody;

  /// No description provided for @transactionsSection.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactionsSection;

  /// No description provided for @noTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get noTransactions;

  /// No description provided for @txReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get txReceived;

  /// No description provided for @txSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get txSent;

  /// No description provided for @txSelfTransfer.
  ///
  /// In en, this message translates to:
  /// **'Self-transfer'**
  String get txSelfTransfer;

  /// No description provided for @txConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get txConfirmed;

  /// No description provided for @txUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Unconfirmed'**
  String get txUnconfirmed;

  /// No description provided for @txId.
  ///
  /// In en, this message translates to:
  /// **'TXID'**
  String get txId;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @txDelayBroadcastSection.
  ///
  /// In en, this message translates to:
  /// **'Delay broadcast (nLockTime)'**
  String get txDelayBroadcastSection;

  /// No description provided for @txDelayDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get txDelayDays;

  /// No description provided for @txDelayHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get txDelayHours;

  /// No description provided for @txDelayMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get txDelayMinutes;

  /// No description provided for @txDelayNoneHint.
  ///
  /// In en, this message translates to:
  /// **'Set days / hours / minutes to delay broadcast.'**
  String get txDelayNoneHint;

  /// No description provided for @txDelayApproxBlocks.
  ///
  /// In en, this message translates to:
  /// **'≈ {blocks} blocks'**
  String txDelayApproxBlocks(int blocks);

  /// No description provided for @txDelayUnlockEta.
  ///
  /// In en, this message translates to:
  /// **'unlock at block {height} (~{eta})'**
  String txDelayUnlockEta(int height, String eta);

  /// No description provided for @psbtLockedMaturity.
  ///
  /// In en, this message translates to:
  /// **'Locked · {blocks} blocks'**
  String psbtLockedMaturity(int blocks);

  /// No description provided for @psbtLockedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Locked · {eta} ({blocks} blocks left)'**
  String psbtLockedTooltip(String eta, int blocks);

  /// No description provided for @psbtBroadcastReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to broadcast'**
  String get psbtBroadcastReady;

  /// No description provided for @electrumSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Electrum Servers'**
  String get electrumSectionTitle;

  /// No description provided for @electrumUrlHint.
  ///
  /// In en, this message translates to:
  /// **'ssl://host:port or tcp://host:port'**
  String get electrumUrlHint;

  /// No description provided for @electrumNetworkMainnet.
  ///
  /// In en, this message translates to:
  /// **'Mainnet Electrum'**
  String get electrumNetworkMainnet;

  /// No description provided for @electrumNetworkTestnet.
  ///
  /// In en, this message translates to:
  /// **'Testnet Electrum'**
  String get electrumNetworkTestnet;

  /// No description provided for @electrumNetworkTestnet4.
  ///
  /// In en, this message translates to:
  /// **'Testnet4 Electrum'**
  String get electrumNetworkTestnet4;

  /// No description provided for @electrumNetworkSignet.
  ///
  /// In en, this message translates to:
  /// **'Signet Electrum'**
  String get electrumNetworkSignet;

  /// No description provided for @electrumNetworkRegtest.
  ///
  /// In en, this message translates to:
  /// **'Regtest Electrum'**
  String get electrumNetworkRegtest;

  /// No description provided for @settingsMinFeeRate.
  ///
  /// In en, this message translates to:
  /// **'Minimum fee rate (sat/vB)'**
  String get settingsMinFeeRate;

  /// No description provided for @fiatSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Fiat Values'**
  String get fiatSectionTitle;

  /// No description provided for @fiatEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Show fiat values'**
  String get fiatEnabledLabel;

  /// No description provided for @fiatCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get fiatCurrencyLabel;

  /// No description provided for @fiatProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Price provider'**
  String get fiatProviderLabel;

  /// No description provided for @fiatProviderCoinGecko.
  ///
  /// In en, this message translates to:
  /// **'CoinGecko'**
  String get fiatProviderCoinGecko;

  /// No description provided for @fiatProviderMempoolSpace.
  ///
  /// In en, this message translates to:
  /// **'Mempool.space'**
  String get fiatProviderMempoolSpace;

  /// No description provided for @explorerSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Block Explorer'**
  String get explorerSectionTitle;

  /// No description provided for @explorerUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://mempool.space'**
  String get explorerUrlHint;

  /// No description provided for @explorerNetworkMainnet.
  ///
  /// In en, this message translates to:
  /// **'Mainnet Explorer'**
  String get explorerNetworkMainnet;

  /// No description provided for @explorerNetworkTestnet.
  ///
  /// In en, this message translates to:
  /// **'Testnet Explorer'**
  String get explorerNetworkTestnet;

  /// No description provided for @explorerNetworkTestnet4.
  ///
  /// In en, this message translates to:
  /// **'Testnet4 Explorer'**
  String get explorerNetworkTestnet4;

  /// No description provided for @explorerNetworkSignet.
  ///
  /// In en, this message translates to:
  /// **'Signet Explorer'**
  String get explorerNetworkSignet;

  /// No description provided for @explorerNetworkRegtest.
  ///
  /// In en, this message translates to:
  /// **'Regtest Explorer'**
  String get explorerNetworkRegtest;

  /// No description provided for @openInExplorer.
  ///
  /// In en, this message translates to:
  /// **'Open in explorer'**
  String get openInExplorer;

  /// No description provided for @txLabelTitle.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get txLabelTitle;

  /// No description provided for @txDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Transaction details'**
  String get txDetailsTitle;

  /// No description provided for @txDetailsNet.
  ///
  /// In en, this message translates to:
  /// **'Net amount'**
  String get txDetailsNet;

  /// No description provided for @txDetailsGrossReceived.
  ///
  /// In en, this message translates to:
  /// **'Received (gross)'**
  String get txDetailsGrossReceived;

  /// No description provided for @txDetailsGrossSent.
  ///
  /// In en, this message translates to:
  /// **'Sent (gross)'**
  String get txDetailsGrossSent;

  /// No description provided for @txDetailsBlockHeight.
  ///
  /// In en, this message translates to:
  /// **'Block height'**
  String get txDetailsBlockHeight;

  /// No description provided for @txDetailsConfirmedAt.
  ///
  /// In en, this message translates to:
  /// **'Confirmed at'**
  String get txDetailsConfirmedAt;

  /// No description provided for @txDetailsFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get txDetailsFee;

  /// No description provided for @addressesSection.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get addressesSection;

  /// No description provided for @receiveAddresses.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receiveAddresses;

  /// No description provided for @changeAddresses.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeAddresses;

  /// No description provided for @noAddresses.
  ///
  /// In en, this message translates to:
  /// **'No addresses yet. Sync to discover addresses.'**
  String get noAddresses;

  /// No description provided for @addressIndex.
  ///
  /// In en, this message translates to:
  /// **'#{index}'**
  String addressIndex(int index);

  /// No description provided for @addressLabelTitle.
  ///
  /// In en, this message translates to:
  /// **'Address label'**
  String get addressLabelTitle;

  /// No description provided for @addressLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Add a label...'**
  String get addressLabelHint;

  /// No description provided for @addressLabelRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove label'**
  String get addressLabelRemove;

  /// No description provided for @addressDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Address details'**
  String get addressDetailsTitle;

  /// No description provided for @addressBalanceSats.
  ///
  /// In en, this message translates to:
  /// **'{sats} sats'**
  String addressBalanceSats(int sats);

  /// No description provided for @revealMoreAddresses.
  ///
  /// In en, this message translates to:
  /// **'Reveal 20 more addresses'**
  String get revealMoreAddresses;

  /// No description provided for @addressTxCount.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions'**
  String addressTxCount(int count);

  /// No description provided for @coinsSection.
  ///
  /// In en, this message translates to:
  /// **'Coins'**
  String get coinsSection;

  /// No description provided for @noCoins.
  ///
  /// In en, this message translates to:
  /// **'No coins. Sync to discover UTXOs.'**
  String get noCoins;

  /// No description provided for @coinDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Coin details'**
  String get coinDetailsTitle;

  /// No description provided for @coinLabelTitle.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get coinLabelTitle;

  /// No description provided for @coinOutpoint.
  ///
  /// In en, this message translates to:
  /// **'Outpoint'**
  String get coinOutpoint;

  /// No description provided for @coinValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get coinValue;

  /// No description provided for @coinAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get coinAddress;

  /// No description provided for @coinKeychain.
  ///
  /// In en, this message translates to:
  /// **'Keychain'**
  String get coinKeychain;

  /// No description provided for @coinKeychainReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get coinKeychainReceive;

  /// No description provided for @coinKeychainChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get coinKeychainChange;

  /// No description provided for @coinAgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get coinAgeLabel;

  /// No description provided for @coinBlockNumber.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get coinBlockNumber;

  /// No description provided for @coinConfirmations.
  ///
  /// In en, this message translates to:
  /// **'Confirmations'**
  String get coinConfirmations;

  /// No description provided for @coinTotalCount.
  ///
  /// In en, this message translates to:
  /// **'{count} coins'**
  String coinTotalCount(int count);

  /// No description provided for @coinTotalValue.
  ///
  /// In en, this message translates to:
  /// **'Total: {sats} sats'**
  String coinTotalValue(int sats);

  /// No description provided for @spendPathsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Spend paths'**
  String get spendPathsAvailable;

  /// No description provided for @spendPathUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get spendPathUnlocked;

  /// No description provided for @spendPathLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get spendPathLocked;

  /// No description provided for @spendPathBlocks.
  ///
  /// In en, this message translates to:
  /// **'{blocks} blocks'**
  String spendPathBlocks(int blocks);

  /// No description provided for @spendPathUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Unconfirmed'**
  String get spendPathUnconfirmed;

  /// No description provided for @spendPathNeedsSync.
  ///
  /// In en, this message translates to:
  /// **'Sync required'**
  String get spendPathNeedsSync;

  /// No description provided for @psbtStatusUnsigned.
  ///
  /// In en, this message translates to:
  /// **'UNSIGNED'**
  String get psbtStatusUnsigned;

  /// No description provided for @psbtStatusPartial.
  ///
  /// In en, this message translates to:
  /// **'PARTIAL'**
  String get psbtStatusPartial;

  /// No description provided for @psbtStatusSigned.
  ///
  /// In en, this message translates to:
  /// **'SIGNED'**
  String get psbtStatusSigned;

  /// No description provided for @psbtStatusSpent.
  ///
  /// In en, this message translates to:
  /// **'SPENT'**
  String get psbtStatusSpent;

  /// No description provided for @psbtSpentInputsWarning.
  ///
  /// In en, this message translates to:
  /// **'One or more inputs have been confirmed spent by another transaction. This PSBT can no longer be broadcast.'**
  String get psbtSpentInputsWarning;

  /// No description provided for @createTxTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Transaction'**
  String get createTxTitle;

  /// No description provided for @createTxRecipientHint.
  ///
  /// In en, this message translates to:
  /// **'bc1q...'**
  String get createTxRecipientHint;

  /// No description provided for @createTxAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount (sats)'**
  String get createTxAmount;

  /// No description provided for @createTxFeeRate.
  ///
  /// In en, this message translates to:
  /// **'Fee rate (sat/vB)'**
  String get createTxFeeRate;

  /// No description provided for @createTxSpendPath.
  ///
  /// In en, this message translates to:
  /// **'Spend path'**
  String get createTxSpendPath;

  /// No description provided for @createTxSpendPathHint.
  ///
  /// In en, this message translates to:
  /// **'Select a spend path'**
  String get createTxSpendPathHint;

  /// No description provided for @createTxSelectedCoins.
  ///
  /// In en, this message translates to:
  /// **'{count} coin(s) selected — {sats} sats'**
  String createTxSelectedCoins(int count, int sats);

  /// No description provided for @createTxButton.
  ///
  /// In en, this message translates to:
  /// **'Create PSBT'**
  String get createTxButton;

  /// No description provided for @createTxAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Amount is required'**
  String get createTxAmountRequired;

  /// No description provided for @createTxAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid amount'**
  String get createTxAmountInvalid;

  /// No description provided for @createTxMaxButton.
  ///
  /// In en, this message translates to:
  /// **'MAX'**
  String get createTxMaxButton;

  /// No description provided for @createTxMyWalletsButton.
  ///
  /// In en, this message translates to:
  /// **'MY WALLETS'**
  String get createTxMyWalletsButton;

  /// No description provided for @createTxSelectDestWallet.
  ///
  /// In en, this message translates to:
  /// **'Select destination wallet'**
  String get createTxSelectDestWallet;

  /// No description provided for @createTxThisWallet.
  ///
  /// In en, this message translates to:
  /// **'This wallet (Self)'**
  String get createTxThisWallet;

  /// No description provided for @createTxNoUnusedAddress.
  ///
  /// In en, this message translates to:
  /// **'No unused receive address available'**
  String get createTxNoUnusedAddress;

  /// No description provided for @createTxNoSpendPaths.
  ///
  /// In en, this message translates to:
  /// **'No spend paths available. Sync the wallet first.'**
  String get createTxNoSpendPaths;

  /// No description provided for @psbtDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsigned Transaction'**
  String get psbtDetailTitle;

  /// No description provided for @psbtRecipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get psbtRecipient;

  /// No description provided for @psbtAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get psbtAmount;

  /// No description provided for @psbtFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get psbtFee;

  /// No description provided for @psbtCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get psbtCreatedAt;

  /// No description provided for @psbtTimelockLabel.
  ///
  /// In en, this message translates to:
  /// **'Timelock'**
  String get psbtTimelockLabel;

  /// No description provided for @psbtTimelockSyncRequired.
  ///
  /// In en, this message translates to:
  /// **'Sync required to check status'**
  String get psbtTimelockSyncRequired;

  /// No description provided for @psbtTimelockBlocksRemaining.
  ///
  /// In en, this message translates to:
  /// **'{blocks} blocks remaining (~{duration})'**
  String psbtTimelockBlocksRemaining(int blocks, String duration);

  /// No description provided for @psbtTimelockTimeRemaining.
  ///
  /// In en, this message translates to:
  /// **'~{duration} remaining'**
  String psbtTimelockTimeRemaining(String duration);

  /// No description provided for @psbtSignaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Signatures ({done}/{threshold} of {total})'**
  String psbtSignaturesTitle(int done, int threshold, int total);

  /// No description provided for @psbtSignerSigned.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get psbtSignerSigned;

  /// No description provided for @psbtSignerMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get psbtSignerMissing;

  /// No description provided for @psbtSignerOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get psbtSignerOptional;

  /// No description provided for @psbtSignerUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get psbtSignerUnknown;

  /// No description provided for @psbtExportButton.
  ///
  /// In en, this message translates to:
  /// **'Export PSBT'**
  String get psbtExportButton;

  /// No description provided for @psbtImportSignedButton.
  ///
  /// In en, this message translates to:
  /// **'Import signature'**
  String get psbtImportSignedButton;

  /// No description provided for @psbtBroadcastButton.
  ///
  /// In en, this message translates to:
  /// **'Broadcast'**
  String get psbtBroadcastButton;

  /// No description provided for @psbtBroadcastSuccess.
  ///
  /// In en, this message translates to:
  /// **'Transaction broadcast! TXID: {txid}'**
  String psbtBroadcastSuccess(String txid);

  /// No description provided for @psbtAutoBroadcastSwitch.
  ///
  /// In en, this message translates to:
  /// **'Broadcast automatically when unlocked'**
  String get psbtAutoBroadcastSwitch;

  /// No description provided for @psbtAutoBroadcastHint.
  ///
  /// In en, this message translates to:
  /// **'The wallet must stay unlocked. Broadcast will be attempted after every sync once the timelock matures.'**
  String get psbtAutoBroadcastHint;

  /// No description provided for @psbtAutoBroadcastQueuedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Queued for automatic broadcast'**
  String get psbtAutoBroadcastQueuedTooltip;

  /// No description provided for @psbtAutoBroadcastedToast.
  ///
  /// In en, this message translates to:
  /// **'Auto-broadcasted: {txid}'**
  String psbtAutoBroadcastedToast(String txid);

  /// No description provided for @psbtAutoBroadcastFailedToast.
  ///
  /// In en, this message translates to:
  /// **'Auto-broadcast failed for PSBT {id}: {error}'**
  String psbtAutoBroadcastFailedToast(int id, String error);

  /// No description provided for @psbtDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete PSBT'**
  String get psbtDeleteTitle;

  /// No description provided for @psbtDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this unsigned transaction?'**
  String get psbtDeleteConfirm;

  /// No description provided for @coinSelectDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get coinSelectDone;

  /// No description provided for @createTxTotalFee.
  ///
  /// In en, this message translates to:
  /// **'Fee (sats)'**
  String get createTxTotalFee;

  /// No description provided for @createTxEstChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get createTxEstChange;

  /// No description provided for @createTxEstInsufficientFunds.
  ///
  /// In en, this message translates to:
  /// **'Insufficient funds'**
  String get createTxEstInsufficientFunds;

  /// No description provided for @createTxAddRecipient.
  ///
  /// In en, this message translates to:
  /// **'Add recipient'**
  String get createTxAddRecipient;

  /// No description provided for @createTxMoreOutputTypes.
  ///
  /// In en, this message translates to:
  /// **'More output types'**
  String get createTxMoreOutputTypes;

  /// No description provided for @opReturnAddOutput.
  ///
  /// In en, this message translates to:
  /// **'Add OP_RETURN data'**
  String get opReturnAddOutput;

  /// No description provided for @opReturnInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Embedded data'**
  String get opReturnInputLabel;

  /// No description provided for @opReturnHexToggle.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get opReturnHexToggle;

  /// No description provided for @opReturnUtf8Toggle.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get opReturnUtf8Toggle;

  /// No description provided for @opReturnSizeWarning.
  ///
  /// In en, this message translates to:
  /// **'Outputs over 80 bytes may not be relayed by all nodes'**
  String get opReturnSizeWarning;

  /// No description provided for @opReturnRecipientLabel.
  ///
  /// In en, this message translates to:
  /// **'OP_RETURN data'**
  String get opReturnRecipientLabel;

  /// No description provided for @opReturnCannotBeMaxRecipient.
  ///
  /// In en, this message translates to:
  /// **'OP_RETURN cannot receive remaining funds'**
  String get opReturnCannotBeMaxRecipient;

  /// No description provided for @opReturnSingleLimit.
  ///
  /// In en, this message translates to:
  /// **'Only one OP_RETURN output allowed'**
  String get opReturnSingleLimit;

  /// No description provided for @opReturnInvalidHex.
  ///
  /// In en, this message translates to:
  /// **'Invalid hex'**
  String get opReturnInvalidHex;

  /// No description provided for @opReturnEmptyError.
  ///
  /// In en, this message translates to:
  /// **'OP_RETURN data is empty'**
  String get opReturnEmptyError;

  /// No description provided for @opReturnByteCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 byte} other{{count} bytes}}'**
  String opReturnByteCount(int count);

  /// No description provided for @opReturnCopyAsText.
  ///
  /// In en, this message translates to:
  /// **'Copy as text'**
  String get opReturnCopyAsText;

  /// No description provided for @opReturnCopyAsHex.
  ///
  /// In en, this message translates to:
  /// **'Copy as hex'**
  String get opReturnCopyAsHex;

  /// No description provided for @createTxTotalOut.
  ///
  /// In en, this message translates to:
  /// **'Total out'**
  String get createTxTotalOut;

  /// No description provided for @createTxSelectCoinsFirst.
  ///
  /// In en, this message translates to:
  /// **'Select coins to build a transaction'**
  String get createTxSelectCoinsFirst;

  /// No description provided for @walletSendButton.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get walletSendButton;

  /// No description provided for @coinSelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Select coins'**
  String get coinSelectorTitle;

  /// No description provided for @coinSelectorSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get coinSelectorSearchHint;

  /// No description provided for @coinSelectorNoCoinsSelected.
  ///
  /// In en, this message translates to:
  /// **'Tap to select coins...'**
  String get coinSelectorNoCoinsSelected;

  /// No description provided for @coinSelectorDoneCount.
  ///
  /// In en, this message translates to:
  /// **'Done ({count})'**
  String coinSelectorDoneCount(int count);

  /// No description provided for @relatedCoins.
  ///
  /// In en, this message translates to:
  /// **'Related coins'**
  String get relatedCoins;

  /// No description provided for @relatedAddresses.
  ///
  /// In en, this message translates to:
  /// **'Output addresses'**
  String get relatedAddresses;

  /// No description provided for @inputAddresses.
  ///
  /// In en, this message translates to:
  /// **'Input addresses'**
  String get inputAddresses;

  /// No description provided for @relatedTransactions.
  ///
  /// In en, this message translates to:
  /// **'Related transactions'**
  String get relatedTransactions;

  /// No description provided for @exportBip329Button.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportBip329Button;

  /// No description provided for @importBip329Button.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importBip329Button;

  /// No description provided for @exportBip329Empty.
  ///
  /// In en, this message translates to:
  /// **'No explicit labels to export'**
  String get exportBip329Empty;

  /// No description provided for @exportBip329Copied.
  ///
  /// In en, this message translates to:
  /// **'Labels copied'**
  String get exportBip329Copied;

  /// No description provided for @importBip329Success.
  ///
  /// In en, this message translates to:
  /// **'Labels imported'**
  String get importBip329Success;

  /// No description provided for @exportDescriptorFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Export format'**
  String get exportDescriptorFormatTitle;

  /// No description provided for @exportDescriptorStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get exportDescriptorStandard;

  /// No description provided for @exportDescriptorStandardDesc.
  ///
  /// In en, this message translates to:
  /// **'Compatible with Nunchuk and most wallets'**
  String get exportDescriptorStandardDesc;

  /// No description provided for @exportDescriptorLiana.
  ///
  /// In en, this message translates to:
  /// **'Liana'**
  String get exportDescriptorLiana;

  /// No description provided for @exportDescriptorLianaDesc.
  ///
  /// In en, this message translates to:
  /// **'Adds [00000000] to the unspendable key'**
  String get exportDescriptorLianaDesc;

  /// No description provided for @exportLabelsOption.
  ///
  /// In en, this message translates to:
  /// **'Labels (BIP-329)'**
  String get exportLabelsOption;

  /// No description provided for @importPsbtOption.
  ///
  /// In en, this message translates to:
  /// **'PSBT'**
  String get importPsbtOption;

  /// No description provided for @importPsbtMerged.
  ///
  /// In en, this message translates to:
  /// **'Signatures merged'**
  String get importPsbtMerged;

  /// No description provided for @importPsbtSaved.
  ///
  /// In en, this message translates to:
  /// **'PSBT imported'**
  String get importPsbtSaved;

  /// No description provided for @coinPendingSpend.
  ///
  /// In en, this message translates to:
  /// **'PSBT'**
  String get coinPendingSpend;

  /// No description provided for @coinMempoolSpend.
  ///
  /// In en, this message translates to:
  /// **'Spending'**
  String get coinMempoolSpend;

  /// No description provided for @coinPendingPsbtsSection.
  ///
  /// In en, this message translates to:
  /// **'Pending transactions'**
  String get coinPendingPsbtsSection;

  /// No description provided for @overviewTab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overviewTab;

  /// No description provided for @walletReceiveButton.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get walletReceiveButton;

  /// No description provided for @noUnusedReceiveAddress.
  ///
  /// In en, this message translates to:
  /// **'No unused receive address found. Try syncing first.'**
  String get noUnusedReceiveAddress;

  /// No description provided for @receiveNextAddress.
  ///
  /// In en, this message translates to:
  /// **'Next address'**
  String get receiveNextAddress;

  /// No description provided for @rbfWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Full-RBF replacement'**
  String get rbfWarningTitle;

  /// No description provided for @rbfOriginalFee.
  ///
  /// In en, this message translates to:
  /// **'Original fee'**
  String get rbfOriginalFee;

  /// No description provided for @rbfDescendants.
  ///
  /// In en, this message translates to:
  /// **'Descendants'**
  String get rbfDescendants;

  /// No description provided for @rbfMinFee.
  ///
  /// In en, this message translates to:
  /// **'Minimum fee'**
  String get rbfMinFee;

  /// No description provided for @rbfMinRate.
  ///
  /// In en, this message translates to:
  /// **'Minimum rate'**
  String get rbfMinRate;

  /// No description provided for @rbfUnknownFee.
  ///
  /// In en, this message translates to:
  /// **'Spending a mempool UTXO — use a higher fee rate than the original tx.'**
  String get rbfUnknownFee;

  /// No description provided for @rbfFeeTooLow.
  ///
  /// In en, this message translates to:
  /// **'Fee rate too low for RBF — minimum is {rate} sat/vB'**
  String rbfFeeTooLow(double rate);

  /// No description provided for @rbfAbsFeeTooLow.
  ///
  /// In en, this message translates to:
  /// **'Total fee too low for RBF — minimum is {fee} sats'**
  String rbfAbsFeeTooLow(int fee);

  /// No description provided for @cpfpBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'CPFP acceleration'**
  String get cpfpBannerTitle;

  /// No description provided for @cpfpParentFee.
  ///
  /// In en, this message translates to:
  /// **'Ancestor fees'**
  String get cpfpParentFee;

  /// No description provided for @cpfpAncestorCount.
  ///
  /// In en, this message translates to:
  /// **'Ancestor txs'**
  String get cpfpAncestorCount;

  /// No description provided for @cpfpEffectiveRate.
  ///
  /// In en, this message translates to:
  /// **'Package fee rate'**
  String get cpfpEffectiveRate;

  /// No description provided for @cpfpAccelerate.
  ///
  /// In en, this message translates to:
  /// **'Accelerate'**
  String get cpfpAccelerate;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsSectionDefaults.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get settingsSectionDefaults;

  /// No description provided for @settingsSectionTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get settingsSectionTransactions;

  /// No description provided for @settingsSectionConnectivity.
  ///
  /// In en, this message translates to:
  /// **'Connectivity'**
  String get settingsSectionConnectivity;

  /// No description provided for @torLabel.
  ///
  /// In en, this message translates to:
  /// **'Use Tor'**
  String get torLabel;

  /// No description provided for @torSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Route all traffic through Tor'**
  String get torSubtitle;

  /// No description provided for @torStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Tor connecting...'**
  String get torStatusConnecting;

  /// No description provided for @torStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Tor active'**
  String get torStatusConnected;

  /// No description provided for @disclaimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Beta Software — Use at Your Own Risk'**
  String get disclaimerTitle;

  /// No description provided for @disclaimerBody.
  ///
  /// In en, this message translates to:
  /// **'Deadbolt is under active development and may contain bugs or errors.\n\nIt is not yet suitable for use with real funds. Use at your own risk.'**
  String get disclaimerBody;

  /// No description provided for @disclaimerDontShow7Days.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show for 7 days'**
  String get disclaimerDontShow7Days;

  /// No description provided for @electrumPrivacyWarning.
  ///
  /// In en, this message translates to:
  /// **'Using a public Electrum server. Your IP and transaction history may be visible to third parties. Configure a personal server in Settings.'**
  String get electrumPrivacyWarning;

  /// No description provided for @goToSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get goToSettings;

  /// No description provided for @wifExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export private key (WIF)'**
  String get wifExportTitle;

  /// No description provided for @wifExportWarning.
  ///
  /// In en, this message translates to:
  /// **'This exports the private key of a single address, but if your wallet\'\'s XPUB is known to anyone — a coordinator, exchange, or any service you\'\'ve shared it with — they can use this WIF to derive the private keys of every address in your wallet.\n\nOnly proceed if your XPUB is private, or if you fully accept this risk.'**
  String get wifExportWarning;

  /// No description provided for @wifExportTypeToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type to confirm:'**
  String get wifExportTypeToConfirm;

  /// No description provided for @wifExportConfirmPhrase.
  ///
  /// In en, this message translates to:
  /// **'my full wallet is at risk'**
  String get wifExportConfirmPhrase;

  /// No description provided for @wifExportShowButton.
  ///
  /// In en, this message translates to:
  /// **'Show WIF'**
  String get wifExportShowButton;

  /// No description provided for @wifDisplayWarning.
  ///
  /// In en, this message translates to:
  /// **'Never share this key. If your XPUB is known to others, this WIF exposes your entire wallet.'**
  String get wifDisplayWarning;

  /// No description provided for @protectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Protection'**
  String get protectionLabel;

  /// No description provided for @protectionNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get protectionNone;

  /// No description provided for @protectionPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get protectionPassword;

  /// No description provided for @protectionXpub.
  ///
  /// In en, this message translates to:
  /// **'XPub'**
  String get protectionXpub;

  /// No description provided for @protectionUnprotected.
  ///
  /// In en, this message translates to:
  /// **'Unprotected'**
  String get protectionUnprotected;

  /// No description provided for @protectionXpubInfo.
  ///
  /// In en, this message translates to:
  /// **'Any xpub from the wallet can unlock it. Do not share those xpubs with third parties.'**
  String get protectionXpubInfo;

  /// No description provided for @securityLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Anti-brute-force level'**
  String get securityLevelLabel;

  /// No description provided for @securityLevelStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get securityLevelStandard;

  /// No description provided for @securityLevelHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get securityLevelHigh;

  /// No description provided for @securityLevelExtreme.
  ///
  /// In en, this message translates to:
  /// **'Extreme'**
  String get securityLevelExtreme;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPasswordLabel;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @backupPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPasswordLabel;

  /// No description provided for @validatorPasswordEmpty.
  ///
  /// In en, this message translates to:
  /// **'Password cannot be empty'**
  String get validatorPasswordEmpty;

  /// No description provided for @validatorPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password required'**
  String get validatorPasswordRequired;

  /// No description provided for @validatorPasswordsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get validatorPasswordsNoMatch;

  /// No description provided for @validatorNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get validatorNameRequired;

  /// No description provided for @changeButton.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeButton;

  /// No description provided for @exportButton.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportButton;

  /// No description provided for @backButton.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backButton;

  /// No description provided for @feeRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Fee rate'**
  String get feeRateLabel;

  /// No description provided for @verifyOnDeviceButton.
  ///
  /// In en, this message translates to:
  /// **'Verify on device'**
  String get verifyOnDeviceButton;

  /// No description provided for @protectionChangedToast.
  ///
  /// In en, this message translates to:
  /// **'Protection changed to {protection}'**
  String protectionChangedToast(String protection);

  /// No description provided for @exportBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get exportBackupTitle;

  /// No description provided for @sweepWifTitle.
  ///
  /// In en, this message translates to:
  /// **'Sweep WIF key'**
  String get sweepWifTitle;

  /// No description provided for @sweepWifPrivateKeySection.
  ///
  /// In en, this message translates to:
  /// **'Private key (WIF)'**
  String get sweepWifPrivateKeySection;

  /// No description provided for @sweepWifHint.
  ///
  /// In en, this message translates to:
  /// **'Paste or scan WIF key...'**
  String get sweepWifHint;

  /// No description provided for @sweepWifSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get sweepWifSearching;

  /// No description provided for @sweepWifFindUtxos.
  ///
  /// In en, this message translates to:
  /// **'Find UTXOs'**
  String get sweepWifFindUtxos;

  /// No description provided for @sweepWifControlledAddresses.
  ///
  /// In en, this message translates to:
  /// **'Controlled addresses'**
  String get sweepWifControlledAddresses;

  /// No description provided for @sweepWifTotal.
  ///
  /// In en, this message translates to:
  /// **'Total: {amount} sat'**
  String sweepWifTotal(int amount);

  /// No description provided for @sweepWifNoFunds.
  ///
  /// In en, this message translates to:
  /// **'No funds found for this key on the current network.'**
  String get sweepWifNoFunds;

  /// No description provided for @sweepWifDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get sweepWifDestination;

  /// No description provided for @sweepWifAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin address...'**
  String get sweepWifAddressHint;

  /// No description provided for @sweepWifSweeping.
  ///
  /// In en, this message translates to:
  /// **'Sweeping...'**
  String get sweepWifSweeping;

  /// No description provided for @sweepWifButton.
  ///
  /// In en, this message translates to:
  /// **'Sweep {amount} sat'**
  String sweepWifButton(int amount);

  /// No description provided for @sweepWifEnterKeyFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter a WIF key first'**
  String get sweepWifEnterKeyFirst;

  /// No description provided for @sweepWifFillFields.
  ///
  /// In en, this message translates to:
  /// **'Fill all fields with valid values'**
  String get sweepWifFillFields;

  /// No description provided for @sweepWifSweptToast.
  ///
  /// In en, this message translates to:
  /// **'Swept: {txid}'**
  String sweepWifSweptToast(String txid);

  /// No description provided for @sweepWifEmpty.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get sweepWifEmpty;

  /// No description provided for @walletCreateGuided.
  ///
  /// In en, this message translates to:
  /// **'Guided creation'**
  String get walletCreateGuided;

  /// No description provided for @walletCreateGuidedSub.
  ///
  /// In en, this message translates to:
  /// **'Standard wallet from your keys'**
  String get walletCreateGuidedSub;

  /// No description provided for @walletCreateFromDescriptor.
  ///
  /// In en, this message translates to:
  /// **'From descriptor'**
  String get walletCreateFromDescriptor;

  /// No description provided for @walletCreateFromDescriptorSub.
  ///
  /// In en, this message translates to:
  /// **'Enter a Bitcoin descriptor directly'**
  String get walletCreateFromDescriptorSub;

  /// No description provided for @walletCreateFromProject.
  ///
  /// In en, this message translates to:
  /// **'From project'**
  String get walletCreateFromProject;

  /// No description provided for @walletCreateFromProjectSub.
  ///
  /// In en, this message translates to:
  /// **'Use a descriptor from the designer'**
  String get walletCreateFromProjectSub;

  /// No description provided for @walletCreateFromBackup.
  ///
  /// In en, this message translates to:
  /// **'From backup'**
  String get walletCreateFromBackup;

  /// No description provided for @walletCreateFromBackupSub.
  ///
  /// In en, this message translates to:
  /// **'Restore a wallet from a .deadbolt or .bed file'**
  String get walletCreateFromBackupSub;

  /// No description provided for @projectCreateFromScratch.
  ///
  /// In en, this message translates to:
  /// **'From scratch'**
  String get projectCreateFromScratch;

  /// No description provided for @projectCreateFromScratchSub.
  ///
  /// In en, this message translates to:
  /// **'Pick network and wallet type, then add keys'**
  String get projectCreateFromScratchSub;

  /// No description provided for @projectCreateFromDescriptorSub.
  ///
  /// In en, this message translates to:
  /// **'Paste, scan or import a Bitcoin descriptor'**
  String get projectCreateFromDescriptorSub;

  /// No description provided for @projectCreateImport.
  ///
  /// In en, this message translates to:
  /// **'Import project'**
  String get projectCreateImport;

  /// No description provided for @projectCreateImportSub.
  ///
  /// In en, this message translates to:
  /// **'Restore a project from a .json export'**
  String get projectCreateImportSub;

  /// No description provided for @newWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'New Wallet'**
  String get newWalletTitle;

  /// No description provided for @walletExportLabel.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletExportLabel;

  /// No description provided for @bedExportOption.
  ///
  /// In en, this message translates to:
  /// **'BED backup'**
  String get bedExportOption;

  /// No description provided for @bedExportColocationWarning.
  ///
  /// In en, this message translates to:
  /// **'Decryptable with any xpub in this wallet — never store it next to one.'**
  String get bedExportColocationWarning;

  /// No description provided for @bedExportWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you export'**
  String get bedExportWarningTitle;

  /// No description provided for @bedExportWarningContinue.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get bedExportWarningContinue;

  /// No description provided for @walletTypeSinglesig.
  ///
  /// In en, this message translates to:
  /// **'Singlesig'**
  String get walletTypeSinglesig;

  /// No description provided for @walletTypeMultisig.
  ///
  /// In en, this message translates to:
  /// **'Multisig'**
  String get walletTypeMultisig;

  /// No description provided for @walletTypeSinglesigDesc.
  ///
  /// In en, this message translates to:
  /// **'One key controls the wallet. Simpler and faster to set up.'**
  String get walletTypeSinglesigDesc;

  /// No description provided for @walletTypeMultisigDesc.
  ///
  /// In en, this message translates to:
  /// **'Multiple keys required to sign. Ideal for shared control or extra security.'**
  String get walletTypeMultisigDesc;

  /// No description provided for @walletTypeInheritance.
  ///
  /// In en, this message translates to:
  /// **'Inheritance'**
  String get walletTypeInheritance;

  /// No description provided for @walletTypeInheritanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Multi-path wallet: you control funds now, heirs can access after a set time delay.'**
  String get walletTypeInheritanceDesc;

  /// No description provided for @ownerKeysSection.
  ///
  /// In en, this message translates to:
  /// **'Your keys'**
  String get ownerKeysSection;

  /// No description provided for @heirsSection.
  ///
  /// In en, this message translates to:
  /// **'Heirs'**
  String get heirsSection;

  /// No description provided for @addHeir.
  ///
  /// In en, this message translates to:
  /// **'Add heir'**
  String get addHeir;

  /// No description provided for @editHeir.
  ///
  /// In en, this message translates to:
  /// **'Edit heir'**
  String get editHeir;

  /// No description provided for @heirName.
  ///
  /// In en, this message translates to:
  /// **'Heir name'**
  String get heirName;

  /// No description provided for @heirNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Alice, Family, Lawyer'**
  String get heirNameHint;

  /// No description provided for @heirKey.
  ///
  /// In en, this message translates to:
  /// **'Heir\'s key'**
  String get heirKey;

  /// No description provided for @heirTimelockLabel.
  ///
  /// In en, this message translates to:
  /// **'Can access after'**
  String get heirTimelockLabel;

  /// No description provided for @inheritanceSixMonths.
  ///
  /// In en, this message translates to:
  /// **'6 months (~26,280 blocks)'**
  String get inheritanceSixMonths;

  /// No description provided for @inheritanceOneYear.
  ///
  /// In en, this message translates to:
  /// **'1 year (~52,560 blocks)'**
  String get inheritanceOneYear;

  /// No description provided for @inheritanceThreeMonthsShort.
  ///
  /// In en, this message translates to:
  /// **'3 mo'**
  String get inheritanceThreeMonthsShort;

  /// No description provided for @inheritanceSixMonthsShort.
  ///
  /// In en, this message translates to:
  /// **'6 mo'**
  String get inheritanceSixMonthsShort;

  /// No description provided for @inheritanceNineMonthsShort.
  ///
  /// In en, this message translates to:
  /// **'9 mo'**
  String get inheritanceNineMonthsShort;

  /// No description provided for @inheritanceOneYearShort.
  ///
  /// In en, this message translates to:
  /// **'1 yr'**
  String get inheritanceOneYearShort;

  /// No description provided for @inheritanceThreeMonths.
  ///
  /// In en, this message translates to:
  /// **'3 months (~13,140 blocks)'**
  String get inheritanceThreeMonths;

  /// No description provided for @inheritanceNineMonths.
  ///
  /// In en, this message translates to:
  /// **'9 months (~39,420 blocks)'**
  String get inheritanceNineMonths;

  /// No description provided for @inheritanceDuplicateTimelockTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate timelocks'**
  String get inheritanceDuplicateTimelockTitle;

  /// No description provided for @inheritanceDuplicateTimelockBody.
  ///
  /// In en, this message translates to:
  /// **'Two or more heirs share the same timelock. For better compatibility with other coordination software, each spending path should have a unique timelock.'**
  String get inheritanceDuplicateTimelockBody;

  /// No description provided for @inheritanceDuplicateTimelockFix.
  ///
  /// In en, this message translates to:
  /// **'Fix automatically'**
  String get inheritanceDuplicateTimelockFix;

  /// No description provided for @inheritanceDuplicateTimelockContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway'**
  String get inheritanceDuplicateTimelockContinue;

  /// No description provided for @inheritanceNeedHeir.
  ///
  /// In en, this message translates to:
  /// **'Add at least one heir'**
  String get inheritanceNeedHeir;

  /// No description provided for @inheritanceOwnerPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Main'**
  String get inheritanceOwnerPathLabel;

  /// No description provided for @inheritanceMinTimelockLabel.
  ///
  /// In en, this message translates to:
  /// **'Inheritance timelock threshold'**
  String get inheritanceMinTimelockLabel;

  /// No description provided for @inheritanceMinTimelockInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Inheritance detection'**
  String get inheritanceMinTimelockInfoTitle;

  /// No description provided for @inheritanceMinTimelockInfo.
  ///
  /// In en, this message translates to:
  /// **'Some Taproot descriptors use spend paths with short timelocks (e.g. 1–2 blocks) to model multiple signing combinations for the same owner — these are not inheritance paths. This threshold is the minimum number of blocks a relative timelock must have before a spend path is treated as an inheritance path and the status panel is shown.\n\nDefault: 144 blocks (~1 day).'**
  String get inheritanceMinTimelockInfo;

  /// No description provided for @inheritanceStatus.
  ///
  /// In en, this message translates to:
  /// **'Inheritance'**
  String get inheritanceStatus;

  /// No description provided for @inheritanceSafe.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get inheritanceSafe;

  /// No description provided for @inheritanceApproaching.
  ///
  /// In en, this message translates to:
  /// **'Heir access approaching'**
  String get inheritanceApproaching;

  /// No description provided for @inheritanceUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Heir can access funds'**
  String get inheritanceUnlocked;

  /// No description provided for @inheritanceNeedsSync.
  ///
  /// In en, this message translates to:
  /// **'Sync to check heir access'**
  String get inheritanceNeedsSync;

  /// No description provided for @inheritanceNoFunds.
  ///
  /// In en, this message translates to:
  /// **'No confirmed funds'**
  String get inheritanceNoFunds;

  /// No description provided for @revaultNow.
  ///
  /// In en, this message translates to:
  /// **'Re-vault'**
  String get revaultNow;

  /// No description provided for @blocksUnit.
  ///
  /// In en, this message translates to:
  /// **'blocks'**
  String get blocksUnit;

  /// No description provided for @inheritanceHeirN.
  ///
  /// In en, this message translates to:
  /// **'Heir {n}'**
  String inheritanceHeirN(int n);

  /// No description provided for @scriptTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Script type'**
  String get scriptTypeLabel;

  /// No description provided for @scriptTypeLegacy.
  ///
  /// In en, this message translates to:
  /// **'Legacy'**
  String get scriptTypeLegacy;

  /// No description provided for @scriptTypeNested.
  ///
  /// In en, this message translates to:
  /// **'Nested'**
  String get scriptTypeNested;

  /// No description provided for @scriptTypeSegwit.
  ///
  /// In en, this message translates to:
  /// **'SegWit'**
  String get scriptTypeSegwit;

  /// No description provided for @scriptTypeTaproot.
  ///
  /// In en, this message translates to:
  /// **'Taproot'**
  String get scriptTypeTaproot;

  /// No description provided for @scriptDescP2pkh.
  ///
  /// In en, this message translates to:
  /// **'P2PKH — Oldest standard. Highest fees.'**
  String get scriptDescP2pkh;

  /// No description provided for @scriptDescP2sh.
  ///
  /// In en, this message translates to:
  /// **'P2SH — Oldest multisig standard. Highest fees.'**
  String get scriptDescP2sh;

  /// No description provided for @scriptDescP2shWpkh.
  ///
  /// In en, this message translates to:
  /// **'P2SH-P2WPKH — SegWit wrapped for backward compatibility. Rarely needed today.'**
  String get scriptDescP2shWpkh;

  /// No description provided for @scriptDescP2shWsh.
  ///
  /// In en, this message translates to:
  /// **'P2SH-P2WSH — SegWit multisig with backward compatibility. Rarely needed today.'**
  String get scriptDescP2shWsh;

  /// No description provided for @scriptDescP2wpkh.
  ///
  /// In en, this message translates to:
  /// **'P2WPKH — Most common modern standard. Lower fees.'**
  String get scriptDescP2wpkh;

  /// No description provided for @scriptDescP2wsh.
  ///
  /// In en, this message translates to:
  /// **'P2WSH — Native SegWit multisig. Lower fees, widely supported.'**
  String get scriptDescP2wsh;

  /// No description provided for @scriptDescP2trSinglesig.
  ///
  /// In en, this message translates to:
  /// **'P2TR — Taproot. Best privacy and lowest fees.'**
  String get scriptDescP2trSinglesig;

  /// No description provided for @scriptDescP2trMultisig.
  ///
  /// In en, this message translates to:
  /// **'P2TR — Taproot multisig. Best privacy. Requires compatible wallets.'**
  String get scriptDescP2trMultisig;

  /// No description provided for @requiredSignatures.
  ///
  /// In en, this message translates to:
  /// **'Required signatures: {m} of {n}'**
  String requiredSignatures(int m, int n);

  /// No description provided for @decreaseThresholdTooltip.
  ///
  /// In en, this message translates to:
  /// **'Decrease threshold'**
  String get decreaseThresholdTooltip;

  /// No description provided for @increaseThresholdTooltip.
  ///
  /// In en, this message translates to:
  /// **'Increase threshold'**
  String get increaseThresholdTooltip;

  /// No description provided for @keyDetailsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Key details'**
  String get keyDetailsTooltip;

  /// No description provided for @creatingWalletLabel.
  ///
  /// In en, this message translates to:
  /// **'Creating wallet…'**
  String get creatingWalletLabel;

  /// No description provided for @addAtLeastOneKey.
  ///
  /// In en, this message translates to:
  /// **'Add at least one key'**
  String get addAtLeastOneKey;

  /// No description provided for @multisigNeedsMinKeys.
  ///
  /// In en, this message translates to:
  /// **'Multi key wallets need at least 2 keys'**
  String get multisigNeedsMinKeys;

  /// No description provided for @hwWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallet'**
  String get hwWalletTitle;

  /// No description provided for @hwWalletScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning for devices…'**
  String get hwWalletScanning;

  /// No description provided for @hwWalletConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get hwWalletConnecting;

  /// No description provided for @hwWalletUnlockDevice.
  ///
  /// In en, this message translates to:
  /// **'Unlock your device…'**
  String get hwWalletUnlockDevice;

  /// No description provided for @hwWalletNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No hardware wallet detected.\nMake sure it is plugged in.'**
  String get hwWalletNoDevices;

  /// No description provided for @hwWalletSelectDevice.
  ///
  /// In en, this message translates to:
  /// **'Select a device'**
  String get hwWalletSelectDevice;

  /// No description provided for @hwWalletScanDevices.
  ///
  /// In en, this message translates to:
  /// **'Scan for devices'**
  String get hwWalletScanDevices;

  /// No description provided for @hwWalletPairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get hwWalletPairingCode;

  /// No description provided for @hwCompareCodeOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Compare this code with your device screen and confirm:'**
  String get hwCompareCodeOnDevice;

  /// No description provided for @hwSignTransactionButton.
  ///
  /// In en, this message translates to:
  /// **'Sign transaction'**
  String get hwSignTransactionButton;

  /// No description provided for @hwWalletNoConfirmNeeded.
  ///
  /// In en, this message translates to:
  /// **'No confirmation needed on the device for key export.'**
  String get hwWalletNoConfirmNeeded;

  /// No description provided for @hwRegisterWallet.
  ///
  /// In en, this message translates to:
  /// **'Register wallet'**
  String get hwRegisterWallet;

  /// No description provided for @hwRegisterWalletSub.
  ///
  /// In en, this message translates to:
  /// **'Register this policy on the device'**
  String get hwRegisterWalletSub;

  /// No description provided for @hwNotRequired.
  ///
  /// In en, this message translates to:
  /// **'Not required for single-key wallets'**
  String get hwNotRequired;

  /// No description provided for @hwCheckRegistration.
  ///
  /// In en, this message translates to:
  /// **'Check registration'**
  String get hwCheckRegistration;

  /// No description provided for @hwCheckRegistrationSub.
  ///
  /// In en, this message translates to:
  /// **'Verify if this policy is registered'**
  String get hwCheckRegistrationSub;

  /// No description provided for @hwWalletRegistered.
  ///
  /// In en, this message translates to:
  /// **'Wallet registered on device.'**
  String get hwWalletRegistered;

  /// No description provided for @hwWalletIsRegistered.
  ///
  /// In en, this message translates to:
  /// **'Wallet is registered on this device.'**
  String get hwWalletIsRegistered;

  /// No description provided for @hwWalletNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Wallet is NOT registered on this device.'**
  String get hwWalletNotRegistered;

  /// No description provided for @hwNoDevice.
  ///
  /// In en, this message translates to:
  /// **'No device connected'**
  String get hwNoDevice;

  /// No description provided for @hwScanButton.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get hwScanButton;

  /// No description provided for @hwDisconnectButton.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get hwDisconnectButton;

  /// No description provided for @hwSelectDevice.
  ///
  /// In en, this message translates to:
  /// **'Select a device:'**
  String get hwSelectDevice;

  /// No description provided for @hwPairingCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare with device screen and confirm:'**
  String get hwPairingCompare;

  /// No description provided for @directSendConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm send'**
  String get directSendConfirmTitle;

  /// No description provided for @directSendConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Sign and broadcast'**
  String get directSendConfirmAction;

  /// No description provided for @directSendSuccess.
  ///
  /// In en, this message translates to:
  /// **'Sent: {txid}'**
  String directSendSuccess(String txid);

  /// No description provided for @accountIndexLabel.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountIndexLabel;

  /// No description provided for @scanAccountsAction.
  ///
  /// In en, this message translates to:
  /// **'Scan accounts'**
  String get scanAccountsAction;

  /// No description provided for @scanAccountsScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning accounts…'**
  String get scanAccountsScanning;

  /// No description provided for @scanAccountsScanningHint.
  ///
  /// In en, this message translates to:
  /// **'Checking addresses on Electrum…\n(accounts gap: {accountGap}, addresses gap: {addrGap})'**
  String scanAccountsScanningHint(int accountGap, int addrGap);

  /// No description provided for @accountGapLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Account gap limit'**
  String get accountGapLimitLabel;

  /// No description provided for @addressGapLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Address gap limit'**
  String get addressGapLimitLabel;

  /// No description provided for @scanNonStandardPathsLabel.
  ///
  /// In en, this message translates to:
  /// **'Non-standard derivation paths'**
  String get scanNonStandardPathsLabel;

  /// No description provided for @scanNonStandardPathsHint.
  ///
  /// In en, this message translates to:
  /// **'Also scan alternative BIP purpose paths for each script type (44/49/84/86)'**
  String get scanNonStandardPathsHint;

  /// No description provided for @scanAccountsNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No accounts with prior activity found.'**
  String get scanAccountsNoActivity;

  /// No description provided for @scanAccountsScannedCount.
  ///
  /// In en, this message translates to:
  /// **'Scanned {count} accounts'**
  String scanAccountsScannedCount(int count);

  /// No description provided for @scanAccountsFoundBackups.
  ///
  /// In en, this message translates to:
  /// **'{count} account(s) found'**
  String scanAccountsFoundBackups(int count);

  /// No description provided for @scanAccountsNoActivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recover accounts from a mnemonic phrase'**
  String get scanAccountsNoActivitySubtitle;

  /// No description provided for @hwDiscoveryNoDevice.
  ///
  /// In en, this message translates to:
  /// **'No hardware wallet connected. Connect and pair your device first.'**
  String get hwDiscoveryNoDevice;

  /// No description provided for @hwDiscoveryStart.
  ///
  /// In en, this message translates to:
  /// **'Scan accounts'**
  String get hwDiscoveryStart;

  /// No description provided for @hwDiscoveryDeriving.
  ///
  /// In en, this message translates to:
  /// **'Exporting xpubs… ({n}/{total})'**
  String hwDiscoveryDeriving(int n, int total);

  /// No description provided for @scanAccountsCreateWallet.
  ///
  /// In en, this message translates to:
  /// **'Create wallet'**
  String get scanAccountsCreateWallet;

  /// No description provided for @scanAccountsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get scanAccountsRetry;

  /// No description provided for @walletNotFound.
  ///
  /// In en, this message translates to:
  /// **'Wallet not found on device'**
  String get walletNotFound;

  /// No description provided for @searchNostrLabel.
  ///
  /// In en, this message translates to:
  /// **'Search Nostr backups'**
  String get searchNostrLabel;

  /// No description provided for @searchNostrHint.
  ///
  /// In en, this message translates to:
  /// **'Look for descriptor backups on configured relays'**
  String get searchNostrHint;

  /// No description provided for @hwSkipLegacyLabel.
  ///
  /// In en, this message translates to:
  /// **'Skip legacy (P2PKH) derivations'**
  String get hwSkipLegacyLabel;

  /// No description provided for @hwSkipLegacyHint.
  ///
  /// In en, this message translates to:
  /// **'Avoids device confirmation prompts for m/44’ paths'**
  String get hwSkipLegacyHint;

  /// No description provided for @searchNostrScanningHint.
  ///
  /// In en, this message translates to:
  /// **'Also searching Nostr relays for descriptor backups…'**
  String get searchNostrScanningHint;

  /// No description provided for @onChainScanningHint.
  ///
  /// In en, this message translates to:
  /// **'Also searching for on-chain descriptor backups…'**
  String get onChainScanningHint;

  /// No description provided for @importFromNostrBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from Nostr'**
  String get importFromNostrBackup;

  /// No description provided for @nostrImportTamperTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify after import'**
  String get nostrImportTamperTitle;

  /// No description provided for @nostrImportTamperBody.
  ///
  /// In en, this message translates to:
  /// **'Anyone who knows the xpub can modify this backup. After importing, confirm the descriptor and receiving addresses match your expected wallet before sending any funds.'**
  String get nostrImportTamperBody;

  /// No description provided for @scanTypeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get scanTypeAll;

  /// No description provided for @bip39PassphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'BIP39 passphrase (optional)'**
  String get bip39PassphraseLabel;

  /// No description provided for @pressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackAgainToExit;

  /// No description provided for @feeHistogramTitle.
  ///
  /// In en, this message translates to:
  /// **'Next block fees'**
  String get feeHistogramTitle;

  /// No description provided for @feeHistogramNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get feeHistogramNext;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @scanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get scanAgain;

  /// No description provided for @signButton.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get signButton;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @addPrivateKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Add private key'**
  String get addPrivateKeyLabel;

  /// No description provided for @addSigningKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Add signing key'**
  String get addSigningKeyLabel;

  /// No description provided for @addPrivateKeyMatchedKey.
  ///
  /// In en, this message translates to:
  /// **'Will be attached to: {label}'**
  String addPrivateKeyMatchedKey(String label);

  /// No description provided for @addPrivateKeyAlreadyHot.
  ///
  /// In en, this message translates to:
  /// **'{label} already has a private key stored'**
  String addPrivateKeyAlreadyHot(String label);

  /// No description provided for @addPrivateKeyNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint {mfp} does not belong to any key in this wallet'**
  String addPrivateKeyNoMatch(String mfp);

  /// No description provided for @attachPrivateKeyConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This seed matches the existing key \"{label}\". Attach it as a private key?'**
  String attachPrivateKeyConfirmMessage(String label);

  /// No description provided for @attachPrivateKeyConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attachPrivateKeyConfirmAction;

  /// No description provided for @editKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit key'**
  String get editKeyTitle;

  /// No description provided for @validating.
  ///
  /// In en, this message translates to:
  /// **'Validating...'**
  String get validating;

  /// No description provided for @registeredKeys.
  ///
  /// In en, this message translates to:
  /// **'Registered keys'**
  String get registeredKeys;

  /// No description provided for @showRegisteredKeys.
  ///
  /// In en, this message translates to:
  /// **'Show registered keys'**
  String get showRegisteredKeys;

  /// No description provided for @enterXpubToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Enter xpub to unlock'**
  String get enterXpubToUnlock;

  /// No description provided for @xpubUnlockHint.
  ///
  /// In en, this message translates to:
  /// **'Paste any xpub registered for this wallet. Keyspec format ([mfp/path]xpub) is also accepted.'**
  String get xpubUnlockHint;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @invalidXpubOrKeyspec.
  ///
  /// In en, this message translates to:
  /// **'Invalid xpub or keyspec'**
  String get invalidXpubOrKeyspec;

  /// No description provided for @signWithHwWallet.
  ///
  /// In en, this message translates to:
  /// **'Sign with hardware wallet'**
  String get signWithHwWallet;

  /// No description provided for @enterWalletPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter wallet password'**
  String get enterWalletPassword;

  /// No description provided for @walletPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This wallet is protected with a password.'**
  String get walletPasswordSubtitle;

  /// No description provided for @enterBackupPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter backup password'**
  String get enterBackupPassword;

  /// No description provided for @backupPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This backup is password-protected.'**
  String get backupPasswordSubtitle;

  /// No description provided for @wifPrivateKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'WIF private key'**
  String get wifPrivateKeyLabel;

  /// No description provided for @verifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyButton;

  /// No description provided for @derivPathWithoutLeading.
  ///
  /// In en, this message translates to:
  /// **'Without leading m/'**
  String get derivPathWithoutLeading;

  /// No description provided for @nostrRelaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Nostr Relays'**
  String get nostrRelaysLabel;

  /// No description provided for @nostrRelaysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Relays for encrypted descriptor backups'**
  String get nostrRelaysSubtitle;

  /// No description provided for @nostrRelayAddHint.
  ///
  /// In en, this message translates to:
  /// **'wss://relay.example.com'**
  String get nostrRelayAddHint;

  /// No description provided for @nostrRelayInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'URL must start with wss:// or ws://'**
  String get nostrRelayInvalidUrl;

  /// No description provided for @nostrRelayDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Relay already in list'**
  String get nostrRelayDuplicate;

  /// No description provided for @nostrRelayTimeoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Timeout (seconds)'**
  String get nostrRelayTimeoutLabel;

  /// No description provided for @nostrRelayMaxAttemptsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attempts per relay'**
  String get nostrRelayMaxAttemptsLabel;

  /// No description provided for @nostrSearchNetworkWarning.
  ///
  /// In en, this message translates to:
  /// **'Connection issues with some Nostr relays. Some backups may not have been found.'**
  String get nostrSearchNetworkWarning;

  /// No description provided for @publishBackupMenu.
  ///
  /// In en, this message translates to:
  /// **'Publish Descriptor'**
  String get publishBackupMenu;

  /// No description provided for @publishBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Publish Backup'**
  String get publishBackupTitle;

  /// No description provided for @publishBackupSinglesigTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup not recommended'**
  String get publishBackupSinglesigTitle;

  /// No description provided for @publishBackupSinglesigBody.
  ///
  /// In en, this message translates to:
  /// **'This is a singlesig wallet. Its descriptor can be fully recovered from the seed (or xpub) via standard wallet discovery — no external backup is needed. Publishing it to Nostr or on-chain only adds a privacy risk by linking your xpub to extra public data.'**
  String get publishBackupSinglesigBody;

  /// No description provided for @publishBackupSinglesigContinue.
  ///
  /// In en, this message translates to:
  /// **'I understand, show options anyway'**
  String get publishBackupSinglesigContinue;

  /// No description provided for @backupSinglesigShortNote.
  ///
  /// In en, this message translates to:
  /// **'Not recommended for singlesig: descriptor is recoverable from the seed via discovery. Publishing it only adds privacy risk.'**
  String get backupSinglesigShortNote;

  /// No description provided for @nostrBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Nostr Backup'**
  String get nostrBackupTitle;

  /// No description provided for @nostrBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted descriptor backup on Nostr relays'**
  String get nostrBackupSubtitle;

  /// No description provided for @nostrBackupPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish Backup'**
  String get nostrBackupPublish;

  /// No description provided for @nostrBackupRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh Status'**
  String get nostrBackupRefresh;

  /// No description provided for @nostrBackupPublished.
  ///
  /// In en, this message translates to:
  /// **'Backup published'**
  String get nostrBackupPublished;

  /// No description provided for @nostrBackupSecurityNote.
  ///
  /// In en, this message translates to:
  /// **'Anyone with your xpub can locate and decrypt this backup. Only share xpubs with trusted co-signers.'**
  String get nostrBackupSecurityNote;

  /// No description provided for @nostrBackupFound.
  ///
  /// In en, this message translates to:
  /// **'Backup found'**
  String get nostrBackupFound;

  /// No description provided for @nostrBackupNotFound.
  ///
  /// In en, this message translates to:
  /// **'No backup found'**
  String get nostrBackupNotFound;

  /// No description provided for @nostrBackupPartialCosigners.
  ///
  /// In en, this message translates to:
  /// **'{backedUp}/{total} cosigners backed up'**
  String nostrBackupPartialCosigners(int backedUp, int total);

  /// No description provided for @nostrBackupNoRelays.
  ///
  /// In en, this message translates to:
  /// **'No relays configured. Add relays in Settings → Nostr Relays.'**
  String get nostrBackupNoRelays;

  /// No description provided for @nostrBackupChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get nostrBackupChecking;

  /// No description provided for @nostrBackupPublishing.
  ///
  /// In en, this message translates to:
  /// **'Publishing…'**
  String get nostrBackupPublishing;

  /// No description provided for @nostrBackupDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Backup'**
  String get nostrBackupDelete;

  /// No description provided for @nostrBackupDeleted.
  ///
  /// In en, this message translates to:
  /// **'Backup deleted from relay'**
  String get nostrBackupDeleted;

  /// No description provided for @nostrBackupDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace the backup on this relay with an empty event? The descriptor will no longer be recoverable from this relay.'**
  String get nostrBackupDeleteConfirm;

  /// No description provided for @nostrRestoreXpubHint.
  ///
  /// In en, this message translates to:
  /// **'xpub6... or [mfp/path]xpub...'**
  String get nostrRestoreXpubHint;

  /// No description provided for @nostrRestoreFound.
  ///
  /// In en, this message translates to:
  /// **'Backup found'**
  String get nostrRestoreFound;

  /// No description provided for @nostrRestoreImport.
  ///
  /// In en, this message translates to:
  /// **'Import Wallet'**
  String get nostrRestoreImport;

  /// No description provided for @recoverWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'Recover Wallet'**
  String get recoverWalletTitle;

  /// No description provided for @restoreTabXpub.
  ///
  /// In en, this message translates to:
  /// **'xpub'**
  String get restoreTabXpub;

  /// No description provided for @restoreTabSeed.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get restoreTabSeed;

  /// No description provided for @restoreTabHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get restoreTabHardware;

  /// No description provided for @restoreXpubEnterXpub.
  ///
  /// In en, this message translates to:
  /// **'Enter an extended public key to scan on-chain accounts and search Nostr backups.'**
  String get restoreXpubEnterXpub;

  /// No description provided for @restoreXpubScanButton.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get restoreXpubScanButton;

  /// No description provided for @restoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get restoreDefaults;

  /// No description provided for @coinSortLabelSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get coinSortLabelSize;

  /// No description provided for @coinSortLabelAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get coinSortLabelAge;

  /// No description provided for @coinSortSizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Size: largest first'**
  String get coinSortSizeDesc;

  /// No description provided for @coinSortSizeAsc.
  ///
  /// In en, this message translates to:
  /// **'Size: smallest first'**
  String get coinSortSizeAsc;

  /// No description provided for @coinSortAgeDesc.
  ///
  /// In en, this message translates to:
  /// **'Age: oldest first'**
  String get coinSortAgeDesc;

  /// No description provided for @coinSortAgeAsc.
  ///
  /// In en, this message translates to:
  /// **'Age: newest first'**
  String get coinSortAgeAsc;

  /// No description provided for @reorderWallets.
  ///
  /// In en, this message translates to:
  /// **'Reorder wallets'**
  String get reorderWallets;

  /// No description provided for @reorderProjects.
  ///
  /// In en, this message translates to:
  /// **'Reorder projects'**
  String get reorderProjects;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @descriptorSigsTitle.
  ///
  /// In en, this message translates to:
  /// **'Descriptor Signatures'**
  String get descriptorSigsTitle;

  /// No description provided for @descriptorSigsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prove ownership of each key by signing the descriptor hash. Protects backups from tampering.'**
  String get descriptorSigsSubtitle;

  /// No description provided for @descriptorSigsSigned.
  ///
  /// In en, this message translates to:
  /// **'Signed · {date}'**
  String descriptorSigsSigned(String date);

  /// No description provided for @descriptorSigsNotSigned.
  ///
  /// In en, this message translates to:
  /// **'Not signed'**
  String get descriptorSigsNotSigned;

  /// No description provided for @descriptorSigsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid signature'**
  String get descriptorSigsInvalid;

  /// No description provided for @descriptorSigsSignAction.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get descriptorSigsSignAction;

  /// No description provided for @descriptorSigsDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete signature'**
  String get descriptorSigsDeleteAction;

  /// No description provided for @descriptorSigsMethodHotKey.
  ///
  /// In en, this message translates to:
  /// **'HotKey (automatic)'**
  String get descriptorSigsMethodHotKey;

  /// No description provided for @descriptorSigsMethodBB02.
  ///
  /// In en, this message translates to:
  /// **'BitBox02'**
  String get descriptorSigsMethodBB02;

  /// No description provided for @descriptorSigsMethodQRMessage.
  ///
  /// In en, this message translates to:
  /// **'QR — Message signing'**
  String get descriptorSigsMethodQRMessage;

  /// No description provided for @descriptorSigsMethodQRBip322.
  ///
  /// In en, this message translates to:
  /// **'QR — BIP322 PSBT'**
  String get descriptorSigsMethodQRBip322;

  /// No description provided for @descriptorSigsVerifyAll.
  ///
  /// In en, this message translates to:
  /// **'Verify all'**
  String get descriptorSigsVerifyAll;

  /// No description provided for @descriptorSigsConnectHw.
  ///
  /// In en, this message translates to:
  /// **'Connect hardware wallet'**
  String get descriptorSigsConnectHw;

  /// No description provided for @descriptorSigsSummary.
  ///
  /// In en, this message translates to:
  /// **'{signed}/{total} keys signed'**
  String descriptorSigsSummary(int signed, int total);

  /// No description provided for @descriptorSigsMessage.
  ///
  /// In en, this message translates to:
  /// **'Message to sign'**
  String get descriptorSigsMessage;

  /// No description provided for @descriptorSigsQRMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Base64 compact signature (65 bytes)'**
  String get descriptorSigsQRMessageHint;

  /// No description provided for @descriptorSigsQRBip322Hint.
  ///
  /// In en, this message translates to:
  /// **'Signed PSBT (base64 or scan QR)'**
  String get descriptorSigsQRBip322Hint;

  /// No description provided for @descriptorSigsSignSuccess.
  ///
  /// In en, this message translates to:
  /// **'Signature stored'**
  String get descriptorSigsSignSuccess;

  /// No description provided for @descriptorSigsChooseMethod.
  ///
  /// In en, this message translates to:
  /// **'Choose signing method'**
  String get descriptorSigsChooseMethod;

  /// No description provided for @descriptorSigsVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified · {date}'**
  String descriptorSigsVerified(String date);

  /// No description provided for @descriptorSigsVerifyResult.
  ///
  /// In en, this message translates to:
  /// **'{valid} of {total} signatures valid'**
  String descriptorSigsVerifyResult(int valid, int total);

  /// No description provided for @deriveKeyFirst.
  ///
  /// In en, this message translates to:
  /// **'Derive the key first'**
  String get deriveKeyFirst;

  /// No description provided for @invalidDerivedKeyspec.
  ///
  /// In en, this message translates to:
  /// **'Invalid derived keyspec'**
  String get invalidDerivedKeyspec;

  /// No description provided for @enterValidSeedPhrase.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid seed phrase first'**
  String get enterValidSeedPhrase;

  /// No description provided for @enterXprvKey.
  ///
  /// In en, this message translates to:
  /// **'Enter an xprv key'**
  String get enterXprvKey;

  /// No description provided for @signingKeyAdded.
  ///
  /// In en, this message translates to:
  /// **'Signing key added ({mfp})'**
  String signingKeyAdded(String mfp);

  /// No description provided for @hwDeviceNotRegisteredForWallet.
  ///
  /// In en, this message translates to:
  /// **'This device ({mfp}) is not registered for this wallet.'**
  String hwDeviceNotRegisteredForWallet(String mfp);

  /// No description provided for @mfpMismatch.
  ///
  /// In en, this message translates to:
  /// **'MFP mismatch: got {mfp}, expected {expected}'**
  String mfpMismatch(String mfp, String expected);

  /// No description provided for @wrongKeyMfp.
  ///
  /// In en, this message translates to:
  /// **'Wrong key. Got {mfp}, expected {expected}'**
  String wrongKeyMfp(String mfp, String expected);

  /// No description provided for @derivedKeyspecLabel.
  ///
  /// In en, this message translates to:
  /// **'Derived keyspec'**
  String get derivedKeyspecLabel;

  /// No description provided for @onChainBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'On-chain'**
  String get onChainBackupTitle;

  /// No description provided for @onChainBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Descriptor backup embedded in a Bitcoin transaction'**
  String get onChainBackupSubtitle;

  /// No description provided for @onChainBackupSecurityNote.
  ///
  /// In en, this message translates to:
  /// **'Descriptor backed up on-chain. Recoverable from any cosigner\'s xpub.'**
  String get onChainBackupSecurityNote;

  /// No description provided for @onChainBackupAnchors.
  ///
  /// In en, this message translates to:
  /// **'Anchors: {count} × {amount} sats'**
  String onChainBackupAnchors(int count, int amount);

  /// No description provided for @onChainBackupScanning.
  ///
  /// In en, this message translates to:
  /// **'Preparing backup…'**
  String get onChainBackupScanning;

  /// No description provided for @noUtxosAvailable.
  ///
  /// In en, this message translates to:
  /// **'No UTXOs available'**
  String get noUtxosAvailable;

  /// No description provided for @onChainBackupFeeRate.
  ///
  /// In en, this message translates to:
  /// **'Fee rate (sats/vB)'**
  String get onChainBackupFeeRate;

  /// No description provided for @onChainBackupTxFees.
  ///
  /// In en, this message translates to:
  /// **'Fee: {total} sats · {vb} vB'**
  String onChainBackupTxFees(int total, int vb);

  /// No description provided for @onChainBackupChange.
  ///
  /// In en, this message translates to:
  /// **'Change: {sats} sats'**
  String onChainBackupChange(Object sats);

  /// No description provided for @onChainBackupVault.
  ///
  /// In en, this message translates to:
  /// **'Vault: {sats} sats'**
  String onChainBackupVault(Object sats);

  /// No description provided for @onChainBackupUtxoInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Select a coin with at least {sats} sats'**
  String onChainBackupUtxoInsufficient(int sats);

  /// No description provided for @onChainBackupConfirmBuild.
  ///
  /// In en, this message translates to:
  /// **'Build TX_COMMIT'**
  String get onChainBackupConfirmBuild;

  /// No description provided for @onChainBackupTimelockedUtxo.
  ///
  /// In en, this message translates to:
  /// **'Some selected UTXOs are still timelocked and cannot be spent yet.'**
  String get onChainBackupTimelockedUtxo;

  /// No description provided for @onChainBackupSignWithHotKey.
  ///
  /// In en, this message translates to:
  /// **'Sign with hot key'**
  String get onChainBackupSignWithHotKey;

  /// No description provided for @onChainBackupPublishing.
  ///
  /// In en, this message translates to:
  /// **'Signing…'**
  String get onChainBackupPublishing;

  /// No description provided for @onChainBackupChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get onChainBackupChecking;

  /// No description provided for @onChainBackupExists.
  ///
  /// In en, this message translates to:
  /// **'Backup already exists'**
  String get onChainBackupExists;

  /// No description provided for @onChainBackupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Descriptor backed up on-chain'**
  String get onChainBackupSuccess;

  /// No description provided for @onChainBackupCommitTx.
  ///
  /// In en, this message translates to:
  /// **'TX_COMMIT'**
  String get onChainBackupCommitTx;

  /// No description provided for @onChainBackupRevealTx.
  ///
  /// In en, this message translates to:
  /// **'TX_REVEAL'**
  String get onChainBackupRevealTx;

  /// No description provided for @onChainBackupSignCommitHint.
  ///
  /// In en, this message translates to:
  /// **'Sign the commit transaction with your hardware wallet or QR device, then import the signed PSBT.'**
  String get onChainBackupSignCommitHint;

  /// No description provided for @onChainBackupBuildingPsbt.
  ///
  /// In en, this message translates to:
  /// **'Building PSBT…'**
  String get onChainBackupBuildingPsbt;

  /// No description provided for @onChainBackupFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing…'**
  String get onChainBackupFinalizing;

  /// No description provided for @onChainBackupExportPsbt.
  ///
  /// In en, this message translates to:
  /// **'Export PSBT'**
  String get onChainBackupExportPsbt;

  /// No description provided for @onChainBackupImportSigned.
  ///
  /// In en, this message translates to:
  /// **'Import signed'**
  String get onChainBackupImportSigned;

  /// No description provided for @onChainBackupSignWithHw.
  ///
  /// In en, this message translates to:
  /// **'Sign with HW'**
  String get onChainBackupSignWithHw;

  /// No description provided for @onChainBackupConfirmBroadcastTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm broadcast'**
  String get onChainBackupConfirmBroadcastTitle;

  /// No description provided for @onChainBackupCommitFee.
  ///
  /// In en, this message translates to:
  /// **'Fee: {sats} sats'**
  String onChainBackupCommitFee(String sats);

  /// No description provided for @onChainBackupRevealFee.
  ///
  /// In en, this message translates to:
  /// **'Fee: {sats} sats'**
  String onChainBackupRevealFee(String sats);

  /// No description provided for @onChainBackupRevealChange.
  ///
  /// In en, this message translates to:
  /// **'Change: {sats} sats'**
  String onChainBackupRevealChange(Object sats);

  /// No description provided for @onChainBackupBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Broadcast'**
  String get onChainBackupBroadcast;

  /// No description provided for @onChainBackupAnchorsHealth.
  ///
  /// In en, this message translates to:
  /// **'{reachable} of {total} anchors accessible'**
  String onChainBackupAnchorsHealth(int reachable, int total);

  /// No description provided for @onChainBackupDescriptorVerified.
  ///
  /// In en, this message translates to:
  /// **'Descriptor verified'**
  String get onChainBackupDescriptorVerified;

  /// No description provided for @onChainBackupRevealPending.
  ///
  /// In en, this message translates to:
  /// **'TX_REVEAL not yet published'**
  String get onChainBackupRevealPending;

  /// No description provided for @onChainBackupCreateNew.
  ///
  /// In en, this message translates to:
  /// **'Create new backup'**
  String get onChainBackupCreateNew;

  /// No description provided for @onChainSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search on-chain backups'**
  String get onChainSearchLabel;

  /// No description provided for @onChainSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Scan Signet for descriptor backups published on-chain'**
  String get onChainSearchHint;

  /// No description provided for @onChainBadge.
  ///
  /// In en, this message translates to:
  /// **'On-chain'**
  String get onChainBadge;

  /// No description provided for @generateMnemonicStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generateMnemonicStep1Title;

  /// No description provided for @generateMnemonicStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Verify backup'**
  String get generateMnemonicStep2Title;

  /// No description provided for @generateMnemonicStep3Title.
  ///
  /// In en, this message translates to:
  /// **'Configure key'**
  String get generateMnemonicStep3Title;

  /// No description provided for @generateMnemonicLengthLabel.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get generateMnemonicLengthLabel;

  /// No description provided for @generateMnemonicLength12.
  ///
  /// In en, this message translates to:
  /// **'12 words'**
  String get generateMnemonicLength12;

  /// No description provided for @generateMnemonicLength24.
  ///
  /// In en, this message translates to:
  /// **'24 words'**
  String get generateMnemonicLength24;

  /// No description provided for @generateMnemonicGenerateButton.
  ///
  /// In en, this message translates to:
  /// **'Generate mnemonic'**
  String get generateMnemonicGenerateButton;

  /// No description provided for @generateMnemonicRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get generateMnemonicRegenerate;

  /// No description provided for @generateMnemonicWarning.
  ///
  /// In en, this message translates to:
  /// **'Write these words down on paper, in order. They will not be shown again. Anyone with access to them can spend your bitcoin.'**
  String get generateMnemonicWarning;

  /// No description provided for @generateMnemonicBackupDone.
  ///
  /// In en, this message translates to:
  /// **'I have written them down'**
  String get generateMnemonicBackupDone;

  /// No description provided for @generateMnemonicVerifyIntro.
  ///
  /// In en, this message translates to:
  /// **'Type each word in the position requested. All positions must match before you can continue.'**
  String get generateMnemonicVerifyIntro;

  /// No description provided for @generateMnemonicVerifyWordLabel.
  ///
  /// In en, this message translates to:
  /// **'Word #{pos}'**
  String generateMnemonicVerifyWordLabel(int pos);

  /// No description provided for @generateMnemonicVerifyError.
  ///
  /// In en, this message translates to:
  /// **'Some words do not match. Check your notes and try again.'**
  String get generateMnemonicVerifyError;

  /// No description provided for @generateMnemonicShuffleAgain.
  ///
  /// In en, this message translates to:
  /// **'Shuffle order again'**
  String get generateMnemonicShuffleAgain;

  /// No description provided for @generateMnemonicContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get generateMnemonicContinue;

  /// No description provided for @generateMnemonicDone.
  ///
  /// In en, this message translates to:
  /// **'Add key'**
  String get generateMnemonicDone;

  /// No description provided for @addKeyCapacityWatchOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch-only key'**
  String get addKeyCapacityWatchOnlyTitle;

  /// No description provided for @addKeyCapacityWatchOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'An xpub you can monitor but not sign with.'**
  String get addKeyCapacityWatchOnlySubtitle;

  /// No description provided for @addKeyCapacityHotTitle.
  ///
  /// In en, this message translates to:
  /// **'Hot key'**
  String get addKeyCapacityHotTitle;

  /// No description provided for @addKeyCapacityHotSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Holds the seed on this device so it can sign.'**
  String get addKeyCapacityHotSubtitle;

  /// No description provided for @addKeyWatchSourcePasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter manually'**
  String get addKeyWatchSourcePasteTitle;

  /// No description provided for @addKeyWatchSourcePasteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From clipboard or typed in.'**
  String get addKeyWatchSourcePasteSubtitle;

  /// No description provided for @addKeyManualDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter key'**
  String get addKeyManualDialogTitle;

  /// No description provided for @addKeyManualHint.
  ///
  /// In en, this message translates to:
  /// **'[mfp/path]xpub\n\nor one line per field:\nmfp\nm/path\nxpub'**
  String get addKeyManualHint;

  /// No description provided for @addKeyManualFormatError.
  ///
  /// In en, this message translates to:
  /// **'Format not recognized. Paste a [mfp/path]xpub keyspec or three lines (mfp, path, xpub).'**
  String get addKeyManualFormatError;

  /// No description provided for @addKeyWatchSourceScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get addKeyWatchSourceScanTitle;

  /// No description provided for @addKeyWatchSourceScanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read a keyspec QR code with the camera.'**
  String get addKeyWatchSourceScanSubtitle;

  /// No description provided for @addKeyWatchSourceFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Load file'**
  String get addKeyWatchSourceFileTitle;

  /// No description provided for @addKeyWatchSourceFileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open a text/JSON file with the keyspec.'**
  String get addKeyWatchSourceFileSubtitle;

  /// No description provided for @addKeyWatchSourceHwTitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallet'**
  String get addKeyWatchSourceHwTitle;

  /// No description provided for @addKeyWatchSourceHwSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export xpub from a BitBox02 or compatible device.'**
  String get addKeyWatchSourceHwSubtitle;

  /// No description provided for @addKeyHotSourceGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate new mnemonic'**
  String get addKeyHotSourceGenerateTitle;

  /// No description provided for @addKeyHotSourceGenerateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a fresh seed and verify the backup.'**
  String get addKeyHotSourceGenerateSubtitle;

  /// No description provided for @addKeyHotSourceExistingTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter existing mnemonic'**
  String get addKeyHotSourceExistingTitle;

  /// No description provided for @addKeyHotSourceExistingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type or scan a 12/24-word seed.'**
  String get addKeyHotSourceExistingSubtitle;

  /// No description provided for @addKeyHotSourceXprvTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter xprv'**
  String get addKeyHotSourceXprvTitle;

  /// No description provided for @addKeyHotSourceXprvSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Paste a master xprv (depth 0).'**
  String get addKeyHotSourceXprvSubtitle;

  /// No description provided for @txPlanningTitle.
  ///
  /// In en, this message translates to:
  /// **'Migrate UTXOs'**
  String get txPlanningTitle;

  /// No description provided for @txPlanningMenuEntry.
  ///
  /// In en, this message translates to:
  /// **'Migrate UTXOs…'**
  String get txPlanningMenuEntry;

  /// No description provided for @txPlanningIdleDescription.
  ///
  /// In en, this message translates to:
  /// **'Move every confirmed UTXO to fresh addresses spaced over time. Each transaction gets its own random feerate and nLockTime so auto-broadcast emits them as their timelock matures.'**
  String get txPlanningIdleDescription;

  /// No description provided for @txPlanningComputeButton.
  ///
  /// In en, this message translates to:
  /// **'Compute plan'**
  String get txPlanningComputeButton;

  /// No description provided for @txPlanningLastPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Last plan: {status}'**
  String txPlanningLastPlanTitle(String status);

  /// No description provided for @txPlanningLastPlanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Plan #{id}, {kind}'**
  String txPlanningLastPlanSubtitle(int id, String kind);

  /// No description provided for @txPlanningWalletNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Wallet not loaded'**
  String get txPlanningWalletNotLoaded;

  /// No description provided for @txPlanningNoConfirmedUtxos.
  ///
  /// In en, this message translates to:
  /// **'No confirmed UTXOs to plan'**
  String get txPlanningNoConfirmedUtxos;

  /// No description provided for @txPlanningTooFewAddresses.
  ///
  /// In en, this message translates to:
  /// **'Wallet has too few revealed addresses ({needed} needed). Generate more on the Receive screen first.'**
  String txPlanningTooFewAddresses(int needed);

  /// No description provided for @txPlanningInvalidFeeRate.
  ///
  /// In en, this message translates to:
  /// **'Invalid fee rate'**
  String get txPlanningInvalidFeeRate;

  /// No description provided for @txPlanningFeeRateOrder.
  ///
  /// In en, this message translates to:
  /// **'Min fee must be ≤ max fee'**
  String get txPlanningFeeRateOrder;

  /// No description provided for @txPlanningInvalidDelay.
  ///
  /// In en, this message translates to:
  /// **'Invalid spacing'**
  String get txPlanningInvalidDelay;

  /// No description provided for @txPlanningDelayOrder.
  ///
  /// In en, this message translates to:
  /// **'Min spacing must be ≤ max spacing'**
  String get txPlanningDelayOrder;

  /// No description provided for @txPlanningInvalidSplitProbability.
  ///
  /// In en, this message translates to:
  /// **'Invalid split probability'**
  String get txPlanningInvalidSplitProbability;

  /// No description provided for @txPlanningInvalidMinOutput.
  ///
  /// In en, this message translates to:
  /// **'Invalid min output'**
  String get txPlanningInvalidMinOutput;

  /// No description provided for @txPlanningPlanHeader.
  ///
  /// In en, this message translates to:
  /// **'Plan #{id} · {kind}'**
  String txPlanningPlanHeader(int id, String kind);

  /// No description provided for @txPlanningTxCountFee.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions · total fee {fee} sats'**
  String txPlanningTxCountFee(int count, String fee);

  /// No description provided for @txPlanningSummaryCoins.
  ///
  /// In en, this message translates to:
  /// **'Coins to transfer'**
  String get txPlanningSummaryCoins;

  /// No description provided for @txPlanningSummaryTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total amount'**
  String get txPlanningSummaryTotalAmount;

  /// No description provided for @txPlanningSummaryTotalFee.
  ///
  /// In en, this message translates to:
  /// **'Total fees'**
  String get txPlanningSummaryTotalFee;

  /// No description provided for @txPlanningSummarySigned.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get txPlanningSummarySigned;

  /// No description provided for @txPlanningSignersTitle.
  ///
  /// In en, this message translates to:
  /// **'Signatures: {signed} of {threshold}'**
  String txPlanningSignersTitle(int signed, int threshold);

  /// No description provided for @txPlanningSignedRatio.
  ///
  /// In en, this message translates to:
  /// **'{signed} / {total} signed'**
  String txPlanningSignedRatio(int signed, int total);

  /// No description provided for @txPlanningUnsignedRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions still need signatures.'**
  String txPlanningUnsignedRemaining(int count);

  /// No description provided for @txPlanningCommitButton.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get txPlanningCommitButton;

  /// No description provided for @txPlanningCancelDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel plan?'**
  String get txPlanningCancelDialogTitle;

  /// No description provided for @txPlanningCancelDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Every child PSBT will be deleted.\n\nAny signatures collected so far will be lost.'**
  String get txPlanningCancelDialogBody;

  /// No description provided for @txPlanningKeepButton.
  ///
  /// In en, this message translates to:
  /// **'Keep plan'**
  String get txPlanningKeepButton;

  /// No description provided for @txPlanningTxRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Tx for {outpoint}'**
  String txPlanningTxRowTitle(String outpoint);

  /// No description provided for @txPlanningTxRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{amount} sats in · {fee} fee · matures at block {block}'**
  String txPlanningTxRowSubtitle(String amount, String fee, int block);

  /// No description provided for @txPlanningRunningHeader.
  ///
  /// In en, this message translates to:
  /// **'Plan #{id} · running'**
  String txPlanningRunningHeader(int id);

  /// No description provided for @txPlanningRunningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions pending. Auto-broadcast fires as each timelock matures.'**
  String txPlanningRunningSubtitle(int count);

  /// No description provided for @txPlanningJustBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Just broadcast'**
  String get txPlanningJustBroadcast;

  /// No description provided for @txPlanningStopDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop plan?'**
  String get txPlanningStopDialogTitle;

  /// No description provided for @txPlanningStopDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Pending transactions will be discarded.\n\nAnything already broadcast stays on chain.'**
  String get txPlanningStopDialogBody;

  /// No description provided for @txPlanningKeepRunningButton.
  ///
  /// In en, this message translates to:
  /// **'Keep running'**
  String get txPlanningKeepRunningButton;

  /// No description provided for @txPlanningRowInputsSpent.
  ///
  /// In en, this message translates to:
  /// **'Inputs spent'**
  String get txPlanningRowInputsSpent;

  /// No description provided for @txPlanningRowArmed.
  ///
  /// In en, this message translates to:
  /// **'Broadcasts at block {block}'**
  String txPlanningRowArmed(int block);

  /// No description provided for @txPlanningRowArmedEta.
  ///
  /// In en, this message translates to:
  /// **'{datetime} ({blocks} blocks left)'**
  String txPlanningRowArmedEta(String datetime, int blocks);

  /// No description provided for @txPlanningRowIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get txPlanningRowIdle;

  /// No description provided for @txPlanningRowAmountTitle.
  ///
  /// In en, this message translates to:
  /// **'{amount} sats · #{id}'**
  String txPlanningRowAmountTitle(int amount, int id);

  /// No description provided for @txPlanningTerminalDone.
  ///
  /// In en, this message translates to:
  /// **'Plan complete'**
  String get txPlanningTerminalDone;

  /// No description provided for @txPlanningTerminalCancelled.
  ///
  /// In en, this message translates to:
  /// **'Plan cancelled'**
  String get txPlanningTerminalCancelled;

  /// No description provided for @txPlanningTerminalFailed.
  ///
  /// In en, this message translates to:
  /// **'Plan failed'**
  String get txPlanningTerminalFailed;

  /// No description provided for @txPlanningTerminalGeneric.
  ///
  /// In en, this message translates to:
  /// **'Plan {status}'**
  String txPlanningTerminalGeneric(String status);

  /// No description provided for @txPlanningNewPlanButton.
  ///
  /// In en, this message translates to:
  /// **'New plan'**
  String get txPlanningNewPlanButton;

  /// No description provided for @txPlanningBannerDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan ready to sign'**
  String get txPlanningBannerDraftTitle;

  /// No description provided for @txPlanningBannerDraftSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions queued · plan #{id}'**
  String txPlanningBannerDraftSubtitle(int count, int id);

  /// No description provided for @txPlanningBannerRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan running'**
  String get txPlanningBannerRunningTitle;

  /// No description provided for @txPlanningBannerRunningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} pending · auto-broadcast on maturity'**
  String txPlanningBannerRunningSubtitle(int count);

  /// No description provided for @txPlanningReservedBadge.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get txPlanningReservedBadge;

  /// No description provided for @txPlanningReservedBalance.
  ///
  /// In en, this message translates to:
  /// **'Planned {value}'**
  String txPlanningReservedBalance(String value);

  /// No description provided for @txPlanningConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get txPlanningConfigTitle;

  /// No description provided for @txPlanningDestinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get txPlanningDestinationLabel;

  /// No description provided for @txPlanningDestinationSelf.
  ///
  /// In en, this message translates to:
  /// **'Same wallet (refresh)'**
  String get txPlanningDestinationSelf;

  /// No description provided for @txPlanningDestinationWallet.
  ///
  /// In en, this message translates to:
  /// **'{name} ({kind})'**
  String txPlanningDestinationWallet(String name, String kind);

  /// No description provided for @txPlanningSelectCoins.
  ///
  /// In en, this message translates to:
  /// **'Select coins'**
  String get txPlanningSelectCoins;

  /// No description provided for @txPlanningCoinsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} coins selected'**
  String txPlanningCoinsSelected(String count);

  /// No description provided for @txPlanningAllCoins.
  ///
  /// In en, this message translates to:
  /// **'All coins'**
  String get txPlanningAllCoins;

  /// No description provided for @txPlanningSpendPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Spend path'**
  String get txPlanningSpendPathLabel;

  /// No description provided for @txPlanningFeeRateMinLabel.
  ///
  /// In en, this message translates to:
  /// **'Min fee (sat/vB)'**
  String get txPlanningFeeRateMinLabel;

  /// No description provided for @txPlanningFeeRateMaxLabel.
  ///
  /// In en, this message translates to:
  /// **'Max fee (sat/vB)'**
  String get txPlanningFeeRateMaxLabel;

  /// No description provided for @txPlanningDelayMinLabel.
  ///
  /// In en, this message translates to:
  /// **'Min spacing (blocks)'**
  String get txPlanningDelayMinLabel;

  /// No description provided for @txPlanningDelayMaxLabel.
  ///
  /// In en, this message translates to:
  /// **'Max spacing (blocks)'**
  String get txPlanningDelayMaxLabel;

  /// No description provided for @txPlanningSpacingHelper.
  ///
  /// In en, this message translates to:
  /// **'Blocks between consecutive transactions. Larger ranges mean more privacy and a longer overall migration.'**
  String get txPlanningSpacingHelper;

  /// No description provided for @txPlanningEtaPreview.
  ///
  /// In en, this message translates to:
  /// **'Estimated duration: {minBlocks}–{maxBlocks} blocks (~{minWindow}–{maxWindow}) for {count} transactions'**
  String txPlanningEtaPreview(
    int count,
    int minBlocks,
    int maxBlocks,
    String minWindow,
    String maxWindow,
  );

  /// No description provided for @txPlanningEtaHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String txPlanningEtaHours(int hours);

  /// No description provided for @txPlanningEtaDays.
  ///
  /// In en, this message translates to:
  /// **'{days} d'**
  String txPlanningEtaDays(int days);

  /// No description provided for @txPlanningSplitProbabilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Split probability'**
  String get txPlanningSplitProbabilityLabel;

  /// No description provided for @txPlanningMinOutputLabel.
  ///
  /// In en, this message translates to:
  /// **'Min output (sats)'**
  String get txPlanningMinOutputLabel;

  /// No description provided for @txPlanningFeeRange.
  ///
  /// In en, this message translates to:
  /// **'{min} – {max} sat/vB'**
  String txPlanningFeeRange(String min, String max);

  /// No description provided for @txPlanningDelayRange.
  ///
  /// In en, this message translates to:
  /// **'{min} – {max} blocks'**
  String txPlanningDelayRange(String min, String max);

  /// No description provided for @txPlanningComputePlanButton.
  ///
  /// In en, this message translates to:
  /// **'Compute plan'**
  String get txPlanningComputePlanButton;

  /// No description provided for @txPlanningMigrate.
  ///
  /// In en, this message translates to:
  /// **'migrate'**
  String get txPlanningMigrate;

  /// No description provided for @txPlanningRefresh.
  ///
  /// In en, this message translates to:
  /// **'refresh'**
  String get txPlanningRefresh;

  /// No description provided for @txPlanningSignAllButton.
  ///
  /// In en, this message translates to:
  /// **'Sign all…'**
  String get txPlanningSignAllButton;

  /// No description provided for @txPlanningCommitArmButton.
  ///
  /// In en, this message translates to:
  /// **'Broadcast'**
  String get txPlanningCommitArmButton;

  /// No description provided for @txPlanningSignerPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose signer'**
  String get txPlanningSignerPickerTitle;

  /// No description provided for @txPlanningSignerHotKey.
  ///
  /// In en, this message translates to:
  /// **'Hot key ({mfp})'**
  String txPlanningSignerHotKey(String mfp);

  /// No description provided for @txPlanningSignerHotKeySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign every PSBT in-app with this stored key'**
  String get txPlanningSignerHotKeySubtitle;

  /// No description provided for @txPlanningSignerHw.
  ///
  /// In en, this message translates to:
  /// **'Hardware wallet'**
  String get txPlanningSignerHw;

  /// No description provided for @txPlanningSignerHwSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign every PSBT on the device, one tap per tx'**
  String get txPlanningSignerHwSubtitle;

  /// No description provided for @txPlanningSignerQr.
  ///
  /// In en, this message translates to:
  /// **'Offline signer (QR)'**
  String get txPlanningSignerQr;

  /// No description provided for @txPlanningSignerQrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export every PSBT as animated QR, scan signed back'**
  String get txPlanningSignerQrSubtitle;

  /// No description provided for @txPlanningSignerComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get txPlanningSignerComingSoon;

  /// No description provided for @txPlanningSignerNoHotKeys.
  ///
  /// In en, this message translates to:
  /// **'No hot keys available on this wallet.'**
  String get txPlanningSignerNoHotKeys;

  /// No description provided for @txPlanningConfirmBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign {count} transactions?'**
  String txPlanningConfirmBatchTitle(int count);

  /// No description provided for @txPlanningConfirmBatchBody.
  ///
  /// In en, this message translates to:
  /// **'Total fee {fee} sats · signer: {signer}.\n\nThe batch never asks twice — the next prompt will be the broadcast confirmation.'**
  String txPlanningConfirmBatchBody(String fee, String signer);

  /// No description provided for @txPlanningBatchFailures.
  ///
  /// In en, this message translates to:
  /// **'{count} signing errors — review the failed rows.'**
  String txPlanningBatchFailures(int count);

  /// No description provided for @txPlanningBadgeSigned.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get txPlanningBadgeSigned;

  /// No description provided for @txPlanningBadgePartial.
  ///
  /// In en, this message translates to:
  /// **'Partial ({signed}/{threshold})'**
  String txPlanningBadgePartial(int signed, int threshold);

  /// No description provided for @txPlanningBadgeUnsigned.
  ///
  /// In en, this message translates to:
  /// **'Unsigned'**
  String get txPlanningBadgeUnsigned;

  /// No description provided for @txPlanningBadgeFailed.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get txPlanningBadgeFailed;

  /// No description provided for @txPlanningHwBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign batch with hardware wallet'**
  String get txPlanningHwBatchTitle;

  /// No description provided for @txPlanningHwBatchReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to sign {count} transactions'**
  String txPlanningHwBatchReady(int count);

  /// No description provided for @txPlanningHwBatchStartButton.
  ///
  /// In en, this message translates to:
  /// **'Start signing'**
  String get txPlanningHwBatchStartButton;

  /// No description provided for @txPlanningHwBatchProgress.
  ///
  /// In en, this message translates to:
  /// **'Signing {current} of {total}…'**
  String txPlanningHwBatchProgress(int current, int total);

  /// No description provided for @txPlanningHwBatchApplying.
  ///
  /// In en, this message translates to:
  /// **'Merging signatures…'**
  String get txPlanningHwBatchApplying;

  /// No description provided for @txPlanningHwBatchRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry transaction {current}'**
  String txPlanningHwBatchRetryButton(int current);

  /// No description provided for @txPlanningHwBatchFinishEarlyButton.
  ///
  /// In en, this message translates to:
  /// **'Finish with {signed} signed'**
  String txPlanningHwBatchFinishEarlyButton(int signed);

  /// No description provided for @txPlanningSignMfpTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign with this key'**
  String get txPlanningSignMfpTitle;

  /// No description provided for @txPlanningSignerHotKeyOption.
  ///
  /// In en, this message translates to:
  /// **'Hot key'**
  String get txPlanningSignerHotKeyOption;

  /// No description provided for @txPlanningHwBatchWrongDevice.
  ///
  /// In en, this message translates to:
  /// **'This hardware wallet ({mfp}) is not part of the plan\'s signing keys.'**
  String txPlanningHwBatchWrongDevice(String mfp);

  /// No description provided for @txPlanningHwBatchAllSigned.
  ///
  /// In en, this message translates to:
  /// **'This key has already signed every transaction in the plan.'**
  String get txPlanningHwBatchAllSigned;

  /// No description provided for @txPlanningQrSignTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign batch via QR'**
  String get txPlanningQrSignTitle;

  /// No description provided for @txPlanningQrSignCurrent.
  ///
  /// In en, this message translates to:
  /// **'Transaction {current} of {total}'**
  String txPlanningQrSignCurrent(int current, int total);

  /// No description provided for @txPlanningQrSignHint.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR on your offline signer, then tap “Scan signature” to capture the signed PSBT.'**
  String get txPlanningQrSignHint;

  /// No description provided for @txPlanningQrSignScanButton.
  ///
  /// In en, this message translates to:
  /// **'Scan signature'**
  String get txPlanningQrSignScanButton;

  /// No description provided for @txPlanningQrSignMismatchToast.
  ///
  /// In en, this message translates to:
  /// **'The scanned signature does not match this transaction.'**
  String get txPlanningQrSignMismatchToast;

  /// No description provided for @txPlanningQrSignNoNewSigToast.
  ///
  /// In en, this message translates to:
  /// **'The scanned PSBT did not add any new signature.'**
  String get txPlanningQrSignNoNewSigToast;

  /// No description provided for @txPlanningQrSignAllDone.
  ///
  /// In en, this message translates to:
  /// **'Batch fully signed.'**
  String get txPlanningQrSignAllDone;

  /// No description provided for @txPlanningConfirmCommitTitle.
  ///
  /// In en, this message translates to:
  /// **'Broadcast {count} transactions?'**
  String txPlanningConfirmCommitTitle(int count);

  /// No description provided for @txPlanningConfirmCommitBody.
  ///
  /// In en, this message translates to:
  /// **'Total fee {fee} sats.\n\nFirst broadcast around {earliest}, last around {latest}.\n\nEach transaction emits automatically when its timelock matures.'**
  String txPlanningConfirmCommitBody(
    String fee,
    String earliest,
    String latest,
  );

  /// No description provided for @txPlanningConfirmCommitBodyTipUnknown.
  ///
  /// In en, this message translates to:
  /// **'Total fee {fee} sats.\n\nBroadcast windows depend on the chain tip (not yet synced).\n\nEach transaction emits automatically when its timelock matures.'**
  String txPlanningConfirmCommitBodyTipUnknown(String fee);

  /// No description provided for @txPlanningCommitConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Broadcast'**
  String get txPlanningCommitConfirmButton;

  /// No description provided for @batteryOptBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Improve background broadcasting'**
  String get batteryOptBannerTitle;

  /// No description provided for @batteryOptBannerBody.
  ///
  /// In en, this message translates to:
  /// **'Android may delay or skip scheduled broadcasts when Deadbolt is in the background. Exclude the app from battery optimization for reliable auto-broadcast.'**
  String get batteryOptBannerBody;

  /// No description provided for @batteryOptBannerAction.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get batteryOptBannerAction;

  /// No description provided for @batteryOptBannerDismiss.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get batteryOptBannerDismiss;

  /// No description provided for @settingsSectionBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get settingsSectionBackground;

  /// No description provided for @batteryOptTileTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization'**
  String get batteryOptTileTitle;

  /// No description provided for @batteryOptTileExempt.
  ///
  /// In en, this message translates to:
  /// **'Allowed — background broadcasts will run reliably.'**
  String get batteryOptTileExempt;

  /// No description provided for @batteryOptTileRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted — Android may delay or skip background broadcasts.'**
  String get batteryOptTileRestricted;
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
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
