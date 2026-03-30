import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/simple_wallet_dialog.dart';
import 'package:deadbolt/screens/wallet_detail_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' as rust_wallet;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart' show KeyspecResult, kKeyspecPattern;
import 'package:deadbolt/widgets/colored_group_text.dart';
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

  _ScanState _scanState = _ScanState.idle;
  String? _errorMessage;
  List<APIAccountInfo> _accounts = [];
  int _totalScanned = 0;
  Map<String, APIWalletInfo> _walletByFirstAddress = {};

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
    });

    final passphrase =
        _passphraseController.text.isEmpty ? null : _passphraseController.text;
    final url = _electrumUrl;

    final types =
        _scriptFilter != null ? [_scriptFilter!] : _ScriptType.values;

    try {
      final futures = types.map((t) => rust_wallet.discoverAccounts(
            mnemonic: mnemonic,
            passphrase: passphrase,
            walletType: _toWalletType(t),
            network: _selectedNetwork,
            electrumUrl: url,
            accountGapLimit: _accountGapLimit,
            addressGapLimit: _addressGapLimit,
          ));

      final (results, walletByFirstAddress) = await (
        Future.wait(futures),
        _buildWalletByAddress(),
      ).wait;
      if (!mounted) return;

      final merged = results.expand((r) => r.accounts).toList();
      final totalScanned =
          results.map((r) => r.scannedCount).fold(0, (a, b) => a + b);

      setState(() {
        _accounts = merged;
        _totalScanned = totalScanned;
        _walletByFirstAddress = walletByFirstAddress;
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
        final addr = await rust_wallet.firstAddressFromDescriptor(
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
          ],
        ),
        const SizedBox(height: 24),
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
            l10n.scanAccountsFoundActivity(_accounts.length),
            style: theme.textTheme.titleMedium,
          ),
          Text(
            l10n.scanAccountsScannedCount(_totalScanned),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final account in _accounts) ...[
            _buildAccountCard(l10n, account),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  /// Extracts the master fingerprint from a keyspec `[mfp/path]xpub`.
  static String _extractMfp(String keyspec) =>
      kKeyspecPattern.firstMatch(keyspec)?.group(1) ?? '';

  Widget _buildAccountCard(AppLocalizations l10n, APIAccountInfo account) {
    final bracketEnd = account.keyspec.indexOf(']');
    final xpub = bracketEnd >= 0
        ? account.keyspec.substring(bracketEnd + 1)
        : account.keyspec;

    final satsText = account.balanceSat == BigInt.zero
        ? '0 sats'
        : '${BitcoinFormatter.formatNum(account.balanceSat.toInt())} sats';

    final scriptLabel = _scriptTypeLabel(l10n, account.walletType);
    final matched = _walletByFirstAddress[account.firstAddress];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ScriptBadge(label: scriptLabel),
                const SizedBox(width: 6),
                Text(
                  account.derivationPath,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                if (matched != null)
                  _ScriptBadge(
                    label: matched.name,
                    background: cs.primaryContainer,
                    foreground: cs.onPrimaryContainer,
                  ),
                const Spacer(),
                if (matched != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                    tooltip: matched.name,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openWallet(matched),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    tooltip: l10n.scanAccountsCreateWallet,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openWizard(account),
                  ),
              ],
            ),
            Text(
              '${l10n.scanAccountsActivitySummary(account.txCount)}  ·  $satsText',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            ColoredGroupText(
              text: xpub,
              fontSize: 12,
              truncate: true,
              monospace: true,
            ),
          ],
        ),
      ),
    );
  }

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
