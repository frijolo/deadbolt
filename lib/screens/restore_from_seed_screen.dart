import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/simple_wallet_dialog.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet/discovery.dart' as rust_discovery;
import 'package:deadbolt/src/rust/api/wallet/nostr_backup.dart' as rust_nostr;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart' show KeyspecResult, kKeyspecPattern;
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/mnemonic_entry_field.dart';
import 'package:deadbolt/widgets/network_dropdown_field.dart';

enum _ScanState { idle, scanning, done, error }

class RestoreFromSeedScreen extends StatefulWidget {
  const RestoreFromSeedScreen({super.key});

  static Future<void> push(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RestoreFromSeedScreen()),
      );

  @override
  State<RestoreFromSeedScreen> createState() => _RestoreFromSeedScreenState();
}

class _RestoreFromSeedScreenState extends State<RestoreFromSeedScreen> {
  final _mnemonicController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _showPassphrase = false;

  late APINetwork _selectedNetwork;
  _ScriptType? _scriptFilter;

  int _accountGapLimit = 20;
  int _addressGapLimit = 20;
  bool _nonStandardPaths = false;
  bool _searchNostr = true;

  _ScanState _scanState = _ScanState.idle;
  String? _errorMessage;
  List<APIAccountInfo> _accounts = [];
  int _totalScanned = 0;
  Map<String, APIWalletInfo> _walletByFirstAddress = {};
  List<_NostrFoundBackup> _nostrFoundBackups = [];

  /// Unified list for display: on-chain accounts that DON'T have a Nostr match
  /// combined with Nostr backups that DON'T have a chain match.
  /// Items with chain match are already shown in the on-chain list.
  List<({String? firstAddress, String? walletName, String? derivationPath, APIWalletType? walletType, int? txCount, BigInt? balanceSat, bool hasNostrBackup})> _unifiedWallets = [];

  @override
  void initState() {
    super.initState();
    _selectedNetwork = context.read<SettingsCubit>().state.network;
  }

  @override
  void dispose() {
    _mnemonicController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  String get _electrumUrl =>
      context.read<SettingsCubit>().state.electrumUrlForNetwork(_selectedNetwork);

  static APIWalletType _toWalletType(_ScriptType t) => switch (t) {
        _ScriptType.legacy => APIWalletType.p2Pkh,
        _ScriptType.nestedSegwit => APIWalletType.p2ShWpkh,
        _ScriptType.nativeSegwit => APIWalletType.p2Wpkh,
        _ScriptType.taproot => APIWalletType.p2Tr,
      };

  Future<void> _onScan() async {
    final mnemonic = _mnemonicController.text.trim();
    if (mnemonic.isEmpty) return;

    setState(() {
      _scanState = _ScanState.scanning;
      _errorMessage = null;
      _accounts = [];
      _totalScanned = 0;
      _nostrFoundBackups = [];
    });

    final passphrase =
        _passphraseController.text.isEmpty ? null : _passphraseController.text;
    final url = _electrumUrl;

    final types =
        _scriptFilter != null ? [_scriptFilter!] : _ScriptType.values;

    try {
      final futures = types.map((t) => rust_discovery.discoverAccounts(
            mnemonic: mnemonic,
            passphrase: passphrase,
            walletType: _toWalletType(t),
            network: _selectedNetwork,
            electrumUrl: url,
            accountGapLimit: _accountGapLimit,
            addressGapLimit: _addressGapLimit,
            nonStandardPaths: _nonStandardPaths,
          ));

      final (results, walletByFirstAddress) = await (
        Future.wait(futures),
        _buildWalletByAddress(),
      ).wait;
      if (!mounted) return;

      final merged = results.expand((r) => r.accounts).toList();
      final totalScanned =
          results.map((r) => r.scannedCount).fold(0, (a, b) => a + b);

      List<_NostrFoundBackup> nostrBackups = [];
      if (_searchNostr) {
        nostrBackups = await _fetchNostrBackups(
          mnemonic: mnemonic,
          passphrase: passphrase,
        );
        if (!mounted) return;
      }

      setState(() {
        _accounts = merged;
        _totalScanned = totalScanned;
        _walletByFirstAddress = walletByFirstAddress;
        _nostrFoundBackups = nostrBackups;
        // Build unified list: ALL on-chain accounts (with hasNostrBackup flag)
        // + Nostr backups that don't have a chain match
        final nostrAddresses = {for (final b in nostrBackups) b.firstAddress};
        final mergedAddresses = {for (final a in merged) a.firstAddress};
        _unifiedWallets = [
          // All on-chain accounts, with flag indicating if they have Nostr backup
          ...merged.map((a) => (
                firstAddress: a.firstAddress,
                walletName: null,
                derivationPath: a.derivationPath,
                walletType: a.walletType,
                txCount: a.txCount,
                balanceSat: a.balanceSat,
                hasNostrBackup: nostrAddresses.contains(a.firstAddress),
              )),
          // Nostr-only backups (no chain data)
          ...nostrBackups.where((b) => !mergedAddresses.contains(b.firstAddress))
              .map((b) => (
                firstAddress: b.firstAddress,
                walletName: b.walletName,
                derivationPath: '',
                walletType: b.walletType,
                txCount: null,
                balanceSat: null,
                hasNostrBackup: true,
              )),
        ];
        _scanState = _ScanState.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _scanState = _ScanState.error;
      });
    }
  }

  Future<void> _openWizard(APIAccountInfo? account) async {
    final cubit = context.read<WalletListCubit>();
    final keyspec = account != null
        ? (
            keyspec: account.keyspec,
            mnemonic: _mnemonicController.text.trim(),
            passphrase: _passphraseController.text.isEmpty
                ? null
                : _passphraseController.text,
            xprv: null,
          ) as KeyspecResult
        : null;

    final walletPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SimpleWalletDialog(
          cubit: cubit,
          initialKeyspecs: keyspec != null ? [keyspec] : const [],
          initialNetwork: _selectedNetwork,
        ),
      ),
    );

