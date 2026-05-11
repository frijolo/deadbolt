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
  String get previous => 'Previous';

  @override
  String get next => 'Next';

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
  String get importFromFile => 'Import from file';

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
  String get descriptorViewAlias => 'Alias';

  @override
  String get descriptorViewRaw => 'Raw';

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
  String get activeNetworkLabel => 'Active Network';

  @override
  String get activeNetworkDescription =>
      'Only wallets on this network are shown. Wallets on other networks are hidden, not deleted.';

  @override
  String walletsHiddenOnOtherNetworks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'wallets',
      one: 'wallet',
    );
    return '$count $_temp0 on other networks — change in Settings';
  }

  @override
  String restoringToNetwork(String network) {
    return 'Restoring to: $network';
  }

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
  String get screenshotProtectionLabel => 'Screenshot Protection';

  @override
  String get screenshotProtectionSubtitle =>
      'Prevent screenshots and screen recording';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get biometricLockLabel => 'Biometric Lock';

  @override
  String get biometricLockSubtitle => 'Require biometrics to open the app';

  @override
  String get biometricLockInfoTitle => 'Biometric Lock';

  @override
  String get biometricLockInfoBody =>
      'When enabled, Deadbolt will require fingerprint, face, or your device PIN/pattern to unlock every time you open the app or return from the background.\n\nMake sure your device has biometrics or a screen lock set up before enabling this.';

  @override
  String get biometricLockInfoEnable => 'Enable';

  @override
  String get biometricTimeoutLabel => 'Lock after';

  @override
  String get biometricTimeoutImmediate => 'Immediately';

  @override
  String get biometricTimeout1Min => '1 minute';

  @override
  String get biometricTimeout5Min => '5 minutes';

  @override
  String get biometricUnlockReason => 'Authenticate to access Deadbolt';

  @override
  String get biometricUnlockButton => 'Unlock';

  @override
  String get biometricSetupFailed =>
      'Authentication failed. Biometric lock was not enabled.';

  @override
  String get biometricWalletSectionTitle => 'Biometric unlock';

  @override
  String get biometricWalletSectionBody =>
      'Use fingerprint or face ID to open this wallet without typing your password.';

  @override
  String get biometricWalletUnlockReason => 'Authenticate to open wallet';

  @override
  String get biometricWalletEnableFailed =>
      'Could not enable biometric unlock. Try again.';

  @override
  String get biometricWalletDisableFailed =>
      'Could not disable biometric unlock.';

  @override
  String get biometricWalletRootedWarning =>
      'Warning: on rooted or jailbroken devices the unlock key stored in secure storage may be extractable.';

  @override
  String get discardChangesTooltip => 'Discard changes';

  @override
  String get moreOptionsTooltip => 'More options';

  @override
  String get buildFabLabel => 'Build';

  @override
  String get descriptorOutdatedBanner =>
      'Descriptor outdated · tap Build to regenerate';

  @override
  String get keySectionLabel => 'Key';

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
  String get shareFile => 'Share file';

  @override
  String get shareText => 'Share';

  @override
  String get showQrCode => 'Show QR code';

  @override
  String get scanQrCode => 'Scan QR code';

  @override
  String get fromFile => 'From file';

  @override
  String get showAsText => 'Show as text';

  @override
  String get pasteFromClipboard => 'Paste from clipboard';

  @override
  String get pasteText => 'Paste text';

  @override
  String get pasteTextHint => 'Paste your content here…';

  @override
  String get clipboardEmpty => 'Clipboard is empty';

  @override
  String clipboardWillClear(int seconds) {
    return 'Clipboard will be cleared in ${seconds}s';
  }

  @override
  String get clipboardCleared => 'Clipboard cleared';

  @override
  String get importAction => 'Import';

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
  String get enable => 'Enable';

  @override
  String get close => 'Close';

  @override
  String get dismiss => 'Dismiss';

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
  String get keyFingerprintLabel => 'Fingerprint';

  @override
  String get keyDerivPathLabel => 'Derivation path';

  @override
  String get keyXpubLabel => 'Extended public key';

  @override
  String get removeKeyTooltip => 'Remove key';

  @override
  String get keyInUseTooltip => 'Key in use - cannot delete';

  @override
  String get hotKeyBadge => 'HOT';

  @override
  String get privateKeySection => 'Private key';

  @override
  String get viewPrivateKeyButton => 'View seed phrase';

  @override
  String get deletePrivateKeyButton => 'Remove signing key';

  @override
  String get viewPrivateKeyDisclaimer =>
      'Make sure no one can see your screen. Your seed phrase gives full access to your funds.';

  @override
  String get deletePrivateKeyDisclaimer =>
      'This removes the signing key from this project. You will no longer be able to sign transactions from the Designer.';

  @override
  String get deleteWalletPrivateKeyDisclaimer =>
      'This removes the signing key from this wallet. You will no longer be able to sign transactions with it.';

  @override
  String get viewPrivateKeyConfirm => 'Show seed';

  @override
  String get deletePrivateKeyConfirm => 'Remove';

  @override
  String get seedPhraseDialogTitle => 'Seed phrase';

  @override
  String get seedPhraseCopied => 'Seed phrase copied';

  @override
  String get seedExportTitle => 'Seed Export';

  @override
  String get seedExportTabWords => 'Words';

  @override
  String get seedExportTabQr => 'QR Code';

  @override
  String get seedExportTabGuide => 'Paper Guide';

  @override
  String get seedQrStandard => 'Standard SeedQR';

  @override
  String get seedQrCompact => 'Compact SeedQR';

  @override
  String get seedPassphraseWarning =>
      'This seed has a passphrase that is not shown here.';

  @override
  String get seedPassphraseNotIncluded => 'Passphrase not included in QR';

  @override
  String get seedMfpSeedOnly => 'Seed only';

  @override
  String get seedMfpWithPassphrase => 'Seed + passphrase';

  @override
  String seedGuideSegmentLabel(String label, int total) {
    return 'Segment $label of $total';
  }

  @override
  String get seedGuideDoneTitle => 'All segments transcribed';

  @override
  String get seedGuideDoneBody =>
      'Verify by scanning your paper QR with a camera.';

  @override
  String get seedGuideVerifyQr => 'Verify QR';

  @override
  String get seedGuideVerifySuccess => 'QR verified correctly.';

  @override
  String get seedGuideVerifyMismatch => 'QR does not match the seed.';

  @override
  String get seedGuideInstructions =>
      'Transcribe each segment to paper. Filled squares = dark modules.';

  @override
  String get seedGuideTapToAdvance => 'Tap QR to advance';

  @override
  String get seedGuideRestart => 'Restart';

  @override
  String seedQrSize(String format, int size) {
    return '$format · $size×$size';
  }

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
  String get sweepCostLabel => 'Sweep cost';

  @override
  String get trDepthLabel => 'TR depth';

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

  @override
  String get walletPolicySingleSig => 'SingleSig';

  @override
  String get walletPolicyMiniscript => 'Miniscript';

  @override
  String get walletAddressLegacy => 'Legacy';

  @override
  String get walletAddressSegwit => 'SegWit';

  @override
  String get walletAddressNested => 'Nested';

  @override
  String get walletAddressTaproot => 'Taproot';

  @override
  String get navDesigner => 'Designer';

  @override
  String get navWallet => 'Wallet';

  @override
  String get walletsTitle => 'Wallets';

  @override
  String get noWallets => 'No wallets yet.\nTap + to create one.';

  @override
  String get createWalletFromProject => 'Create wallet';

  @override
  String get generateProjectFromWallet => 'Analyze in Designer';

  @override
  String get projectHasNoDescriptor =>
      'This project has no descriptor yet. Build one first.';

  @override
  String get loadingWallets => 'Loading wallets...';

  @override
  String get openingWallet => 'Opening wallet…';

  @override
  String get loadingWalletData => 'Loading wallet data…';

  @override
  String get loadingAddresses => 'Loading addresses…';

  @override
  String get loadingCoins => 'Loading coins…';

  @override
  String get initializingCamera => 'Initializing camera…';

  @override
  String get switchCamera => 'Switch camera';

  @override
  String get deleteWalletTitle => 'Delete wallet';

  @override
  String deleteWalletConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get createWalletTitle => 'New Wallet';

  @override
  String get walletNameLabel => 'Wallet name';

  @override
  String get walletNameRequired => 'Wallet name is required';

  @override
  String get deleteProjectAfterCreate =>
      'Delete this project after creating the wallet';

  @override
  String get fromProjectAction => 'From project';

  @override
  String get createWalletButton => 'Create wallet';

  @override
  String get creatingWallet => 'Creating wallet...';

  @override
  String get balanceConfirmed => 'Confirmed';

  @override
  String get balancePending => 'Pending';

  @override
  String get balanceImmature => 'Immature';

  @override
  String balanceSats(int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return '$satsString sats';
  }

  @override
  String balanceBtc(String btc) {
    return '$btc BTC';
  }

  @override
  String get walletPasswordProtected => 'Password protected';

  @override
  String get lockWallet => 'Lock wallet';

  @override
  String get backupSaved => 'Backup saved';

  @override
  String get changeProtectionMenu => 'Change protection';

  @override
  String get encryptionLabel => 'Encryption';

  @override
  String get walletSecurityLabel => 'Security';

  @override
  String get walletSecurityTitle => 'Wallet Security';

  @override
  String get encryptionSection => 'Encryption';

  @override
  String get descriptorSigsSection => 'Descriptor Signatures';

  @override
  String get manageSignatures => 'Manage Signatures';

  @override
  String get goToSecurity => 'Go to Security';

  @override
  String get noParticipatingKeys => 'No participating keys found';

  @override
  String get descriptorSigAbsent => 'No signatures';

  @override
  String get descriptorSigVerified => 'Signatures verified';

  @override
  String get descriptorSigInvalid => 'Invalid signatures';

  @override
  String get descriptorSigOwnerUnsigned => 'Owner xpub not signed';

  @override
  String get descriptorSigUnknown => 'Signature status unknown';

  @override
  String get walletBalanceUnknown => '–';

  @override
  String get notYetSynced => 'Not yet synced';

  @override
  String lastSynced(String time) {
    return 'Last synced: $time';
  }

  @override
  String get syncButton => 'Sync';

  @override
  String get syncTooltip => 'Sync wallet';

  @override
  String get syncing => 'Syncing...';

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String get rescanButton => 'Full rescan';

  @override
  String get rescanConfirmTitle => 'Full rescan';

  @override
  String get rescanConfirmBody =>
      'This will re-scan all addresses from scratch. It may take longer than a normal sync.';

  @override
  String get transactionsSection => 'Transactions';

  @override
  String get noTransactions => 'No transactions yet';

  @override
  String get txReceived => 'Received';

  @override
  String get txSent => 'Sent';

  @override
  String get txSelfTransfer => 'Self-transfer';

  @override
  String get txConfirmed => 'Confirmed';

  @override
  String get txUnconfirmed => 'Unconfirmed';

  @override
  String txFee(int fee) {
    final intl.NumberFormat feeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String feeString = feeNumberFormat.format(fee);

    return 'Fee: $feeString sats';
  }

  @override
  String txHeight(int height) {
    final intl.NumberFormat heightNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String heightString = heightNumberFormat.format(height);

    return 'Block: $heightString';
  }

  @override
  String get txId => 'TXID';

  @override
  String get loadMore => 'Load more';

  @override
  String get electrumSectionTitle => 'Electrum Servers';

  @override
  String get electrumUrlLabel => 'Electrum URL';

  @override
  String get electrumUrlHint => 'ssl://host:port or tcp://host:port';

  @override
  String get electrumNetworkMainnet => 'Mainnet Electrum';

  @override
  String get electrumNetworkTestnet => 'Testnet Electrum';

  @override
  String get electrumNetworkTestnet4 => 'Testnet4 Electrum';

  @override
  String get electrumNetworkSignet => 'Signet Electrum';

  @override
  String get electrumNetworkRegtest => 'Regtest Electrum';

  @override
  String get settingsMinFeeRate => 'Minimum fee rate (sat/vB)';

  @override
  String get fiatSectionTitle => 'Fiat Values';

  @override
  String get fiatEnabledLabel => 'Show fiat values';

  @override
  String get fiatCurrencyLabel => 'Currency';

  @override
  String get fiatProviderLabel => 'Price provider';

  @override
  String get fiatProviderCoinGecko => 'CoinGecko';

  @override
  String get fiatProviderMempoolSpace => 'Mempool.space';

  @override
  String get explorerSectionTitle => 'Block Explorer';

  @override
  String get explorerUrlHint => 'https://mempool.space';

  @override
  String get explorerNetworkMainnet => 'Mainnet Explorer';

  @override
  String get explorerNetworkTestnet => 'Testnet Explorer';

  @override
  String get explorerNetworkTestnet4 => 'Testnet4 Explorer';

  @override
  String get explorerNetworkSignet => 'Signet Explorer';

  @override
  String get explorerNetworkRegtest => 'Regtest Explorer';

  @override
  String get explorerNoUrl => 'No explorer configured for this network';

  @override
  String get openInExplorer => 'Open in explorer';

  @override
  String get txLabelTitle => 'Label';

  @override
  String get txDetailsTitle => 'Transaction details';

  @override
  String get txDetailsNet => 'Net amount';

  @override
  String get txDetailsGrossReceived => 'Received (gross)';

  @override
  String get txDetailsGrossSent => 'Sent (gross)';

  @override
  String get txDetailsBlockHeight => 'Block height';

  @override
  String get txDetailsConfirmedAt => 'Confirmed at';

  @override
  String get txDetailsFee => 'Fee';

  @override
  String get addressesSection => 'Addresses';

  @override
  String get receiveAddresses => 'Receive';

  @override
  String get changeAddresses => 'Change';

  @override
  String get noAddresses => 'No addresses yet. Sync to discover addresses.';

  @override
  String addressIndex(int index) {
    return '#$index';
  }

  @override
  String get addressLabelTitle => 'Address label';

  @override
  String get addressLabelHint => 'Add a label...';

  @override
  String get addressLabelRemove => 'Remove label';

  @override
  String get addressDetailsTitle => 'Address details';

  @override
  String addressBalanceSats(int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return '$satsString sats';
  }

  @override
  String get revealMoreAddresses => 'Reveal 20 more addresses';

  @override
  String addressTxCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString transactions';
  }

  @override
  String get viewInExplorer => 'View in explorer';

  @override
  String get coinsSection => 'Coins';

  @override
  String get noCoins => 'No coins. Sync to discover UTXOs.';

  @override
  String get coinDetailsTitle => 'Coin details';

  @override
  String get coinLabelTitle => 'Label';

  @override
  String get coinOutpoint => 'Outpoint';

  @override
  String get coinValue => 'Value';

  @override
  String get coinAddress => 'Address';

  @override
  String get coinKeychain => 'Keychain';

  @override
  String get coinKeychainReceive => 'Receive';

  @override
  String get coinKeychainChange => 'Change';

  @override
  String get coinAgeLabel => 'Age';

  @override
  String get coinBlockNumber => 'Block';

  @override
  String get coinConfirmations => 'Confirmations';

  @override
  String coinTotalCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString coins';
  }

  @override
  String coinTotalValue(int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return 'Total: $satsString sats';
  }

  @override
  String get spendPathsAvailable => 'Spend paths';

  @override
  String get spendPathsNotSynced => 'Sync to see available spend paths';

  @override
  String get spendPathUnlocked => 'Unlocked';

  @override
  String get spendPathLocked => 'Locked';

  @override
  String spendPathLockedUntilBlock(int block) {
    final intl.NumberFormat blockNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blockString = blockNumberFormat.format(block);

    return 'Locked until block $blockString';
  }

  @override
  String spendPathBlocks(int blocks) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return '$blocksString blocks';
  }

  @override
  String get spendPathNeedsConfirmation => 'Needs confirmation';

  @override
  String get spendPathUnconfirmed => 'Unconfirmed';

  @override
  String get spendPathNeedsSync => 'Sync required';

  @override
  String get psbtStatusUnsigned => 'UNSIGNED';

  @override
  String get psbtStatusPartial => 'PARTIAL';

  @override
  String get psbtStatusSigned => 'SIGNED';

  @override
  String get psbtStatusMempool => 'MEMPOOL';

  @override
  String get psbtStatusConfirmed => 'CONFIRMED';

  @override
  String get psbtStatusSpent => 'SPENT';

  @override
  String get psbtSpentInputsWarning =>
      'One or more inputs have been confirmed spent by another transaction. This PSBT can no longer be broadcast.';

  @override
  String get createTxTitle => 'Create Transaction';

  @override
  String get createTxRecipient => 'Recipient address';

  @override
  String get createTxRecipientHint => 'bc1q...';

  @override
  String get createTxAmount => 'Amount (sats)';

  @override
  String get createTxFeeRate => 'Fee rate (sat/vB)';

  @override
  String get createTxFeeRateHint => 'e.g. 1.5';

  @override
  String createTxFeeRateMin(String min) {
    return 'Minimum fee rate is $min sat/vB';
  }

  @override
  String get createTxSpendPath => 'Spend path';

  @override
  String get createTxSpendPathHint => 'Select a spend path';

  @override
  String createTxSelectedCoins(int count, int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return '$count coin(s) selected — $satsString sats';
  }

  @override
  String get createTxAutoSelect => 'Auto-select coins';

  @override
  String get createTxButton => 'Create PSBT';

  @override
  String get createTxCreating => 'Creating...';

  @override
  String get createTxRecipientRequired => 'Recipient address is required';

  @override
  String get createTxAmountRequired => 'Amount is required';

  @override
  String get createTxAmountInvalid => 'Invalid amount';

  @override
  String get createTxMaxButton => 'MAX';

  @override
  String get createTxSendMax => 'Send all (max)';

  @override
  String get createTxSelfPayButton => 'SELF';

  @override
  String get createTxMyWalletsButton => 'MY WALLETS';

  @override
  String get createTxSelectDestWallet => 'Select destination wallet';

  @override
  String get createTxThisWallet => 'This wallet (Self)';

  @override
  String get createTxNoUnusedAddress => 'No unused receive address available';

  @override
  String get createTxFeeRateInvalid => 'Invalid fee rate';

  @override
  String get createTxNoSpendPaths =>
      'No spend paths available. Sync the wallet first.';

  @override
  String get createTxSuccess => 'PSBT created';

  @override
  String get psbtDetailTitle => 'Unsigned Transaction';

  @override
  String get psbtRecipient => 'Recipient';

  @override
  String get psbtAmount => 'Amount';

  @override
  String get psbtFee => 'Fee';

  @override
  String get psbtCreatedAt => 'Created';

  @override
  String get psbtTimelockLabel => 'Timelock';

  @override
  String get psbtTimelockSyncRequired => 'Sync required to check status';

  @override
  String psbtTimelockBlocksRemaining(int blocks, String duration) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return '$blocksString blocks remaining (~$duration)';
  }

  @override
  String psbtTimelockTimeRemaining(String duration) {
    return '~$duration remaining';
  }

  @override
  String psbtSignaturesTitle(int done, int threshold, int total) {
    return 'Signatures ($done/$threshold of $total)';
  }

  @override
  String get psbtSignerSigned => 'Signed';

  @override
  String get psbtSignerMissing => 'Missing';

  @override
  String get psbtSignerOptional => 'Optional';

  @override
  String get psbtSignerUnknown => 'Unknown';

  @override
  String get psbtExportButton => 'Export PSBT';

  @override
  String get psbtImportSignedButton => 'Import signature';

  @override
  String get psbtImportFromQr => 'Scan QR';

  @override
  String get psbtImportFromFile => 'From file (.psbt)';

  @override
  String get psbtBroadcastButton => 'Broadcast';

  @override
  String psbtBroadcastSuccess(String txid) {
    return 'Transaction broadcast! TXID: $txid';
  }

  @override
  String psbtBroadcastFailed(String error) {
    return 'Broadcast failed: $error';
  }

  @override
  String get psbtMergeSuccess => 'Signatures imported';

  @override
  String psbtMergeFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get psbtDeleteTitle => 'Delete PSBT';

  @override
  String get psbtDeleteConfirm => 'Delete this unsigned transaction?';

  @override
  String get psbtExportedCopied => 'PSBT copied';

  @override
  String get coinSelectMode => 'Select coins';

  @override
  String get coinSelectDone => 'Done';

  @override
  String coinSelected(int count) {
    return '$count selected';
  }

  @override
  String get createTxFeeByRate => 'Rate (sat/vB)';

  @override
  String get createTxFeeByTotal => 'Total (sats)';

  @override
  String get createTxTotalFee => 'Fee (sats)';

  @override
  String get createTxTotalFeeInvalid => 'Enter a positive fee amount';

  @override
  String get createTxFeeEstimate => 'Fee estimate';

  @override
  String get createTxEstInputs => 'Inputs';

  @override
  String get createTxEstSend => 'Send';

  @override
  String get createTxEstFee => 'Fee';

  @override
  String get createTxEstChange => 'Change';

  @override
  String get createTxEstInsufficientFunds => 'Insufficient funds';

  @override
  String get createTxAddRecipient => 'Add recipient';

  @override
  String get createTxMoreOutputTypes => 'More output types';

  @override
  String get opReturnAddOutput => 'Add OP_RETURN data';

  @override
  String get opReturnInputLabel => 'Embedded data';

  @override
  String get opReturnHexToggle => 'Hex';

  @override
  String get opReturnUtf8Toggle => 'Text';

  @override
  String get opReturnSizeWarning =>
      'Outputs over 80 bytes may not be relayed by all nodes';

  @override
  String get opReturnRecipientLabel => 'OP_RETURN data';

  @override
  String get opReturnCannotBeMaxRecipient =>
      'OP_RETURN cannot receive remaining funds';

  @override
  String get opReturnSingleLimit => 'Only one OP_RETURN output allowed';

  @override
  String get opReturnInvalidHex => 'Invalid hex';

  @override
  String get opReturnEmptyError => 'OP_RETURN data is empty';

  @override
  String opReturnByteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bytes',
      one: '1 byte',
    );
    return '$_temp0';
  }

  @override
  String get opReturnCopyAsText => 'Copy as text';

  @override
  String get opReturnCopyAsHex => 'Copy as hex';

  @override
  String get createTxTotalOut => 'Total out';

  @override
  String get createTxSelectCoinsFirst => 'Select coins to build a transaction';

  @override
  String get walletSendButton => 'Send';

  @override
  String get coinSelectorTitle => 'Select coins';

  @override
  String get coinSelectorNoCoinsSelected => 'Tap to select coins...';

  @override
  String coinSelectorDoneCount(int count) {
    return 'Done ($count)';
  }

  @override
  String get relatedCoins => 'Related coins';

  @override
  String get relatedAddressLabel => 'Address label';

  @override
  String get relatedAddresses => 'Output addresses';

  @override
  String get inputAddresses => 'Input addresses';

  @override
  String get relatedTransactions => 'Related transactions';

  @override
  String get creatingTransaction => 'Creating transaction';

  @override
  String get exportBip329Button => 'Export';

  @override
  String get importBip329Button => 'Import';

  @override
  String get exportBip329Empty => 'No explicit labels to export';

  @override
  String get exportBip329Copied => 'Labels copied';

  @override
  String get importBip329Success => 'Labels imported';

  @override
  String get exportDescriptorFormatTitle => 'Export format';

  @override
  String get exportDescriptorStandard => 'Standard';

  @override
  String get exportDescriptorStandardDesc =>
      'Compatible with Nunchuk and most wallets';

  @override
  String get exportDescriptorLiana => 'Liana';

  @override
  String get exportDescriptorLianaDesc =>
      'Adds [00000000] to the unspendable key';

  @override
  String get exportLabelsOption => 'Labels (BIP-329)';

  @override
  String get importPsbtOption => 'PSBT';

  @override
  String get importPsbtMerged => 'Signatures merged';

  @override
  String get importPsbtSaved => 'PSBT imported';

  @override
  String get coinPendingSpend => 'PSBT';

  @override
  String get coinMempoolSpend => 'Spending';

  @override
  String get coinPendingPsbtsSection => 'Pending transactions';

  @override
  String get overviewTab => 'Overview';

  @override
  String get walletReceiveButton => 'Receive';

  @override
  String get noUnusedReceiveAddress =>
      'No unused receive address found. Try syncing first.';

  @override
  String get receiveNextAddress => 'Next address';

  @override
  String get rbfWarningTitle => 'Full-RBF replacement';

  @override
  String get rbfOriginalFee => 'Original fee';

  @override
  String get rbfDescendants => 'Descendants';

  @override
  String get rbfMinFee => 'Minimum fee';

  @override
  String get rbfMinRate => 'Minimum rate';

  @override
  String get rbfUnknownFee =>
      'Spending a mempool UTXO — use a higher fee rate than the original tx.';

  @override
  String rbfFeeTooLow(double rate) {
    return 'Fee rate too low for RBF — minimum is $rate sat/vB';
  }

  @override
  String rbfAbsFeeTooLow(int fee) {
    return 'Total fee too low for RBF — minimum is $fee sats';
  }

  @override
  String get cpfpBannerTitle => 'CPFP acceleration';

  @override
  String get cpfpParentFee => 'Ancestor fees';

  @override
  String get cpfpAncestorCount => 'Ancestor txs';

  @override
  String get cpfpEffectiveRate => 'Package fee rate';

  @override
  String get cpfpAccelerate => 'Accelerate';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsSectionDefaults => 'Wallet';

  @override
  String get settingsSectionTransactions => 'Transactions';

  @override
  String get settingsSectionConnectivity => 'Connectivity';

  @override
  String get torLabel => 'Use Tor';

  @override
  String get torSubtitle => 'Route all traffic through Tor';

  @override
  String get torStatusConnecting => 'Tor connecting...';

  @override
  String get torStatusConnected => 'Tor active';

  @override
  String get torErrorNotConnected => 'Tor is enabled but not yet connected';

  @override
  String get disclaimerTitle => 'Beta Software — Use at Your Own Risk';

  @override
  String get disclaimerBody =>
      'Deadbolt is under active development and may contain bugs or errors.\n\nIt is not yet suitable for use with real funds. Use at your own risk.';

  @override
  String get disclaimerDontShow7Days => 'Don\'t show for 7 days';

  @override
  String get electrumPrivacyWarning =>
      'Using a public Electrum server. Your IP and transaction history may be visible to third parties. Configure a personal server in Settings.';

  @override
  String get goToSettings => 'Settings';

  @override
  String get wifExportTitle => 'Export private key (WIF)';

  @override
  String get wifExportWarning =>
      'This exports the private key of a single address, but if your wallet\'\'s XPUB is known to anyone — a coordinator, exchange, or any service you\'\'ve shared it with — they can use this WIF to derive the private keys of every address in your wallet.\n\nOnly proceed if your XPUB is private, or if you fully accept this risk.';

  @override
  String get wifExportTypeToConfirm => 'Type to confirm:';

  @override
  String get wifExportConfirmPhrase => 'my full wallet is at risk';

  @override
  String get wifExportShowButton => 'Show WIF';

  @override
  String get wifDisplayWarning =>
      'Never share this key. If your XPUB is known to others, this WIF exposes your entire wallet.';

  @override
  String get protectionLabel => 'Protection';

  @override
  String get protectionNone => 'None';

  @override
  String get protectionPassword => 'Password';

  @override
  String get protectionXpub => 'XPub';

  @override
  String get protectionUnprotected => 'Unprotected';

  @override
  String get protectionXpubInfo =>
      'Any xpub from the wallet can unlock it. Do not share those xpubs with third parties.';

  @override
  String get securityLevelLabel => 'Anti-brute-force level';

  @override
  String get securityLevelStandard => 'Standard';

  @override
  String get securityLevelHigh => 'High';

  @override
  String get securityLevelExtreme => 'Extreme';

  @override
  String get newPasswordLabel => 'New password';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get backupPasswordLabel => 'Backup password';

  @override
  String get validatorPasswordEmpty => 'Password cannot be empty';

  @override
  String get validatorPasswordRequired => 'Password required';

  @override
  String get validatorPasswordsNoMatch => 'Passwords do not match';

  @override
  String get validatorNameRequired => 'Name is required';

  @override
  String get changeButton => 'Change';

  @override
  String get exportButton => 'Export';

  @override
  String get backButton => 'Back';

  @override
  String get feeRateLabel => 'Fee rate';

  @override
  String get verifyOnDeviceButton => 'Verify on device';

  @override
  String get changeProtectionTitle => 'Change wallet protection';

  @override
  String changeProtectionCurrent(String protection) {
    return 'Current: $protection';
  }

  @override
  String protectionChangedToast(String protection) {
    return 'Protection changed to $protection';
  }

  @override
  String get exportBackupTitle => 'Export backup';

  @override
  String get sweepWifTitle => 'Sweep WIF key';

  @override
  String get sweepWifPrivateKeySection => 'Private key (WIF)';

  @override
  String get sweepWifHint => 'Paste or scan WIF key...';

  @override
  String get sweepWifSearching => 'Searching...';

  @override
  String get sweepWifFindUtxos => 'Find UTXOs';

  @override
  String get sweepWifControlledAddresses => 'Controlled addresses';

  @override
  String sweepWifTotal(int amount) {
    return 'Total: $amount sat';
  }

  @override
  String get sweepWifNoFunds =>
      'No funds found for this key on the current network.';

  @override
  String get sweepWifDestination => 'Destination';

  @override
  String get sweepWifAddressHint => 'Bitcoin address...';

  @override
  String get sweepWifSweeping => 'Sweeping...';

  @override
  String sweepWifButton(int amount) {
    return 'Sweep $amount sat';
  }

  @override
  String get sweepWifEnterKeyFirst => 'Enter a WIF key first';

  @override
  String get sweepWifFillFields => 'Fill all fields with valid values';

  @override
  String sweepWifSweptToast(String txid) {
    return 'Swept: $txid';
  }

  @override
  String get sweepWifEmpty => 'empty';

  @override
  String get walletCreateGuided => 'Guided creation';

  @override
  String get walletCreateGuidedSub => 'Standard wallet from your keys';

  @override
  String get walletCreateFromDescriptor => 'From descriptor';

  @override
  String get walletCreateFromDescriptorSub =>
      'Enter a Bitcoin descriptor directly';

  @override
  String get walletCreateFromProject => 'From project';

  @override
  String get walletCreateFromProjectSub => 'Use a descriptor from the designer';

  @override
  String get walletCreateFromBackup => 'From backup';

  @override
  String get walletCreateFromBackupSub =>
      'Restore a wallet from a .deadbolt file';

  @override
  String get projectCreateFromScratch => 'From scratch';

  @override
  String get projectCreateFromScratchSub =>
      'Pick network and wallet type, then add keys';

  @override
  String get projectCreateFromDescriptorSub =>
      'Paste, scan or import a Bitcoin descriptor';

  @override
  String get projectCreateImport => 'Import project';

  @override
  String get projectCreateImportSub => 'Restore a project from a .json export';

  @override
  String get newWalletTitle => 'New Wallet';

  @override
  String get walletExportLabel => 'Wallet';

  @override
  String get walletTypeSinglesig => 'Singlesig';

  @override
  String get walletTypeMultisig => 'Multisig';

  @override
  String get walletTypeSinglesigDesc =>
      'One key controls the wallet. Simpler and faster to set up.';

  @override
  String get walletTypeMultisigDesc =>
      'Multiple keys required to sign. Ideal for shared control or extra security.';

  @override
  String get walletTypeInheritance => 'Inheritance';

  @override
  String get walletTypeInheritanceDesc =>
      'Multi-path wallet: you control funds now, heirs can access after a set time delay.';

  @override
  String get ownerKeysSection => 'Your keys';

  @override
  String get heirsSection => 'Heirs';

  @override
  String get addHeir => 'Add heir';

  @override
  String get editHeir => 'Edit heir';

  @override
  String get heirName => 'Heir name';

  @override
  String get heirNameHint => 'e.g. Alice, Family, Lawyer';

  @override
  String get heirKey => 'Heir\'s key';

  @override
  String get heirTimelockLabel => 'Can access after';

  @override
  String get inheritanceSixMonths => '6 months (~26,280 blocks)';

  @override
  String get inheritanceOneYear => '1 year (~52,560 blocks)';

  @override
  String get inheritanceThreeMonthsShort => '3 mo';

  @override
  String get inheritanceSixMonthsShort => '6 mo';

  @override
  String get inheritanceNineMonthsShort => '9 mo';

  @override
  String get inheritanceOneYearShort => '1 yr';

  @override
  String get inheritanceThreeMonths => '3 months (~13,140 blocks)';

  @override
  String get inheritanceNineMonths => '9 months (~39,420 blocks)';

  @override
  String get inheritanceCustomTimelock => 'Custom...';

  @override
  String get inheritanceDuplicateTimelockTitle => 'Duplicate timelocks';

  @override
  String get inheritanceDuplicateTimelockBody =>
      'Two or more heirs share the same timelock. For better compatibility with other coordination software, each spending path should have a unique timelock.';

  @override
  String get inheritanceDuplicateTimelockFix => 'Fix automatically';

  @override
  String get inheritanceDuplicateTimelockContinue => 'Continue anyway';

  @override
  String get inheritanceHeirsNeedKey => 'Set a key for each heir';

  @override
  String get inheritanceNeedHeir => 'Add at least one heir';

  @override
  String get inheritanceOwnerPathLabel => 'Main';

  @override
  String get inheritanceMinTimelockLabel => 'Inheritance timelock threshold';

  @override
  String get inheritanceMinTimelockInfoTitle => 'Inheritance detection';

  @override
  String get inheritanceMinTimelockInfo =>
      'Some Taproot descriptors use spend paths with short timelocks (e.g. 1–2 blocks) to model multiple signing combinations for the same owner — these are not inheritance paths. This threshold is the minimum number of blocks a relative timelock must have before a spend path is treated as an inheritance path and the status panel is shown.\n\nDefault: 144 blocks (~1 day).';

  @override
  String get inheritanceStatus => 'Inheritance';

  @override
  String get inheritanceSafe => 'Safe';

  @override
  String get inheritanceApproaching => 'Heir access approaching';

  @override
  String get inheritanceUnlocked => 'Heir can access funds';

  @override
  String get inheritanceNeedsSync => 'Sync to check heir access';

  @override
  String get inheritanceNoFunds => 'No confirmed funds';

  @override
  String get revaultNow => 'Re-vault';

  @override
  String get revaultTitle => 'Reset inheritance timer';

  @override
  String get revaultDescription =>
      'Sends all funds back to this wallet. Once confirmed, the inheritance timer resets — heirs must wait the full delay again.';

  @override
  String get revaultFeeRateLabel => 'Fee rate (sat/vB)';

  @override
  String get revaultCreateButton => 'Create re-vault transaction';

  @override
  String get revaultCreating => 'Creating transaction...';

  @override
  String get blocksUnit => 'blocks';

  @override
  String inheritanceHeirN(int n) {
    return 'Heir $n';
  }

  @override
  String inheritanceEarliestAccess(String duration, int blocks) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return 'Earliest heir access in ~$duration ($blocksString blocks)';
  }

  @override
  String get scriptTypeLabel => 'Script type';

  @override
  String get scriptTypeLegacy => 'Legacy';

  @override
  String get scriptTypeNested => 'Nested';

  @override
  String get scriptTypeSegwit => 'SegWit';

  @override
  String get scriptTypeTaproot => 'Taproot';

  @override
  String get scriptDescP2pkh => 'P2PKH — Oldest standard. Highest fees.';

  @override
  String get scriptDescP2sh => 'P2SH — Oldest multisig standard. Highest fees.';

  @override
  String get scriptDescP2shWpkh =>
      'P2SH-P2WPKH — SegWit wrapped for backward compatibility. Rarely needed today.';

  @override
  String get scriptDescP2shWsh =>
      'P2SH-P2WSH — SegWit multisig with backward compatibility. Rarely needed today.';

  @override
  String get scriptDescP2wpkh =>
      'P2WPKH — Most common modern standard. Lower fees.';

  @override
  String get scriptDescP2wsh =>
      'P2WSH — Native SegWit multisig. Lower fees, widely supported.';

  @override
  String get scriptDescP2trSinglesig =>
      'P2TR — Taproot. Best privacy and lowest fees.';

  @override
  String get scriptDescP2trMultisig =>
      'P2TR — Taproot multisig. Best privacy. Requires compatible wallets.';

  @override
  String requiredSignatures(int m, int n) {
    return 'Required signatures: $m of $n';
  }

  @override
  String get decreaseThresholdTooltip => 'Decrease threshold';

  @override
  String get increaseThresholdTooltip => 'Increase threshold';

  @override
  String get replaceKeyTooltip => 'Replace key';

  @override
  String get keyDetailsTooltip => 'Key details';

  @override
  String get creatingWalletLabel => 'Creating wallet…';

  @override
  String get addAtLeastOneKey => 'Add at least one key';

  @override
  String get multisigNeedsMinKeys => 'Multi key wallets need at least 2 keys';

  @override
  String get hwWalletTitle => 'Hardware wallet';

  @override
  String get hwWalletScanning => 'Scanning for devices…';

  @override
  String get hwWalletConnecting => 'Connecting…';

  @override
  String get hwWalletUnlockDevice => 'Unlock your device…';

  @override
  String get hwWalletNoDevices =>
      'No hardware wallet detected.\nMake sure it is plugged in.';

  @override
  String get hwWalletSelectDevice => 'Select a device';

  @override
  String get hwWalletScanDevices => 'Scan for devices';

  @override
  String get hwWalletPairingCode => 'Pairing code';

  @override
  String get hwWalletNoConfirmNeeded =>
      'No confirmation needed on the device for key export.';

  @override
  String get hwRegisterWallet => 'Register wallet';

  @override
  String get hwRegisterWalletSub => 'Register this policy on the device';

  @override
  String get hwNotRequired => 'Not required for single-key wallets';

  @override
  String get hwCheckRegistration => 'Check registration';

  @override
  String get hwCheckRegistrationSub => 'Verify if this policy is registered';

  @override
  String get hwWalletRegistered => 'Wallet registered on device.';

  @override
  String get hwWalletIsRegistered => 'Wallet is registered on this device.';

  @override
  String get hwWalletNotRegistered =>
      'Wallet is NOT registered on this device.';

  @override
  String get hwNoDevice => 'No device connected';

  @override
  String get hwScanButton => 'Scan';

  @override
  String get hwDisconnectButton => 'Disconnect';

  @override
  String get hwSelectDevice => 'Select a device:';

  @override
  String get hwPairingCompare => 'Compare with device screen and confirm:';

  @override
  String get directSendConfirmTitle => 'Confirm send';

  @override
  String get directSendConfirmAction => 'Sign and broadcast';

  @override
  String directSendSuccess(String txid) {
    return 'Sent: $txid';
  }

  @override
  String get accountIndexLabel => 'Account';

  @override
  String get restoreFromSeedMenuLabel => 'Recover from seed';

  @override
  String get restoreFromSeedTitle => 'Recover from seed';

  @override
  String get scanAccountsAction => 'Scan accounts';

  @override
  String get scanAccountsScanning => 'Scanning accounts…';

  @override
  String scanAccountsScanningHint(int accountGap, int addrGap) {
    return 'Checking addresses on Electrum…\n(accounts gap: $accountGap, addresses gap: $addrGap)';
  }

  @override
  String get accountGapLimitLabel => 'Account gap limit';

  @override
  String get addressGapLimitLabel => 'Address gap limit';

  @override
  String get scanNonStandardPathsLabel => 'Non-standard derivation paths';

  @override
  String get scanNonStandardPathsHint =>
      'Also scan alternative BIP purpose paths for each script type (44/49/84/86)';

  @override
  String get scanAccountsNoActivity => 'No accounts with prior activity found.';

  @override
  String scanAccountsScannedCount(int count) {
    return 'Scanned $count accounts';
  }

  @override
  String scanAccountsFoundBackups(int count) {
    return '$count account(s) found';
  }

  @override
  String scanAccountsNewAccount(int index) {
    return 'Use new account ($index)';
  }

  @override
  String get scanAccountsNoActivitySubtitle =>
      'Recover accounts from a mnemonic phrase';

  @override
  String get restoreFromHwMenuLabel => 'Recover from hardware wallet';

  @override
  String get restoreFromHwMenuSubtitle =>
      'Scan accounts from a connected BitBox02';

  @override
  String get restoreFromHwTitle => 'Recover from Hardware Wallet';

  @override
  String get hwDiscoveryNoDevice =>
      'No hardware wallet connected. Connect and pair your device first.';

  @override
  String get hwDiscoveryStart => 'Scan accounts';

  @override
  String hwDiscoveryDeriving(int n, int total) {
    return 'Exporting keys… ($n/$total)';
  }

  @override
  String get hwDiscoveryScanning => 'Scanning blockchain…';

  @override
  String scanAccountsActivitySummary(int txCount) {
    return '$txCount tx';
  }

  @override
  String get scanAccountsCreateWallet => 'Create wallet';

  @override
  String get scanAccountsRetry => 'Retry';

  @override
  String get walletNotFound => 'Wallet not found on device';

  @override
  String get searchNostrLabel => 'Search Nostr backups';

  @override
  String get searchNostrHint =>
      'Look for descriptor backups on configured relays';

  @override
  String get hwSkipLegacyLabel => 'Skip legacy (P2PKH) derivations';

  @override
  String get hwSkipLegacyHint =>
      'Avoids device confirmation prompts for m/44’ paths';

  @override
  String get searchNostrScanningHint =>
      'Also searching Nostr relays for descriptor backups…';

  @override
  String get onChainScanningHint =>
      'Also searching for on-chain descriptor backups…';

  @override
  String get nostrBackupFoundOnScan => 'Nostr backup found';

  @override
  String get importFromNostrBackup => 'Restore from Nostr';

  @override
  String get nostrImportTamperTitle => 'Verify after import';

  @override
  String get nostrImportTamperBody =>
      'Anyone who knows the xpub can modify this backup. After importing, confirm the descriptor and receiving addresses match your expected wallet before sending any funds.';

  @override
  String get scanTypeAll => 'All';

  @override
  String get bip39PassphraseLabel => 'BIP39 passphrase (optional)';

  @override
  String get pressBackAgainToExit => 'Press back again to exit';

  @override
  String get feeHistogramTitle => 'Next block fees';

  @override
  String get feeHistogramNext => 'Next';

  @override
  String get confirm => 'Confirm';

  @override
  String get ok => 'OK';

  @override
  String get copy => 'Copy';

  @override
  String get refresh => 'Refresh';

  @override
  String get tryAgain => 'Try again';

  @override
  String get scanAgain => 'Scan again';

  @override
  String get signButton => 'Sign';

  @override
  String get unlock => 'Unlock';

  @override
  String get addPrivateKeyLabel => 'Add private key';

  @override
  String get addSigningKeyLabel => 'Add signing key';

  @override
  String get editKeyTitle => 'Edit key';

  @override
  String get addKeyClipboardSubtitle => 'Clipboard, file or QR code';

  @override
  String get addKeyHwSubtitle => 'USB or Bluetooth device';

  @override
  String get addKeyManualTitle => 'Enter manually';

  @override
  String get addKeyManualSubtitle => 'Watch Only (xpub) or Hot Key (seed)';

  @override
  String get validating => 'Validating...';

  @override
  String get registeredKeys => 'Registered keys';

  @override
  String get showRegisteredKeys => 'Show registered keys';

  @override
  String get enterXpubToUnlock => 'Enter xpub to unlock';

  @override
  String get xpubUnlockHint =>
      'Paste any xpub registered for this wallet. Keyspec format ([mfp/path]xpub) is also accepted.';

  @override
  String get required => 'Required';

  @override
  String get invalidXpubOrKeyspec => 'Invalid xpub or keyspec';

  @override
  String get signWithHwWallet => 'Sign with hardware wallet';

  @override
  String get enterWalletPassword => 'Enter wallet password';

  @override
  String get walletPasswordSubtitle =>
      'This wallet is protected with a password.';

  @override
  String get enterBackupPassword => 'Enter backup password';

  @override
  String get backupPasswordSubtitle => 'This backup is password-protected.';

  @override
  String get wifPrivateKeyLabel => 'WIF private key';

  @override
  String get verifyButton => 'Verify';

  @override
  String get derivPathWithoutLeading => 'Without leading m/';

  @override
  String get nostrRelaysLabel => 'Nostr Relays';

  @override
  String get nostrRelaysSubtitle => 'Relays for encrypted descriptor backups';

  @override
  String get nostrRelayAddHint => 'wss://relay.example.com';

  @override
  String get nostrRelayInvalidUrl => 'URL must start with wss:// or ws://';

  @override
  String get nostrRelayDuplicate => 'Relay already in list';

  @override
  String get nostrRelayAddButton => 'Add relay';

  @override
  String get nostrRelayTimeoutLabel => 'Timeout (seconds)';

  @override
  String get nostrRelayMaxAttemptsLabel => 'Attempts per relay';

  @override
  String get nostrSearchNetworkWarning =>
      'Connection issues with some Nostr relays. Some backups may not have been found.';

  @override
  String get publishBackupMenu => 'Publish Backup';

  @override
  String get publishBackupTitle => 'Publish Backup';

  @override
  String get publishBackupSinglesigTitle => 'Backup not recommended';

  @override
  String get publishBackupSinglesigBody =>
      'This is a singlesig wallet. Its descriptor can be fully recovered from the seed (or xpub) via standard wallet discovery — no external backup is needed. Publishing it to Nostr or on-chain only adds a privacy risk by linking your xpub to extra public data.';

  @override
  String get publishBackupSinglesigContinue =>
      'I understand, show options anyway';

  @override
  String get backupSinglesigShortNote =>
      'Not recommended for singlesig: descriptor is recoverable from the seed via discovery. Publishing it only adds privacy risk.';

  @override
  String get nostrBackupMenu => 'Nostr Backup';

  @override
  String get nostrBackupTitle => 'Nostr Backup';

  @override
  String get nostrBackupSubtitle =>
      'Encrypted descriptor backup on Nostr relays';

  @override
  String get nostrBackupPublish => 'Publish Backup';

  @override
  String get nostrBackupRefresh => 'Refresh Status';

  @override
  String get nostrBackupPublished => 'Backup published';

  @override
  String get nostrBackupSecurityNote =>
      'Anyone with your xpub can locate and decrypt this backup. Only share xpubs with trusted co-signers.';

  @override
  String get nostrBackupFound => 'Backup found';

  @override
  String get nostrBackupNotFound => 'No backup found';

  @override
  String nostrBackupPartialCosigners(int backedUp, int total) {
    return '$backedUp/$total cosigners backed up';
  }

  @override
  String get nostrBackupError => 'Relay error';

  @override
  String get nostrBackupNoRelays =>
      'No relays configured. Add relays in Settings → Nostr Relays.';

  @override
  String get nostrBackupChecking => 'Checking…';

  @override
  String get nostrBackupPublishing => 'Publishing…';

  @override
  String get nostrBackupDelete => 'Delete Backup';

  @override
  String get nostrBackupDeleting => 'Deleting…';

  @override
  String get nostrBackupDeleted => 'Backup deleted from relay';

  @override
  String get nostrBackupDeleteConfirm =>
      'Replace the backup on this relay with an empty event? The descriptor will no longer be recoverable from this relay.';

  @override
  String get walletCreateFromNostr => 'Restore from Nostr';

  @override
  String get walletCreateFromNostrSub =>
      'Recover a descriptor backup from Nostr relays';

  @override
  String get nostrRestoreTitle => 'Restore from Nostr';

  @override
  String get nostrRestoreEnterXpub => 'Enter any xpub from the wallet';

  @override
  String get nostrRestoreXpubHint => 'xpub6... or [mfp/path]xpub...';

  @override
  String get nostrRestoreSearch => 'Search Relays';

  @override
  String get nostrRestoreSearching => 'Searching relays…';

  @override
  String get nostrRestoreNotFound => 'No backup found on configured relays';

  @override
  String get nostrRestoreFound => 'Backup found';

  @override
  String get nostrRestoreWalletName => 'Wallet name';

  @override
  String get nostrRestoreNetwork => 'Network';

  @override
  String get nostrRestoreDate => 'Backed up';

  @override
  String get nostrRestoreEnterCredential => 'Enter your xpub to decrypt';

  @override
  String get nostrRestoreImport => 'Import Wallet';

  @override
  String get nostrRestoreImporting => 'Importing wallet…';

  @override
  String get nostrRestoreWatchOnlyNote =>
      'The wallet will be imported as watch-only. Reconnect your hardware wallet or add your mnemonic to sign transactions.';

  @override
  String get recoverWalletTitle => 'Recover Wallet';

  @override
  String get restoreTabXpub => 'xpub';

  @override
  String get restoreTabSeed => 'Seed';

  @override
  String get restoreTabHardware => 'Hardware';

  @override
  String get restoreXpubEnterXpub =>
      'Enter an extended public key to scan on-chain accounts and search Nostr backups.';

  @override
  String get restoreXpubScanButton => 'Scan';

  @override
  String get restoreDefaults => 'Restore defaults';

  @override
  String get coinSortLabelSize => 'Size';

  @override
  String get coinSortLabelAge => 'Age';

  @override
  String get coinSortSizeDesc => 'Size: largest first';

  @override
  String get coinSortSizeAsc => 'Size: smallest first';

  @override
  String get coinSortAgeDesc => 'Age: oldest first';

  @override
  String get coinSortAgeAsc => 'Age: newest first';

  @override
  String get reorderWallets => 'Reorder wallets';

  @override
  String get reorderProjects => 'Reorder projects';

  @override
  String get done => 'Done';

  @override
  String get descriptorSigsTitle => 'Descriptor Signatures';

  @override
  String get descriptorSigsSubtitle =>
      'Prove ownership of each key by signing the descriptor hash. Protects backups from tampering.';

  @override
  String descriptorSigsSigned(String date) {
    return 'Signed · $date';
  }

  @override
  String get descriptorSigsNotSigned => 'Not signed';

  @override
  String get descriptorSigsInvalid => 'Invalid signature';

  @override
  String get descriptorSigsSignAction => 'Sign';

  @override
  String get descriptorSigsDeleteAction => 'Delete signature';

  @override
  String get descriptorSigsMethodHotKey => 'HotKey (automatic)';

  @override
  String get descriptorSigsMethodBB02 => 'BitBox02';

  @override
  String get descriptorSigsMethodQRMessage => 'QR — Message signing';

  @override
  String get descriptorSigsMethodQRBip322 => 'QR — BIP322 PSBT';

  @override
  String get descriptorSigsVerifyAll => 'Verify all';

  @override
  String get descriptorSigsConnectHw => 'Connect hardware wallet';

  @override
  String descriptorSigsSummary(int signed, int total) {
    return '$signed/$total keys signed';
  }

  @override
  String get descriptorSigsManage => 'Manage signatures';

  @override
  String get descriptorSigsMessage => 'Message to sign';

  @override
  String get descriptorSigsQRMessageHint =>
      'Base64 compact signature (65 bytes)';

  @override
  String get descriptorSigsShowPsbtQr =>
      'Show PSBT QR (scan with hardware wallet)';

  @override
  String get descriptorSigsQRBip322Hint => 'Signed PSBT (base64 or scan QR)';

  @override
  String get descriptorSigsSignSuccess => 'Signature stored';

  @override
  String get descriptorSigsDeleteSuccess => 'Signature deleted';

  @override
  String get descriptorSigsChooseMethod => 'Choose signing method';

  @override
  String descriptorSigsVerified(String date) {
    return 'Verified · $date';
  }

  @override
  String descriptorSigsVerifyResult(int valid, int total) {
    return '$valid of $total signatures valid';
  }

  @override
  String get deriveKeyFirst => 'Derive the key first';

  @override
  String get invalidDerivedKeyspec => 'Invalid derived keyspec';

  @override
  String get enterValidSeedPhrase => 'Enter a valid seed phrase first';

  @override
  String get enterXprvKey => 'Enter an xprv key';

  @override
  String signingKeyAdded(String mfp) {
    return 'Signing key added ($mfp)';
  }

  @override
  String mfpMismatch(String mfp, String expected) {
    return 'MFP mismatch: got $mfp, expected $expected';
  }

  @override
  String wrongKeyMfp(String mfp, String expected) {
    return 'Wrong key. Got $mfp, expected $expected';
  }

  @override
  String get derivedKeyspecLabel => 'Derived keyspec';

  @override
  String mustMatchMfp(String mfp) {
    return 'Must match MFP: $mfp';
  }

  @override
  String keyWithMfp(String mfp) {
    return 'Key: $mfp';
  }

  @override
  String loadWarningCorruptKeys(int count) {
    return 'Lost $count signing key(s) due to database corruption';
  }

  @override
  String get onChainBackupTitle => 'On-chain';

  @override
  String get onChainBackupSubtitle =>
      'Descriptor backup embedded in a Bitcoin transaction';

  @override
  String get onChainBackupSecurityNote =>
      'Descriptor backed up to Bitcoin Signet. Recoverable from any cosigner\'s xpub.';

  @override
  String onChainBackupParticipants(int count) {
    return '$count cosigner(s)';
  }

  @override
  String onChainBackupAnchors(int count, int amount) {
    return 'Anchors: $count × $amount sats';
  }

  @override
  String onChainBackupEstimatedFee(int fee) {
    return 'Estimated fee: $fee sats';
  }

  @override
  String onChainBackupTotalCost(int cost) {
    return 'Total cost: ~$cost sats';
  }

  @override
  String get onChainBackupScanUtxos => 'Scan UTXOs';

  @override
  String get onChainBackupScanning => 'Preparing backup…';

  @override
  String get onChainBackupSelectUtxo => 'Select UTXO';

  @override
  String get noUtxosAvailable => 'No UTXOs available';

  @override
  String get onChainBackupFeeRate => 'Fee rate (sats/vB)';

  @override
  String onChainBackupTxFees(int total, int vb) {
    return 'Fee: $total sats · $vb vB';
  }

  @override
  String onChainBackupMinUtxo(Object sats) {
    return 'Min UTXO: $sats sats';
  }

  @override
  String onChainBackupChange(Object sats) {
    return 'Change: $sats sats';
  }

  @override
  String onChainBackupVault(Object sats) {
    return 'Vault: $sats sats';
  }

  @override
  String onChainBackupUtxoInsufficient(int sats) {
    return 'Select a coin with at least $sats sats';
  }

  @override
  String get onChainBackupConfirmBuild => 'Build TX_COMMIT';

  @override
  String get onChainBackupTimelockedUtxo =>
      'Some selected UTXOs are still timelocked and cannot be spent yet.';

  @override
  String get onChainBackupSignWithHotKey => 'Sign with hot key';

  @override
  String get onChainBackupPublish => 'Backup on-chain';

  @override
  String get onChainBackupPublishing => 'Signing…';

  @override
  String get onChainBackupChecking => 'Checking…';

  @override
  String get onChainBackupExists => 'Backup already exists';

  @override
  String get onChainBackupSuccess => 'Descriptor backed up on-chain';

  @override
  String get onChainBackupCommitTx => 'TX_COMMIT';

  @override
  String get onChainBackupRevealTx => 'TX_REVEAL';

  @override
  String get onChainBackupNoHotKey =>
      'No signing key found. Add a hot key to this wallet before backing up on-chain.';

  @override
  String get onChainBackupSignCommit => 'Sign TX_COMMIT';

  @override
  String get onChainBackupSignCommitHint =>
      'Sign the commit transaction with your hardware wallet or QR device, then import the signed PSBT.';

  @override
  String get onChainBackupBuildingPsbt => 'Building PSBT…';

  @override
  String get onChainBackupFinalizing => 'Finalizing…';

  @override
  String get onChainBackupExportPsbt => 'Export PSBT';

  @override
  String get onChainBackupImportSigned => 'Import signed';

  @override
  String get onChainBackupSignWithHw => 'Sign with HW';

  @override
  String get onChainBackupConfirmBroadcastTitle => 'Confirm broadcast';

  @override
  String onChainBackupCommitFee(String sats) {
    return 'Fee: $sats sats';
  }

  @override
  String onChainBackupRevealFee(String sats) {
    return 'Fee: $sats sats';
  }

  @override
  String onChainBackupRevealChange(Object sats) {
    return 'Change: $sats sats';
  }

  @override
  String get onChainBackupBroadcast => 'Broadcast';

  @override
  String onChainBackupAnchorsHealth(int reachable, int total) {
    return '$reachable of $total anchors accessible';
  }

  @override
  String get onChainBackupDescriptorVerified => 'Descriptor verified';

  @override
  String get onChainBackupRevealPending => 'TX_REVEAL not yet published';

  @override
  String get onChainBackupCreateNew => 'Create new backup';

  @override
  String get onChainSearchLabel => 'Search on-chain backups';

  @override
  String get onChainSearchHint =>
      'Scan Signet for descriptor backups published on-chain';

  @override
  String get onChainBadge => 'On-chain';
}
