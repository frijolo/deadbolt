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

  /// No description provided for @menuImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get menuImport;

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get menuAbout;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

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

  /// No description provided for @deleteProjectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProjectTooltip;

  /// No description provided for @couldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read file'**
  String get couldNotReadFile;

  /// No description provided for @projectImportedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Project imported successfully'**
  String get projectImportedSuccess;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @newProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProjectTitle;

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

  /// No description provided for @selectWalletTypeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select wallet type'**
  String get selectWalletTypeTooltip;

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

  /// No description provided for @preferredNetworkLabel.
  ///
  /// In en, this message translates to:
  /// **'Preferred Network'**
  String get preferredNetworkLabel;

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

  /// No description provided for @separateFieldsMode.
  ///
  /// In en, this message translates to:
  /// **'Separate fields'**
  String get separateFieldsMode;

  /// No description provided for @fullKeyspecMode.
  ///
  /// In en, this message translates to:
  /// **'Full keyspec'**
  String get fullKeyspecMode;

  /// No description provided for @mfpLabel.
  ///
  /// In en, this message translates to:
  /// **'Master Fingerprint (MFP)'**
  String get mfpLabel;

  /// No description provided for @mfpHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., c449c5c5'**
  String get mfpHint;

  /// No description provided for @derivationPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Derivation Path'**
  String get derivationPathLabel;

  /// No description provided for @derivationPathHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., 48h/0h/0h/2h'**
  String get derivationPathHint;

  /// No description provided for @xpubLabel.
  ///
  /// In en, this message translates to:
  /// **'Extended Public Key (xpub)'**
  String get xpubLabel;

  /// No description provided for @xpubHint.
  ///
  /// In en, this message translates to:
  /// **'xpub6...'**
  String get xpubHint;

  /// No description provided for @fullKeyspecLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Keyspec'**
  String get fullKeyspecLabel;

  /// No description provided for @fullKeyspecHint.
  ///
  /// In en, this message translates to:
  /// **'[c449c5c5/48h/0h/0h/2h]xpub6...'**
  String get fullKeyspecHint;

  /// No description provided for @fullKeyspecHelperText.
  ///
  /// In en, this message translates to:
  /// **'Format: [mfp/path]xpub'**
  String get fullKeyspecHelperText;

  /// No description provided for @allFieldsRequired.
  ///
  /// In en, this message translates to:
  /// **'All fields are required'**
  String get allFieldsRequired;

  /// No description provided for @keyspecRequired.
  ///
  /// In en, this message translates to:
  /// **'Keyspec is required'**
  String get keyspecRequired;

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

  /// No description provided for @descriptorSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Descriptor'**
  String get descriptorSectionTitle;

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

  /// No description provided for @saveToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Save to Downloads'**
  String get saveToDownloads;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save as…'**
  String get saveAs;

  /// No description provided for @shareFile.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareFile;

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

  /// No description provided for @qrBytesPerFrame.
  ///
  /// In en, this message translates to:
  /// **'Bytes/frame'**
  String get qrBytesPerFrame;

  /// No description provided for @qrEcLevel.
  ///
  /// In en, this message translates to:
  /// **'Error correction'**
  String get qrEcLevel;

  /// No description provided for @qrTooLargeForLevel.
  ///
  /// In en, this message translates to:
  /// **'Content too large for this error correction level'**
  String get qrTooLargeForLevel;

  /// No description provided for @qrPart.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String qrPart(int current, int total);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

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

  /// No description provided for @spendPathMustHaveKey.
  ///
  /// In en, this message translates to:
  /// **'Spend path {index}: Must have at least one key'**
  String spendPathMustHaveKey(int index);

  /// No description provided for @spendPathKeyNotFound.
  ///
  /// In en, this message translates to:
  /// **'Spend path {index}: Key {mfp} not found'**
  String spendPathKeyNotFound(int index, String mfp);

  /// No description provided for @spendPathThresholdMin.
  ///
  /// In en, this message translates to:
  /// **'Spend path {index}: Threshold must be at least 1'**
  String spendPathThresholdMin(int index);

  /// No description provided for @spendPathThresholdExceeds.
  ///
  /// In en, this message translates to:
  /// **'Spend path {index}: Threshold cannot exceed number of keys'**
  String spendPathThresholdExceeds(int index);

  /// No description provided for @taprootOneKeyPath.
  ///
  /// In en, this message translates to:
  /// **'Only one spend path can be marked as key-path in Taproot descriptors.'**
  String get taprootOneKeyPath;

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

  /// No description provided for @tapToName.
  ///
  /// In en, this message translates to:
  /// **'Tap to name'**
  String get tapToName;

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

  /// No description provided for @pathPrefix.
  ///
  /// In en, this message translates to:
  /// **'Path: '**
  String get pathPrefix;

  /// No description provided for @rootPath.
  ///
  /// In en, this message translates to:
  /// **'(root)'**
  String get rootPath;

  /// No description provided for @xpubPrefix.
  ///
  /// In en, this message translates to:
  /// **'Xpub: '**
  String get xpubPrefix;

  /// No description provided for @keyNameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Key name'**
  String get keyNameDialogTitle;

  /// No description provided for @removeKeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get removeKeyTooltip;

  /// No description provided for @keyInUseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Key in use - cannot delete'**
  String get keyInUseTooltip;

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