    if (walletPath != null && mounted) {
      await _refreshWalletMap();
    }
  }

  Future<Map<String, APIWalletInfo>> _buildWalletByAddress() async {
    final wallets = switch (context.read<WalletListCubit>().state) {
      WalletListLoaded(:final wallets) =>
        wallets.where((w) => w.network == _selectedNetwork).toList(),
      _ => <APIWalletInfo>[],
    };
    final entries = await Future.wait(wallets.map((w) async {
      try {
        final addr = await rust_discovery.firstAddressFromDescriptor(
            descriptor: w.descriptor, network: _selectedNetwork);
        return MapEntry(addr, w);
      } catch (_) {
        return null;
      }
    }));
    return Map.fromEntries(entries.whereType<MapEntry<String, APIWalletInfo>>());
  }

  Future<void> _refreshWalletMap() async {
    final map = await _buildWalletByAddress();
    if (!mounted) return;
    setState(() => _walletByFirstAddress = map);
  }

  Future<List<_NostrFoundBackup>> _fetchNostrBackups({
    required String mnemonic,
    required String? passphrase,
  }) async {
    final relays = await NostrRelaySettings().loadRelays();
    if (relays.isEmpty) return [];

    final xpubs = await rust_discovery.deriveXpubsForNostr(
      mnemonic: mnemonic,
      passphrase: passphrase,
      network: _selectedNetwork,
      accountCount: _accountGapLimit,
    );

    final results = <_NostrFoundBackup>[];
    // Deduplicate by wallet_name; null-named backups are kept individually.
    final seenNames = <String>{};

    await Future.wait(xpubs.map((xpub) async {
      try {
        final responses = await rust_nostr.fetchNostrBackup(
          xpub: xpub,
          relayUrls: relays,
        );
        for (final resp in responses) {
          final byteList = resp.bytes.toList();
          final name = resp.walletName;
          if (name != null) {
            if (seenNames.contains(name)) continue;
            seenNames.add(name);
          }
          results.add(_NostrFoundBackup(
            xpub: xpub,
            bytes: byteList,
            walletName: name,
            network: resp.network,
            createdAt: resp.createdAt?.toInt(),
            firstAddress: resp.firstAddress,
            walletType: resp.walletType,
          ));
        }
      } catch (_) {
        // Not found or relay error — skip silently
      }
    }));

    results.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
    return results;
  }

  Future<void> _importFromNostr(List<int> bytes, String xpub) async {
    final service = context.read<WalletService>();
    final deviceKey = await service.getOrCreateEncryptionKey();
    final walletsDir = await service.getWalletsDir();
    try {
      final info = await rust_nostr.importNostrBackup(
        backupBytes: bytes,
        xpubCredential: xpub,
        deviceKeyHex: deviceKey,
        walletsDir: walletsDir,
      );
      if (!mounted) return;
      context.read<WalletListCubit>().refresh();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WalletDetailScreen(walletPath: info.walletPath),
          ),
        );
      }
    } catch (e) {
      if (mounted) showErrorToastException(context, e);
    }
  }

  void _openWallet(APIWalletInfo wallet) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalletDetailScreen(walletPath: wallet.walletPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.restoreFromSeedTitle)),
      body: SafeArea(
        child: switch (_scanState) {
          _ScanState.idle => _buildIdleBody(l10n),
          _ScanState.scanning => _buildScanningBody(l10n),
          _ScanState.done => _buildDoneBody(l10n),
          _ScanState.error => _buildErrorBody(l10n),
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Idle
  // ---------------------------------------------------------------------------

  Widget _buildIdleBody(AppLocalizations l10n) {
    return ListView(
      dragStartBehavior: DragStartBehavior.down,
      padding: const EdgeInsets.all(16),
      children: [
        MnemonicEntryField(controller: _mnemonicController),
        const SizedBox(height: 12),
        TextField(
          controller: _passphraseController,
          obscureText: !_showPassphrase,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: l10n.bip39PassphraseLabel,
            suffixIcon: IconButton(
              icon: Icon(
                  _showPassphrase ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _showPassphrase = !_showPassphrase),
            ),
          ),
        ),
        const SizedBox(height: 16),
        NetworkDropdownField(
          value: _selectedNetwork,
          onChanged: (n) => setState(() => _selectedNetwork = n),
        ),
        const SizedBox(height: 16),
        Text(l10n.scriptTypeLabel,
            style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_ScriptType?>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: null,
                  label: Text(l10n.scanTypeAll)),
              ButtonSegment(
                  value: _ScriptType.legacy,
                  label: Text(l10n.scriptTypeLegacy)),
              ButtonSegment(
                  value: _ScriptType.nestedSegwit,
                  label: Text(l10n.scriptTypeNested)),
              ButtonSegment(
                  value: _ScriptType.nativeSegwit,
                  label: Text(l10n.scriptTypeSegwit)),
              ButtonSegment(
                  value: _ScriptType.taproot,
                  label: Text(l10n.scriptTypeTaproot)),
            ],
            selected: {_scriptFilter},
            onSelectionChanged: (v) =>
                setState(() => _scriptFilter = v.first),
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: Text(l10n.advancedScanOptions),
          tilePadding: EdgeInsets.zero,
          children: [
            _buildGapStepper(
              label: l10n.accountGapLimitLabel,
              value: _accountGapLimit,
              onDecrement: _accountGapLimit > 1
                  ? () => setState(() => _accountGapLimit--)
                  : null,
              onIncrement: _accountGapLimit < 100
                  ? () => setState(() => _accountGapLimit++)
                  : null,
            ),
            _buildGapStepper(
              label: l10n.addressGapLimitLabel,
              value: _addressGapLimit,
              onDecrement: _addressGapLimit > 1
                  ? () => setState(() => _addressGapLimit--)
                  : null,
              onIncrement: _addressGapLimit < 100
                  ? () => setState(() => _addressGapLimit++)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.scanNonStandardPathsLabel,
                  style: Theme.of(context).textTheme.bodyMedium),
              subtitle: Text(l10n.scanNonStandardPathsHint,
                  style: Theme.of(context).textTheme.bodySmall),
              value: _nonStandardPaths,
              onChanged: (v) => setState(() => _nonStandardPaths = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.searchNostrLabel,
              style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(l10n.searchNostrHint,
              style: Theme.of(context).textTheme.bodySmall),
          value: _searchNostr,
          onChanged: (v) => setState(() => _searchNostr = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _onScan,
          child: Text(l10n.scanAccountsAction),
        ),
      ],
    );
  }

  Widget _buildGapStepper({
    required String label,
    required int value,
    required VoidCallback? onDecrement,
    required VoidCallback? onIncrement,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: onDecrement,
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 36,
            child: Center(
              child: Text('$value', style: theme.textTheme.titleSmall),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: onIncrement,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  Widget _buildScanningBody(AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 24),
            Text(l10n.scanAccountsScanning, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.scanAccountsScanningHint(
                  _accountGapLimit, _addressGapLimit),
              style: textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (_searchNostr) ...[
              const SizedBox(height: 4),
              Text(
                l10n.searchNostrScanningHint,
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Error
  // ---------------------------------------------------------------------------

  Widget _buildErrorBody(AppLocalizations l10n) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: errorColor),
            const SizedBox(height: 16),
            Text(_errorMessage ?? '',
                style: TextStyle(color: errorColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() => _scanState = _ScanState.idle),
              child: Text(l10n.scanAccountsRetry),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Done
  // ---------------------------------------------------------------------------

  Widget _buildDoneBody(AppLocalizations l10n) {
    final hasActivity = _accounts.isNotEmpty;
    final mfp = hasActivity ? _extractMfp(_accounts.first.keyspec) : null;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Blockchain results ──────────────────────────────────────────────
        if (!hasActivity) ...[
          const SizedBox(height: 32),
          const Center(child: Icon(Icons.search_off, size: 64)),
          const SizedBox(height: 16),
          Center(
            child: Text(l10n.scanAccountsNoActivity,
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.scanAccountsScannedCount(_totalScanned),
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => _openWizard(null),
            child: Text(l10n.scanAccountsCreateWallet),
          ),
        ] else ...[
          Row(
            children: [
              Text(l10n.keyFingerprintLabel,
                  style: theme.textTheme.labelMedium),
              const SizedBox(width: 8),
              MfpBadge(label: mfp!, color: AppAccent.color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.scanAccountsFoundActivity(_unifiedWallets.isEmpty ? _accounts.length : _unifiedWallets.length),
            style: theme.textTheme.titleMedium,
          ),
          Text(
            l10n.scanAccountsScannedCount(_totalScanned),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final w in _unifiedWallets) ...[
            _buildUnifiedWalletCard(l10n, w),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildUnifiedWalletCard(AppLocalizations l10n, ({
    String? firstAddress,
    String? walletName,
    String? derivationPath,
    APIWalletType? walletType,
    int? txCount,
    BigInt? balanceSat,
    bool hasNostrBackup,
  }) w) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isOnChain = !w.hasNostrBackup;
    
    final satsText = w.balanceSat != null && w.balanceSat != BigInt.zero
        ? '${BitcoinFormatter.formatNum(w.balanceSat!.toInt())} sats'
        : isOnChain ? '0 sats' : null;

    final scriptLabel = w.walletType != null ? _scriptTypeLabel(l10n, w.walletType!) : null;
    final existingWallet = w.firstAddress != null ? _walletByFirstAddress[w.firstAddress] : null;
    final isExisting = existingWallet != null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            if (scriptLabel != null) ...[
              _ScriptBadge(label: scriptLabel),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.walletName ?? w.derivationPath ?? l10n.nostrRestoreFound,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: w.derivationPath != null ? 'monospace' : null,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (satsText != null || w.txCount != null)
                    Text(
                      [
                        ?satsText,
                        if (w.txCount != null) '${w.txCount} txs',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (isExisting)
              _ScriptBadge(
                label: existingWallet.name,
                background: cs.primaryContainer,
                foreground: cs.onPrimaryContainer,
              ),
            const SizedBox(width: 4),
            if (w.hasNostrBackup)
              const Icon(Icons.cloud_done_outlined, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            if (isExisting)
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _openWallet(existingWallet),
              )
            else if (isOnChain)
              IconButton(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                tooltip: l10n.scanAccountsCreateWallet,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final account = _accounts.firstWhere(
                    (a) => a.firstAddress == w.firstAddress,
                  );
                  _openWizard(account);
                },
              )
            else
              IconButton(
                icon: const Icon(Icons.cloud_download_outlined),
                tooltip: l10n.importFromNostrBackup,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final backup = _nostrFoundBackups.firstWhere(
                    (b) => b.firstAddress == w.firstAddress,
                  );
                  _importFromNostr(backup.bytes, backup.xpub);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Extracts the master fingerprint from a keyspec `[mfp/path]xpub`.
  static String _extractMfp(String keyspec) =>
      kKeyspecPattern.firstMatch(keyspec)?.group(1) ?? '';

  static String _scriptTypeLabel(AppLocalizations l10n, APIWalletType walletType) {
    return switch (walletType) {
      APIWalletType.p2Pkh => l10n.scriptTypeLegacy,
      APIWalletType.p2ShWpkh => l10n.scriptTypeNested,
      APIWalletType.p2Wpkh => l10n.scriptTypeSegwit,
      APIWalletType.p2Tr => l10n.scriptTypeTaproot,
      _ => walletType.name,
    };
  }

}

// ---------------------------------------------------------------------------
// Data class for Nostr-found backups
// ---------------------------------------------------------------------------

class _NostrFoundBackup {
  final String xpub;
  final List<int> bytes;
  final String? walletName;
  final String? network;
  final int? createdAt;
  final String? firstAddress;
  final APIWalletType? walletType;

  const _NostrFoundBackup({
    required this.xpub,
    required this.bytes,
    this.walletName,
    this.network,
    this.createdAt,
    this.firstAddress,
    this.walletType,
  });
}

// ---------------------------------------------------------------------------
// Local enum for script type selector (null = all types)
// ---------------------------------------------------------------------------

enum _ScriptType { legacy, nestedSegwit, nativeSegwit, taproot }

// ---------------------------------------------------------------------------
// Script type badge
// ---------------------------------------------------------------------------

class _ScriptBadge extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;

  const _ScriptBadge({required this.label, this.background, this.foreground});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? cs.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: foreground ?? cs.onSecondaryContainer,
        ),
      ),
    );
  }
}
