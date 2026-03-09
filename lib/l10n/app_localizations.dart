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

  /// No description provided for @importFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get importFromFile;

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

  /// No description provided for @loadingWallets.
  ///
  /// In en, this message translates to:
  /// **'Loading wallets...'**
  String get loadingWallets;

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

  /// No description provided for @sourceProjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceProjectLabel;

  /// No description provided for @sourceProjectFromProject.
  ///
  /// In en, this message translates to:
  /// **'From project'**
  String get sourceProjectFromProject;

  /// No description provided for @sourceProjectManual.
  ///
  /// In en, this message translates to:
  /// **'Manual descriptor'**
  String get sourceProjectManual;

  /// No description provided for @selectProjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Select project'**
  String get selectProjectLabel;

  /// No description provided for @createWalletButton.
  ///
  /// In en, this message translates to:
  /// **'Create Wallet'**
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

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(String error);

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

  /// No description provided for @txFee.
  ///
  /// In en, this message translates to:
  /// **'Fee: {fee} sats'**
  String txFee(int fee);

  /// No description provided for @txHeight.
  ///
  /// In en, this message translates to:
  /// **'Block: {height}'**
  String txHeight(int height);

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

  /// No description provided for @electrumSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Electrum Servers'**
  String get electrumSectionTitle;

  /// No description provided for @electrumUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Electrum URL'**
  String get electrumUrlLabel;

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

  /// No description provided for @explorerNoUrl.
  ///
  /// In en, this message translates to:
  /// **'No explorer configured for this network'**
  String get explorerNoUrl;

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

  /// No description provided for @txLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Add a label...'**
  String get txLabelHint;

  /// No description provided for @txLabelRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove label'**
  String get txLabelRemove;

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

  /// No description provided for @viewInExplorer.
  ///
  /// In en, this message translates to:
  /// **'View in explorer'**
  String get viewInExplorer;

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

  /// No description provided for @coinLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Add a label...'**
  String get coinLabelHint;

  /// No description provided for @coinLabelRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove label'**
  String get coinLabelRemove;

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

  /// No description provided for @descriptorTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Descriptor'**
  String get descriptorTabLabel;

  /// No description provided for @spendPathsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Spend paths'**
  String get spendPathsAvailable;

  /// No description provided for @spendPathsNotSynced.
  ///
  /// In en, this message translates to:
  /// **'Sync to see available spend paths'**
  String get spendPathsNotSynced;

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

  /// No description provided for @spendPathLockedUntilBlock.
  ///
  /// In en, this message translates to:
  /// **'Locked until block {block}'**
  String spendPathLockedUntilBlock(int block);

  /// No description provided for @spendPathLockedBlocks.
  ///
  /// In en, this message translates to:
  /// **'{blocks} blocks remaining'**
  String spendPathLockedBlocks(int blocks);

  /// No description provided for @spendPathNeedsConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Needs confirmation'**
  String get spendPathNeedsConfirmation;

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

  /// No description provided for @psbtStatusMempool.
  ///
  /// In en, this message translates to:
  /// **'MEMPOOL'**
  String get psbtStatusMempool;

  /// No description provided for @psbtStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'CONFIRMED'**
  String get psbtStatusConfirmed;

  /// No description provided for @createTxTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Transaction'**
  String get createTxTitle;

  /// No description provided for @createTxRecipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient address'**
  String get createTxRecipient;

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

  /// No description provided for @createTxFeeRateHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1.5'**
  String get createTxFeeRateHint;

  /// No description provided for @createTxFeeRateMin.
  ///
  /// In en, this message translates to:
  /// **'Minimum fee rate is {min} sat/vB'**
  String createTxFeeRateMin(String min);

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

  /// No description provided for @createTxAutoSelect.
  ///
  /// In en, this message translates to:
  /// **'Auto-select coins'**
  String get createTxAutoSelect;

  /// No description provided for @createTxButton.
  ///
  /// In en, this message translates to:
  /// **'Create PSBT'**
  String get createTxButton;

  /// No description provided for @createTxCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get createTxCreating;

  /// No description provided for @createTxRecipientRequired.
  ///
  /// In en, this message translates to:
  /// **'Recipient address is required'**
  String get createTxRecipientRequired;

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

  /// No description provided for @createTxSendMax.
  ///
  /// In en, this message translates to:
  /// **'Send all (max)'**
  String get createTxSendMax;

  /// No description provided for @createTxSelfPayButton.
  ///
  /// In en, this message translates to:
  /// **'SELF'**
  String get createTxSelfPayButton;

  /// No description provided for @createTxNoUnusedAddress.
  ///
  /// In en, this message translates to:
  /// **'No unused receive address available'**
  String get createTxNoUnusedAddress;

  /// No description provided for @createTxFeeRateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid fee rate'**
  String get createTxFeeRateInvalid;

  /// No description provided for @createTxNoSpendPaths.
  ///
  /// In en, this message translates to:
  /// **'No spend paths available. Sync the wallet first.'**
  String get createTxNoSpendPaths;

  /// No description provided for @createTxSuccess.
  ///
  /// In en, this message translates to:
  /// **'PSBT created'**
  String get createTxSuccess;

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

  /// No description provided for @psbtExportButton.
  ///
  /// In en, this message translates to:
  /// **'Export PSBT'**
  String get psbtExportButton;

  /// No description provided for @psbtImportSignedButton.
  ///
  /// In en, this message translates to:
  /// **'Import signed PSBT'**
  String get psbtImportSignedButton;

  /// No description provided for @psbtImportFromQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get psbtImportFromQr;

  /// No description provided for @psbtImportFromFile.
  ///
  /// In en, this message translates to:
  /// **'From file (.psbt)'**
  String get psbtImportFromFile;

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

  /// No description provided for @psbtBroadcastFailed.
  ///
  /// In en, this message translates to:
  /// **'Broadcast failed: {error}'**
  String psbtBroadcastFailed(String error);

  /// No description provided for @psbtMergeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Signatures imported'**
  String get psbtMergeSuccess;

  /// No description provided for @psbtMergeFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String psbtMergeFailed(String error);

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

  /// No description provided for @psbtExportedCopied.
  ///
  /// In en, this message translates to:
  /// **'PSBT copied'**
  String get psbtExportedCopied;

  /// No description provided for @coinSelectMode.
  ///
  /// In en, this message translates to:
  /// **'Select coins'**
  String get coinSelectMode;

  /// No description provided for @coinSelectDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get coinSelectDone;

  /// No description provided for @coinSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String coinSelected(int count);

  /// No description provided for @createTxFeeByRate.
  ///
  /// In en, this message translates to:
  /// **'Rate (sat/vB)'**
  String get createTxFeeByRate;

  /// No description provided for @createTxFeeByTotal.
  ///
  /// In en, this message translates to:
  /// **'Total (sats)'**
  String get createTxFeeByTotal;

  /// No description provided for @createTxTotalFee.
  ///
  /// In en, this message translates to:
  /// **'Fee (sats)'**
  String get createTxTotalFee;

  /// No description provided for @createTxTotalFeeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive fee amount'**
  String get createTxTotalFeeInvalid;

  /// No description provided for @createTxFeeEstimate.
  ///
  /// In en, this message translates to:
  /// **'Fee estimate'**
  String get createTxFeeEstimate;

  /// No description provided for @createTxEstInputs.
  ///
  /// In en, this message translates to:
  /// **'Inputs'**
  String get createTxEstInputs;

  /// No description provided for @createTxEstSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get createTxEstSend;

  /// No description provided for @createTxEstFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get createTxEstFee;

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

  /// No description provided for @relatedAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address label'**
  String get relatedAddressLabel;

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

  /// No description provided for @creatingTransaction.
  ///
  /// In en, this message translates to:
  /// **'Creating transaction'**
  String get creatingTransaction;
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
