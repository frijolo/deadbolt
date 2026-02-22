// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get clear => 'Clear';

  @override
  String get add => 'Add';

  @override
  String get edit => 'Edit';

  @override
  String get export => 'Export';

  @override
  String get discard => 'Discard';

  @override
  String get loadingProjects => 'Loading projects...';

  @override
  String get projectsTitle => 'Projects';

  @override
  String get menuNew => 'New';

  @override
  String get menuImport => 'Import';

  @override
  String get menuAbout => 'About';

  @override
  String get menuSettings => 'Settings';

  @override
  String get noProjects => 'No projects yet.\nTap + to create one.';

  @override
  String get deleteProjectTitle => 'Delete project';

  @override
  String deleteProjectConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get deleteProjectTooltip => 'Delete project';

  @override
  String get couldNotReadFile => 'Could not read file';

  @override
  String get projectImportedSuccess => 'Project imported successfully';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get newProjectTitle => 'New project';

  @override
  String get importDescriptorMode => 'Import descriptor';

  @override
  String get fromScratchMode => 'Start from scratch';

  @override
  String get projectNameLabel => 'Project name';

  @override
  String get descriptorLabel => 'Descriptor';

  @override
  String get descriptorHint => 'Paste your Bitcoin descriptor here...';

  @override
  String get networkLabel => 'Network';

  @override
  String get selectNetworkTooltip => 'Select network';

  @override
  String get walletTypeLabel => 'Wallet type';

  @override
  String get selectWalletTypeTooltip => 'Select wallet type';

  @override
  String get analyzeAndSave => 'Analyze & Save';

  @override
  String get createProject => 'Create Project';

  @override
  String get projectNameRequired => 'Project name is required';

  @override
  String get descriptorEmpty => 'Descriptor cannot be empty';

  @override
  String get analyzingDescriptor => 'Analyzing descriptor...';

  @override
  String get creatingProject => 'Creating project...';

  @override
  String get aboutTitle => 'About';

  @override
  String get loadingAppInfo => 'Loading app info...';

  @override
  String get bitcoinDescriptorAnalyzer => 'Bitcoin Descriptor Analyzer';

  @override
  String get versionLabel => 'Version';

  @override
  String get projectSectionTitle => 'Project';

  @override
  String get githubRepository => 'GitHub Repository';

  @override
  String get securityGpg => 'Security & GPG';

  @override
  String get licenseLabel => 'License';

  @override
  String get mitLicense => 'MIT License';

  @override
  String get openSourceDescription =>
      'Open source Bitcoin wallet descriptor analysis';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get languageLabel => 'Language';

  @override
  String get preferredNetworkLabel => 'Preferred Network';

  @override
  String get preferredWalletTypeLabel => 'Default Wallet Type';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageEs => 'Español';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeSystem => 'System default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get discardChangesTooltip => 'Discard changes';

  @override
  String get moreOptionsTooltip => 'More options';

  @override
  String get buildFabLabel => 'Build';

  @override
  String keysSection(int count) {
    return 'Keys ($count)';
  }

  @override
  String get addKeyButton => 'Add key';

  @override
  String spendPathsSection(int count) {
    return 'Spend paths ($count)';
  }

  @override
  String get addSpendPath => 'Add spend path';

  @override
  String get addKeyDialogTitle => 'Add Key';

  @override
  String get separateFieldsMode => 'Separate fields';

  @override
  String get fullKeyspecMode => 'Full keyspec';

  @override
  String get mfpLabel => 'Master Fingerprint (MFP)';

  @override
  String get mfpHint => 'e.g., c449c5c5';

  @override
  String get derivationPathLabel => 'Derivation Path';

  @override
  String get derivationPathHint => 'e.g., 48h/0h/0h/2h';

  @override
  String get xpubLabel => 'Extended Public Key (xpub)';

  @override
  String get xpubHint => 'xpub6...';

  @override
  String get fullKeyspecLabel => 'Full Keyspec';

  @override
  String get fullKeyspecHint => '[c449c5c5/48h/0h/0h/2h]xpub6...';

  @override
  String get fullKeyspecHelperText => 'Format: [mfp/path]xpub';

  @override
  String get allFieldsRequired => 'All fields are required';

  @override
  String get keyspecRequired => 'Keyspec is required';

  @override
  String get invalidKeyspecFormat =>
      'Invalid keyspec format. Expected: [mfp/path]xpub';

  @override
  String duplicateMfp(String mfp) {
    return 'A key with MFP $mfp already exists';
  }

  @override
  String get descriptorSectionTitle => 'Descriptor';

  @override
  String get copyDescriptorTooltip => 'Export descriptor';

  @override
  String get descriptorCopied => 'Descriptor copied';

  @override
  String get copyToClipboard => 'Copy to clipboard';

  @override
  String get saveToDownloads => 'Save to Downloads';

  @override
  String get saveAs => 'Save as…';

  @override
  String get shareFile => 'Share';

  @override
  String get showQrCode => 'Show QR code';

  @override
  String get scanQrCode => 'Scan QR code';

  @override
  String get fromFile => 'From file';

  @override
  String get qrNotFoundInImage => 'No QR code found in image';

  @override
  String get cameraError => 'Camera not available on this platform';

  @override
  String get importFromQrImage => 'Import QR image';

  @override
  String get qrDialogTitle => 'QR Code';

  @override
  String get qrAnimatedLabel => 'Animated (BC-UR)';

  @override
  String get qrBytesPerFrame => 'Bytes/frame';

  @override
  String get qrEcLevel => 'Error correction';

  @override
  String get qrTooLargeForLevel =>
      'Content too large for this error correction level';

  @override
  String qrPart(int current, int total) {
    return '$current / $total';
  }

  @override
  String get close => 'Close';

  @override
  String get savedToDownloads => 'File saved';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get projectNameDialogTitle => 'Project name';

  @override
  String get discardChangesDialogTitle => 'Discard changes?';

  @override
  String get discardChangesContent =>
      'You have unsaved changes. This action cannot be undone.';

  @override
  String get changeWalletTypeTooltip => 'Change wallet type';

  @override
  String spendPathMustHaveKey(int index) {
    return 'Spend path $index: Must have at least one key';
  }

  @override
  String spendPathKeyNotFound(int index, String mfp) {
    return 'Spend path $index: Key $mfp not found';
  }

  @override
  String spendPathThresholdMin(int index) {
    return 'Spend path $index: Threshold must be at least 1';
  }

  @override
  String spendPathThresholdExceeds(int index) {
    return 'Spend path $index: Threshold cannot exceed number of keys';
  }

  @override
  String get taprootOneKeyPath =>
      'Only one spend path can be marked as key-path in Taproot descriptors.';

  @override
  String get buildingDescriptor => 'Building descriptor...';

  @override
  String get buildingDescriptorMultiPath =>
      'Building descriptor with multiple paths...';

  @override
  String get buildingComplexDescriptor =>
      'Building complex descriptor...\nThis may take some time';

  @override
  String get analyzingDescriptorLoading => 'Analyzing descriptor...';

  @override
  String get analyzingComplexDescriptor => 'Analyzing complex descriptor...';

  @override
  String get analyzingAndSaving => 'Analyzing and saving...';

  @override
  String get enterName => 'Enter a name';

  @override
  String get nameAlreadyUsed => 'This name is already used by another key';

  @override
  String get tapToName => 'Tap to name';

  @override
  String get copyKeyspecTooltip => 'Copy keyspec';

  @override
  String get keyCopied => 'Key copied';

  @override
  String get pathPrefix => 'Path: ';

  @override
  String get rootPath => '(root)';

  @override
  String get xpubPrefix => 'Xpub: ';

  @override
  String get keyNameDialogTitle => 'Key name';

  @override
  String get removeKeyTooltip => 'Remove key';

  @override
  String get keyInUseTooltip => 'Key in use - cannot delete';

  @override
  String get spendPathNameDialogTitle => 'Spend path name';

  @override
  String get keyPathBadge => 'KEY PATH';

  @override
  String get setAsKeyPath => 'Set as key path';

  @override
  String get removePathTooltip => 'Remove path';

  @override
  String get keysLabel => 'Keys';

  @override
  String get newKey => 'New key';

  @override
  String get noTimelock => 'No timelock';

  @override
  String priorityBadge(int priority) {
    return 'Priority $priority';
  }

  @override
  String get changeThresholdTooltip => 'Change threshold';

  @override
  String ofCount(int count) {
    return 'of $count';
  }

  @override
  String get thresholdLabel => 'Threshold';

  @override
  String get changePriorityTooltip => 'Change priority';

  @override
  String get timelockDialogTitle => 'Timelock';

  @override
  String get relativeTimelock => 'Relative';

  @override
  String get absoluteTimelock => 'Absolute';

  @override
  String get blocksTimelock => 'Blocks';

  @override
  String get timeTimelock => 'Time';

  @override
  String get timestampTimelock => 'Timestamp';

  @override
  String get selectDateAndTime => 'Select date and time';

  @override
  String get blocksRelHint => 'Blocks (0-65,535)';

  @override
  String get timeUnitsHint => 'Units × 512s (0-65,535)';

  @override
  String get blocksAbsHint => 'Blocks (0-499,999,999)';

  @override
  String get timelockValueMax => 'Value must be ≤ 65,535';

  @override
  String get blockHeightMax => 'Block height must be < 500,000,000';

  @override
  String get timestampMin => 'Timestamp must be ≥ 500,000,000';

  @override
  String get mustHaveAtLeastOneKey => 'Must have at least one key';

  @override
  String get thresholdMustBeAtLeastOne => 'Threshold must be at least 1';

  @override
  String get thresholdCannotExceed => 'Threshold cannot exceed number of keys';

  @override
  String get errorCopiedToClipboard => 'Error copied to clipboard';

  @override
  String get projectExportedSuccess => 'Project exported successfully';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get networkMainnet => 'Mainnet';

  @override
  String get networkTestnet => 'Testnet';

  @override
  String get networkTestnet4 => 'Testnet4';

  @override
  String get networkSignet => 'Signet';

  @override
  String get networkRegtest => 'Regtest';

  @override
  String get walletTypeP2pkh => 'Legacy (P2PKH)';

  @override
  String get walletTypeP2wpkh => 'Segwit (P2WPKH)';

  @override
  String get walletTypeP2sh => 'Legacy (P2SH)';

  @override
  String get walletTypeP2wsh => 'Segwit (P2WSH)';

  @override
  String get walletTypeP2tr => 'Taproot (P2TR)';

  @override
  String get walletTypeP2shWpkh => 'Nested Segwit (P2SH-WPKH)';

  @override
  String get walletTypeP2shWsh => 'Nested Segwit (P2SH-WSH)';

  @override
  String get walletTypeUnknown => 'Unknown';
}
