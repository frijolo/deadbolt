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
  String get noProjects => 'No projects yet.\nTap + to create one.';

  @override
  String get deleteProjectTitle => 'Delete project';

  @override
  String deleteProjectConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get couldNotReadFile => 'Could not read file';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

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
  String get activeNetworkLabel => 'Active Network';

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
  String get biometricWalletUnlockReason => 'Authenticate to open wallet';

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
  String get copyKeyspecTooltip => 'Copy keyspec';

  @override
  String get keyCopied => 'Key copied';

  @override
  String get rootPath => '(root)';

  @override
  String get keyNameDialogTitle => 'Key name';

  @override
  String get keyFingerprintLabel => 'Fingerprint';

  @override
  String get keyDerivPathLabel => 'Derivation path';

  @override
  String get keyXpubLabel => 'Extended public key';

  @override
  String get removeKeyTooltip => 'Remove key from project';

  @override
  String get keyInUseTooltip => 'Key in use, cannot remove';

  @override
  String get hotKeyBadge => 'HOT';

  @override
  String get privateKeySection => 'Stored seed';

  @override
  String get viewPrivateKeyButton => 'View seed phrase';

  @override
  String get deletePrivateKeyButton => 'Delete stored seed';

  @override
  String get viewPrivateKeyDisclaimer =>
      'Make sure no one can see your screen. Your seed phrase gives full access to your funds.';

  @override
  String get deletePrivateKeyDisclaimer =>
      'This deletes the seed phrase stored in this project. If you don\'t have a backup, you will permanently lose access to this key. The public key will remain in the project as watch-only.';

  @override
  String get deleteWalletPrivateKeyDisclaimer =>
      'This removes the signing key from this wallet. You will no longer be able to sign transactions with it.';

  @override
  String get viewPrivateKeyConfirm => 'Show seed';

  @override
  String get deletePrivateKeyConfirm => 'Delete seed';

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
  String get renameWalletMenu => 'Rename wallet';

  @override
  String get renameWalletTitle => 'Rename wallet';

  @override
  String walletRenamedToast(String name) {
    return 'Renamed to \"$name\"';
  }

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
  String get txId => 'TXID';

  @override
  String get loadMore => 'Load more';

  @override
  String get txDelayBroadcastSection => 'Delay broadcast (nLockTime)';

  @override
  String get txDelayDays => 'Days';

  @override
  String get txDelayHours => 'Hours';

  @override
  String get txDelayMinutes => 'Minutes';

  @override
  String get txDelayNoneHint =>
      'Set days / hours / minutes to delay broadcast.';

  @override
  String txDelayApproxBlocks(int blocks) {
    return '≈ $blocks blocks';
  }

  @override
  String txDelayUnlockEta(int height, String eta) {
    return 'unlock at block $height (~$eta)';
  }

  @override
  String psbtLockedMaturity(int blocks) {
    return 'Locked · $blocks blocks';
  }

  @override
  String psbtLockedTooltip(String eta, int blocks) {
    return 'Locked · $eta ($blocks blocks left)';
  }

  @override
  String get psbtBroadcastReady => 'Ready to broadcast';

  @override
  String get electrumSectionTitle => 'Electrum Servers';

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
  String get spendPathUnlocked => 'Unlocked';

  @override
  String get spendPathLocked => 'Locked';

  @override
  String spendPathBlocks(int blocks) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return '$blocksString blocks';
  }

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
  String get psbtStatusSpent => 'SPENT';

  @override
  String get psbtSpentInputsWarning =>
      'One or more inputs have been confirmed spent by another transaction. This PSBT can no longer be broadcast.';

  @override
  String get createTxTitle => 'Create Transaction';

  @override
  String get createTxRecipientHint => 'bc1q...';

  @override
  String get createTxAmount => 'Amount (sats)';

  @override
  String get createTxFeeRate => 'Fee rate (sat/vB)';

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
  String get createTxButton => 'Create PSBT';

  @override
  String get createTxAmountRequired => 'Amount is required';

  @override
  String get createTxAmountInvalid => 'Invalid amount';

  @override
  String get createTxMaxButton => 'MAX';

  @override
  String get createTxMyWalletsButton => 'MY WALLETS';

  @override
  String get createTxSelectDestWallet => 'Select destination wallet';

  @override
  String get createTxThisWallet => 'This wallet (Self)';

  @override
  String get createTxNoUnusedAddress => 'No unused receive address available';

  @override
  String get createTxNoSpendPaths =>
      'No spend paths available. Sync the wallet first.';

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
  String get psbtBroadcastButton => 'Broadcast';

  @override
  String psbtBroadcastSuccess(String txid) {
    return 'Transaction broadcast! TXID: $txid';
  }

  @override
  String get psbtAutoBroadcastSwitch => 'Broadcast automatically when unlocked';

  @override
  String get psbtAutoBroadcastHint =>
      'The wallet must stay unlocked. Broadcast will be attempted after every sync once the timelock matures.';

  @override
  String get psbtAutoBroadcastQueuedTooltip => 'Queued for automatic broadcast';

  @override
  String psbtAutoBroadcastedToast(String txid) {
    return 'Auto-broadcasted: $txid';
  }

  @override
  String psbtAutoBroadcastFailedToast(int id, String error) {
    return 'Auto-broadcast failed for PSBT $id: $error';
  }

  @override
  String get psbtDeleteTitle => 'Delete PSBT';

  @override
  String get psbtDeleteConfirm => 'Delete this unsigned transaction?';

  @override
  String get coinSelectDone => 'Done';

  @override
  String get createTxTotalFee => 'Fee (sats)';

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
  String get coinSelectorSearchHint => 'Search';

  @override
  String get coinSelectorNoCoinsSelected => 'Tap to select coins...';

  @override
  String coinSelectorDoneCount(int count) {
    return 'Done ($count)';
  }

  @override
  String get relatedCoins => 'Related coins';

  @override
  String get relatedAddresses => 'Output addresses';

  @override
  String get inputAddresses => 'Input addresses';

  @override
  String get relatedTransactions => 'Related transactions';

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
      'Restore a wallet from a .deadbolt or .bed file';

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
  String get bedExportOption => 'BED backup';

  @override
  String get bedExportColocationWarning =>
      'Decryptable with any xpub in this wallet — never store it next to one.';

  @override
  String get bedExportWarningTitle => 'Before you export';

  @override
  String get bedExportWarningContinue => 'Export';

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
  String get inheritanceDuplicateTimelockTitle => 'Duplicate timelocks';

  @override
  String get inheritanceDuplicateTimelockBody =>
      'Two or more heirs share the same timelock. For better compatibility with other coordination software, each spending path should have a unique timelock.';

  @override
  String get inheritanceDuplicateTimelockFix => 'Fix automatically';

  @override
  String get inheritanceDuplicateTimelockContinue => 'Continue anyway';

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
  String get blocksUnit => 'blocks';

  @override
  String inheritanceHeirN(int n) {
    return 'Heir $n';
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
  String get hwCompareCodeOnDevice =>
      'Compare this code with your device screen and confirm:';

  @override
  String get hwSignTransactionButton => 'Sign transaction';

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
  String get scanAccountsNoActivitySubtitle =>
      'Recover accounts from a mnemonic phrase';

  @override
  String get hwDiscoveryNoDevice =>
      'No hardware wallet connected. Connect and pair your device first.';

  @override
  String get hwDiscoveryStart => 'Scan accounts';

  @override
  String hwDiscoveryDeriving(int n, int total) {
    return 'Exporting xpubs… ($n/$total)';
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
  String addPrivateKeyMatchedKey(String label) {
    return 'Will be attached to: $label';
  }

  @override
  String addPrivateKeyAlreadyHot(String label) {
    return '$label already has a private key stored';
  }

  @override
  String addPrivateKeyNoMatch(String mfp) {
    return 'Fingerprint $mfp does not belong to any key in this wallet';
  }

  @override
  String attachPrivateKeyConfirmMessage(String label) {
    return 'This seed matches the existing key \"$label\". Attach it as a private key?';
  }

  @override
  String get attachPrivateKeyConfirmAction => 'Attach';

  @override
  String get editKeyTitle => 'Edit key';

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
  String get nostrRelayTimeoutLabel => 'Timeout (seconds)';

  @override
  String get nostrRelayMaxAttemptsLabel => 'Attempts per relay';

  @override
  String get nostrSearchNetworkWarning =>
      'Connection issues with some Nostr relays. Some backups may not have been found.';

  @override
  String get publishBackupMenu => 'Publish Descriptor';

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
  String get nostrBackupNoRelays =>
      'No relays configured. Add relays in Settings → Nostr Relays.';

  @override
  String get nostrBackupChecking => 'Checking…';

  @override
  String get nostrBackupPublishing => 'Publishing…';

  @override
  String get nostrBackupDelete => 'Delete Backup';

  @override
  String get nostrBackupDeleted => 'Backup deleted from relay';

  @override
  String get nostrBackupDeleteConfirm =>
      'Replace the backup on this relay with an empty event? The descriptor will no longer be recoverable from this relay.';

  @override
  String get nostrRestoreXpubHint => 'xpub6... or [mfp/path]xpub...';

  @override
  String get nostrRestoreFound => 'Backup found';

  @override
  String get nostrRestoreImport => 'Import Wallet';

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
  String get descriptorSigsMessage => 'Message to sign';

  @override
  String get descriptorSigsQRMessageHint =>
      'Base64 compact signature (65 bytes)';

  @override
  String get descriptorSigsQRBip322Hint => 'Signed PSBT (base64 or scan QR)';

  @override
  String get descriptorSigsSignSuccess => 'Signature stored';

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
  String hwDeviceNotRegisteredForWallet(String mfp) {
    return 'This device ($mfp) is not registered for this wallet.';
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
  String get onChainBackupTitle => 'On-chain';

  @override
  String get onChainBackupSubtitle =>
      'Descriptor backup embedded in a Bitcoin transaction';

  @override
  String get onChainBackupSecurityNote =>
      'Descriptor backed up on-chain. Recoverable from any cosigner\'s xpub.';

  @override
  String onChainBackupAnchors(int count, int amount) {
    return 'Anchors: $count × $amount sats';
  }

  @override
  String get onChainBackupScanning => 'Preparing backup…';

  @override
  String get noUtxosAvailable => 'No UTXOs available';

  @override
  String get onChainBackupFeeRate => 'Fee rate (sats/vB)';

  @override
  String onChainBackupTxFees(int total, int vb) {
    return 'Fee: $total sats · $vb vB';
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

  @override
  String get generateMnemonicStep1Title => 'Generate';

  @override
  String get generateMnemonicStep2Title => 'Verify backup';

  @override
  String get generateMnemonicStep3Title => 'Configure key';

  @override
  String get generateMnemonicLengthLabel => 'Length';

  @override
  String get generateMnemonicLength12 => '12 words';

  @override
  String get generateMnemonicLength24 => '24 words';

  @override
  String get generateMnemonicGenerateButton => 'Generate mnemonic';

  @override
  String get generateMnemonicRegenerate => 'Regenerate';

  @override
  String get generateMnemonicWarning =>
      'Write these words down on paper, in order. They will not be shown again. Anyone with access to them can spend your bitcoin.';

  @override
  String get generateMnemonicBackupDone => 'I have written them down';

  @override
  String get generateMnemonicVerifyIntro =>
      'Type each word in the position requested. All positions must match before you can continue.';

  @override
  String generateMnemonicVerifyWordLabel(int pos) {
    return 'Word #$pos';
  }

  @override
  String get generateMnemonicVerifyError =>
      'Some words do not match. Check your notes and try again.';

  @override
  String get generateMnemonicShuffleAgain => 'Shuffle order again';

  @override
  String get generateMnemonicContinue => 'Continue';

  @override
  String get generateMnemonicDone => 'Add key';

  @override
  String get addKeyCapacityWatchOnlyTitle => 'Watch-only key';

  @override
  String get addKeyCapacityWatchOnlySubtitle =>
      'An xpub you can monitor but not sign with.';

  @override
  String get addKeyCapacityHotTitle => 'Hot key';

  @override
  String get addKeyCapacityHotSubtitle =>
      'Holds the seed on this device so it can sign.';

  @override
  String get addKeyWatchSourcePasteTitle => 'Enter manually';

  @override
  String get addKeyWatchSourcePasteSubtitle => 'From clipboard or typed in.';

  @override
  String get addKeyManualDialogTitle => 'Enter key';

  @override
  String get addKeyManualHint =>
      '[mfp/path]xpub\n\nor one line per field:\nmfp\nm/path\nxpub';

  @override
  String get addKeyManualFormatError =>
      'Format not recognized. Paste a [mfp/path]xpub keyspec or three lines (mfp, path, xpub).';

  @override
  String get addKeyWatchSourceScanTitle => 'Scan QR';

  @override
  String get addKeyWatchSourceScanSubtitle =>
      'Read a keyspec QR code with the camera.';

  @override
  String get addKeyWatchSourceFileTitle => 'Load file';

  @override
  String get addKeyWatchSourceFileSubtitle =>
      'Open a text/JSON file with the keyspec.';

  @override
  String get addKeyWatchSourceHwTitle => 'Hardware wallet';

  @override
  String get addKeyWatchSourceHwSubtitle =>
      'Export xpub from a BitBox02 or compatible device.';

  @override
  String get addKeyHotSourceGenerateTitle => 'Generate new mnemonic';

  @override
  String get addKeyHotSourceGenerateSubtitle =>
      'Create a fresh seed and verify the backup.';

  @override
  String get addKeyHotSourceExistingTitle => 'Enter existing mnemonic';

  @override
  String get addKeyHotSourceExistingSubtitle =>
      'Type or scan a 12/24-word seed.';

  @override
  String get addKeyHotSourceXprvTitle => 'Enter xprv';

  @override
  String get addKeyHotSourceXprvSubtitle => 'Paste a master xprv (depth 0).';

  @override
  String get txPlanningTitle => 'Migrate UTXOs';

  @override
  String get txPlanningMenuEntry => 'Migrate UTXOs…';

  @override
  String get txPlanningIdleDescription =>
      'Move every confirmed UTXO to fresh addresses spaced over time. Each transaction gets its own random feerate and nLockTime so auto-broadcast emits them as their timelock matures.';

  @override
  String get txPlanningComputeButton => 'Compute plan';

  @override
  String txPlanningLastPlanTitle(String status) {
    return 'Last plan: $status';
  }

  @override
  String txPlanningLastPlanSubtitle(int id, String kind) {
    return 'Plan #$id, $kind';
  }

  @override
  String get txPlanningWalletNotLoaded => 'Wallet not loaded';

  @override
  String get txPlanningNoConfirmedUtxos => 'No confirmed UTXOs to plan';

  @override
  String txPlanningTooFewAddresses(int needed) {
    return 'Wallet has too few revealed addresses ($needed needed). Generate more on the Receive screen first.';
  }

  @override
  String get txPlanningInvalidFeeRate => 'Invalid fee rate';

  @override
  String get txPlanningFeeRateOrder => 'Min fee must be ≤ max fee';

  @override
  String get txPlanningInvalidDelay => 'Invalid spacing';

  @override
  String get txPlanningDelayOrder => 'Min spacing must be ≤ max spacing';

  @override
  String get txPlanningInvalidSplitProbability => 'Invalid split probability';

  @override
  String get txPlanningInvalidMinOutput => 'Invalid min output';

  @override
  String txPlanningPlanHeader(int id, String kind) {
    return 'Plan #$id · $kind';
  }

  @override
  String txPlanningTxCountFee(int count, String fee) {
    return '$count transactions · total fee $fee sats';
  }

  @override
  String get txPlanningSummaryCoins => 'Coins to transfer';

  @override
  String get txPlanningSummaryTotalAmount => 'Total amount';

  @override
  String get txPlanningSummaryTotalFee => 'Total fees';

  @override
  String get txPlanningSummarySigned => 'Signed';

  @override
  String txPlanningSignersTitle(int signed, int threshold) {
    return 'Signatures: $signed of $threshold';
  }

  @override
  String txPlanningSignedRatio(int signed, int total) {
    return '$signed / $total signed';
  }

  @override
  String txPlanningUnsignedRemaining(int count) {
    return '$count transactions still need signatures.';
  }

  @override
  String get txPlanningCommitButton => 'Commit';

  @override
  String get txPlanningCancelDialogTitle => 'Cancel plan?';

  @override
  String get txPlanningCancelDialogBody =>
      'Every child PSBT will be deleted.\n\nAny signatures collected so far will be lost.';

  @override
  String get txPlanningKeepButton => 'Keep plan';

  @override
  String txPlanningTxRowTitle(String outpoint) {
    return 'Tx for $outpoint';
  }

  @override
  String txPlanningTxRowSubtitle(String amount, String fee, int block) {
    return '$amount sats in · $fee fee · matures at block $block';
  }

  @override
  String txPlanningRunningHeader(int id) {
    return 'Plan #$id · running';
  }

  @override
  String txPlanningRunningSubtitle(int count) {
    return '$count transactions pending. Auto-broadcast fires as each timelock matures.';
  }

  @override
  String get txPlanningJustBroadcast => 'Just broadcast';

  @override
  String get txPlanningStopDialogTitle => 'Stop plan?';

  @override
  String get txPlanningStopDialogBody =>
      'Pending transactions will be discarded.\n\nAnything already broadcast stays on chain.';

  @override
  String get txPlanningKeepRunningButton => 'Keep running';

  @override
  String get txPlanningRowInputsSpent => 'Inputs spent';

  @override
  String txPlanningRowArmed(int block) {
    return 'Broadcasts at block $block';
  }

  @override
  String txPlanningRowArmedEta(String datetime, int blocks) {
    return '$datetime ($blocks blocks left)';
  }

  @override
  String get txPlanningRowIdle => 'Idle';

  @override
  String txPlanningRowAmountTitle(int amount, int id) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '$amountString sats · #$id';
  }

  @override
  String get txPlanningTerminalDone => 'Plan complete';

  @override
  String get txPlanningTerminalCancelled => 'Plan cancelled';

  @override
  String get txPlanningTerminalFailed => 'Plan failed';

  @override
  String txPlanningTerminalGeneric(String status) {
    return 'Plan $status';
  }

  @override
  String get txPlanningNewPlanButton => 'New plan';

  @override
  String get txPlanningBannerDraftTitle => 'Plan ready to sign';

  @override
  String txPlanningBannerDraftSubtitle(int count, int id) {
    return '$count transactions queued · plan #$id';
  }

  @override
  String get txPlanningBannerRunningTitle => 'Plan running';

  @override
  String txPlanningBannerRunningSubtitle(int count) {
    return '$count pending · auto-broadcast on maturity';
  }

  @override
  String get txPlanningReservedBadge => 'Plan';

  @override
  String txPlanningReservedBalance(String value) {
    return 'Planned $value';
  }

  @override
  String get txPlanningConfigTitle => 'Configuration';

  @override
  String get txPlanningDestinationLabel => 'Destination';

  @override
  String get txPlanningDestinationSelf => 'Same wallet (refresh)';

  @override
  String txPlanningDestinationWallet(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get txPlanningSelectCoins => 'Select coins';

  @override
  String txPlanningCoinsSelected(String count) {
    return '$count coins selected';
  }

  @override
  String get txPlanningAllCoins => 'All coins';

  @override
  String get txPlanningSpendPathLabel => 'Spend path';

  @override
  String get txPlanningFeeRateMinLabel => 'Min fee (sat/vB)';

  @override
  String get txPlanningFeeRateMaxLabel => 'Max fee (sat/vB)';

  @override
  String get txPlanningDelayMinLabel => 'Min spacing (blocks)';

  @override
  String get txPlanningDelayMaxLabel => 'Max spacing (blocks)';

  @override
  String get txPlanningSpacingHelper =>
      'Blocks between consecutive transactions. Larger ranges mean more privacy and a longer overall migration.';

  @override
  String txPlanningEtaPreview(
    int count,
    int minBlocks,
    int maxBlocks,
    String minWindow,
    String maxWindow,
  ) {
    return 'Estimated duration: $minBlocks–$maxBlocks blocks (~$minWindow–$maxWindow) for $count transactions';
  }

  @override
  String txPlanningEtaHours(int hours) {
    return '$hours h';
  }

  @override
  String txPlanningEtaDays(int days) {
    return '$days d';
  }

  @override
  String get txPlanningSplitProbabilityLabel => 'Split probability';

  @override
  String get txPlanningMinOutputLabel => 'Min output (sats)';

  @override
  String txPlanningFeeRange(String min, String max) {
    return '$min – $max sat/vB';
  }

  @override
  String txPlanningDelayRange(String min, String max) {
    return '$min – $max blocks';
  }

  @override
  String get txPlanningComputePlanButton => 'Compute plan';

  @override
  String get txPlanningMigrate => 'migrate';

  @override
  String get txPlanningRefresh => 'refresh';

  @override
  String get txPlanningSignAllButton => 'Sign all…';

  @override
  String get txPlanningCommitArmButton => 'Broadcast';

  @override
  String get txPlanningSignerPickerTitle => 'Choose signer';

  @override
  String txPlanningSignerHotKey(String mfp) {
    return 'Hot key ($mfp)';
  }

  @override
  String get txPlanningSignerHotKeySubtitle =>
      'Sign every PSBT in-app with this stored key';

  @override
  String get txPlanningSignerHw => 'Hardware wallet';

  @override
  String get txPlanningSignerHwSubtitle =>
      'Sign every PSBT on the device, one tap per tx';

  @override
  String get txPlanningSignerQr => 'Offline signer (QR)';

  @override
  String get txPlanningSignerQrSubtitle =>
      'Export every PSBT as animated QR, scan signed back';

  @override
  String get txPlanningSignerComingSoon => 'Coming soon';

  @override
  String get txPlanningSignerNoHotKeys =>
      'No hot keys available on this wallet.';

  @override
  String txPlanningConfirmBatchTitle(int count) {
    return 'Sign $count transactions?';
  }

  @override
  String txPlanningConfirmBatchBody(String fee, String signer) {
    return 'Total fee $fee sats · signer: $signer.\n\nThe batch never asks twice — the next prompt will be the broadcast confirmation.';
  }

  @override
  String txPlanningBatchFailures(int count) {
    return '$count signing errors — review the failed rows.';
  }

  @override
  String get txPlanningBadgeSigned => 'Signed';

  @override
  String txPlanningBadgePartial(int signed, int threshold) {
    return 'Partial ($signed/$threshold)';
  }

  @override
  String get txPlanningBadgeUnsigned => 'Unsigned';

  @override
  String get txPlanningBadgeFailed => 'Error';

  @override
  String get txPlanningHwBatchTitle => 'Sign batch with hardware wallet';

  @override
  String txPlanningHwBatchReady(int count) {
    return 'Ready to sign $count transactions';
  }

  @override
  String get txPlanningHwBatchStartButton => 'Start signing';

  @override
  String txPlanningHwBatchProgress(int current, int total) {
    return 'Signing $current of $total…';
  }

  @override
  String get txPlanningHwBatchApplying => 'Merging signatures…';

  @override
  String txPlanningHwBatchRetryButton(int current) {
    return 'Retry transaction $current';
  }

  @override
  String txPlanningHwBatchFinishEarlyButton(int signed) {
    return 'Finish with $signed signed';
  }

  @override
  String get txPlanningSignMfpTitle => 'Sign with this key';

  @override
  String get txPlanningSignerHotKeyOption => 'Hot key';

  @override
  String txPlanningHwBatchWrongDevice(String mfp) {
    return 'This hardware wallet ($mfp) is not part of the plan\'s signing keys.';
  }

  @override
  String get txPlanningHwBatchAllSigned =>
      'This key has already signed every transaction in the plan.';

  @override
  String get txPlanningQrSignTitle => 'Sign batch via QR';

  @override
  String txPlanningQrSignCurrent(int current, int total) {
    return 'Transaction $current of $total';
  }

  @override
  String get txPlanningQrSignHint =>
      'Scan this QR on your offline signer, then tap “Scan signature” to capture the signed PSBT.';

  @override
  String get txPlanningQrSignScanButton => 'Scan signature';

  @override
  String get txPlanningQrSignMismatchToast =>
      'The scanned signature does not match this transaction.';

  @override
  String get txPlanningQrSignNoNewSigToast =>
      'The scanned PSBT did not add any new signature.';

  @override
  String get txPlanningQrSignAllDone => 'Batch fully signed.';

  @override
  String txPlanningConfirmCommitTitle(int count) {
    return 'Broadcast $count transactions?';
  }

  @override
  String txPlanningConfirmCommitBody(
    String fee,
    String earliest,
    String latest,
  ) {
    return 'Total fee $fee sats.\n\nFirst broadcast around $earliest, last around $latest.\n\nEach transaction emits automatically when its timelock matures.';
  }

  @override
  String txPlanningConfirmCommitBodyTipUnknown(String fee) {
    return 'Total fee $fee sats.\n\nBroadcast windows depend on the chain tip (not yet synced).\n\nEach transaction emits automatically when its timelock matures.';
  }

  @override
  String get txPlanningCommitConfirmButton => 'Broadcast';

  @override
  String get batteryOptBannerTitle => 'Improve background broadcasting';

  @override
  String get batteryOptBannerBody =>
      'Android may delay or skip scheduled broadcasts when Deadbolt is in the background. Exclude the app from battery optimization for reliable auto-broadcast.';

  @override
  String get batteryOptBannerAction => 'Open settings';

  @override
  String get batteryOptBannerDismiss => 'Not now';

  @override
  String get settingsSectionBackground => 'Background';

  @override
  String get batteryOptTileTitle => 'Battery optimization';

  @override
  String get batteryOptTileExempt =>
      'Allowed — background broadcasts will run reliably.';

  @override
  String get batteryOptTileRestricted =>
      'Restricted — Android may delay or skip background broadcasts.';
}
