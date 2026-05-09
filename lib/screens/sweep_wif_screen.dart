import 'dart:async';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/config/app_settings_extensions.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/services/mempool_blocks_service.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/tor.dart' show isTorRunning, torSocksAddr;
import 'package:deadbolt/src/rust/api/wif_sweep.dart' as wif_sweep;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show showSheet;
import 'package:deadbolt/widgets/fee_presets_widget.dart';

/// Full-screen flow for sweeping funds from an external WIF private key
/// into the user's current wallet or a custom destination address.
class SweepWifScreen extends StatefulWidget {
  final APINetwork network;
  final String? currentWalletPath;
  final Future<APIAddress?> Function()? getNextAddress;
  final Future<String?> Function(String walletPath)? getAddressForWallet;
  final VoidCallback? onSwept;

  const SweepWifScreen({
    super.key,
    required this.network,
    this.currentWalletPath,
    this.getNextAddress,
    this.getAddressForWallet,
    this.onSwept,
  });

  static Future<void> push(
    BuildContext context, {
    required APINetwork network,
    String? currentWalletPath,
    Future<APIAddress?> Function()? getNextAddress,
    Future<String?> Function(String walletPath)? getAddressForWallet,
    VoidCallback? onSwept,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SweepWifScreen(
            network: network,
            currentWalletPath: currentWalletPath,
            getNextAddress: getNextAddress,
            getAddressForWallet: getAddressForWallet,
            onSwept: onSwept,
          ),
        ),
      );

  @override
  State<SweepWifScreen> createState() => _SweepWifScreenState();
}

class _SweepWifScreenState extends State<SweepWifScreen> {
  final _wifCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _feeRateCtrl = TextEditingController(text: '1.0');
  final _rateFocusNode = FocusNode();

  bool _destEditMode = true;
  bool _feeEditing = false;

  FeePresets? _feePresets;
  int? _selectedPresetIndex;

  Timer? _blockSnapshotTimer;
  bool _blockSnapshotPending = false;

  List<wif_sweep.APIWifAddress>? _resolvedAddresses;
  List<wif_sweep.APIWifUtxo>? _utxos;
  bool _querying = false;
  bool _sweeping = false;
  String? _queryError;

  @override
  void initState() {
    super.initState();
    _loadFeePresets();
  }

  @override
  void dispose() {
    _blockSnapshotTimer?.cancel();
    _wifCtrl.dispose();
    _destCtrl.dispose();
    _feeRateCtrl.dispose();
    _rateFocusNode.dispose();
    super.dispose();
  }

  void _loadFeePresets() {
    _refreshBlockSnapshot();
    _blockSnapshotTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshBlockSnapshot(),
    );
  }

  void _refreshBlockSnapshot() {
    if (_blockSnapshotPending) return;
    _blockSnapshotPending = true;
    final settings = context.read<SettingsCubit>().state;
    final explorerBase = settings.explorerBaseForNetwork(widget.network);
    final socksAddr = isTorRunning() ? torSocksAddr() : null;
    MempoolBlocksService.getSnapshot(explorerBase, torSocksAddr: socksAddr).then((s) {
      _blockSnapshotPending = false;
      if (!mounted) return;
      setState(() {
        if (s != null) {
          _feePresets = s.presetsFromSnapshot(
            context.read<SettingsCubit>().state.minFeeRate,
          );
        }
      });
    });
  }

  APINetwork get _network => widget.network;

  String get _electrumUrl {
    final settings = context.read<SettingsCubit>().state;
    return settings.electrumUrlForNetwork(_network);
  }

  // ---------------------------------------------------------------------------
  // Step 1: paste / scan WIF
  // ---------------------------------------------------------------------------

  Future<void> _pasteWif() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _wifCtrl.text = data!.text!.trim();
    }
  }

  Future<void> _scanWif() async {
    final scanned = await QrScannerScreen.push(context);
    if (scanned != null && mounted) {
      _wifCtrl.text = scanned.trim();
    }
  }

  // ---------------------------------------------------------------------------
  // Step 2: query UTXOs
  // ---------------------------------------------------------------------------

  Future<void> _queryUtxos() async {
    final wif = _wifCtrl.text.trim();
    if (wif.isEmpty) {
      showErrorToast(context.l10n.sweepWifEnterKeyFirst);
      return;
    }

    setState(() {
      _querying = true;
      _queryError = null;
      _resolvedAddresses = null;
      _utxos = null;
    });

    try {
      final results = await Future.wait([
        wif_sweep.resolveWif(wif: wif, network: _network),
        wif_sweep.queryWifUtxos(wif: wif, network: _network, electrumUrl: _electrumUrl),
      ]);
      final addresses = results[0] as List<wif_sweep.APIWifAddress>;
      final utxos = results[1] as List<wif_sweep.APIWifUtxo>;

      // Default destination: next receive address of the current wallet.
      if (_destCtrl.text.isEmpty && mounted) {
        final nextAddr = await widget.getNextAddress?.call();
        if (mounted && nextAddr != null) _setDest(nextAddr.address);
      }

      if (mounted) {
        setState(() {
          _resolvedAddresses = addresses;
          _utxos = utxos;
          _querying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _queryError = e.toString().replaceFirst(RegExp(r'^Exception: '), '');
          _querying = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Step 3: sweep
  // ---------------------------------------------------------------------------

  Future<void> _sweep() async {
    final wif = _wifCtrl.text.trim();
    final dest = _destCtrl.text.trim();
    final feeRate = double.tryParse(_feeRateCtrl.text.trim());

    if (wif.isEmpty || dest.isEmpty || feeRate == null || feeRate <= 0) {
      showErrorToast(context.l10n.sweepWifFillFields);
      return;
    }

    setState(() => _sweeping = true);
    try {
      final txid = await wif_sweep.sweepWif(
        wif: wif,
        destinationAddress: dest,
        feeRateSatPerVb: feeRate,
        electrumUrl: _electrumUrl,
        network: _network,
      );
      if (mounted) {
        showSuccessToast(context.l10n.sweepWifSweptToast(txid));
        widget.onSwept?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showErrorToastException(e);
        setState(() => _sweeping = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Destination UI helpers
  // ---------------------------------------------------------------------------

  void _setDest(String addr) {
    setState(() {
      _destCtrl.text = addr;
      _destEditMode = false;
    });
  }

  void _confirmDest() {
    if (_destCtrl.text.trim().isEmpty) return;
    setState(() => _destEditMode = false);
  }

  Future<void> _showWalletPickerSheet() async {
    final l10n = context.l10n;
    final listState = context.read<WalletListCubit>().state;
    final allWallets = listState is WalletListLoaded ? listState.wallets : <APIWalletInfo>[];
    final service = context.read<WalletService>();

    final sameNetwork = allWallets
        .where((w) => w.network == widget.network)
        .toList()
      ..sort((a, b) {
        if (a.walletPath == widget.currentWalletPath) return -1;
        if (b.walletPath == widget.currentWalletPath) return 1;
        return 0;
      });

    if (!mounted) return;

    await showSheet<void>(context, (sheetCtx) {
      final theme = Theme.of(sheetCtx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.createTxSelectDestWallet,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ...sameNetwork.map((wallet) {
            final isCurrent = wallet.walletPath == widget.currentWalletPath;
            final isLocked = wallet.protection.needsPassword &&
                service.getCachedPassword(wallet.walletPath) == null;
            final name = isCurrent ? l10n.createTxThisWallet : wallet.name;
            return ListTile(
              leading: isLocked
                  ? Icon(Icons.lock_outline,
                      color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive))
                  : isCurrent
                      ? Icon(Icons.account_balance_wallet_outlined,
                          color: theme.colorScheme.primary)
                      : const Icon(Icons.account_balance_wallet_outlined),
              title: Text(
                name,
                style: isLocked
                    ? TextStyle(
                        color: theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive))
                    : null,
              ),
              enabled: !isLocked,
              onTap: isLocked
                  ? null
                  : () {
                      Navigator.of(sheetCtx).pop();
                      _fillAddressFromWallet(wallet.walletPath, isCurrent);
                    },
            );
          }),
          const SizedBox(height: 8),
        ],
      );
    });
  }

  Future<void> _fillAddressFromWallet(String walletPath, bool isCurrent) async {
    final String? address;
    if (isCurrent) {
      address = (await widget.getNextAddress?.call())?.address;
    } else {
      address = await widget.getAddressForWallet?.call(walletPath);
    }
    if (!mounted) return;
    if (address == null) {
      showErrorToast(context.l10n.createTxNoUnusedAddress);
      return;
    }
    _setDest(address);
  }

  // ---------------------------------------------------------------------------
  // Fee UI helpers
  // ---------------------------------------------------------------------------

  void _applyPreset(int index) {
    if (_feePresets == null) return;
    final rates = [_feePresets!.economy, _feePresets!.normal, _feePresets!.priority];
    setState(() {
      _selectedPresetIndex = index;
      _feeRateCtrl.text = rates[index].toStringAsFixed(1);
      _feeEditing = false;
    });
  }


  Widget _buildFeeRateField(BuildContext context) {
    final feeRateLabel = context.l10n.feeRateLabel;
    if (_feeEditing) {
      return TextFormField(
        controller: _feeRateCtrl,
        focusNode: _rateFocusNode,
        decoration: InputDecoration(
          labelText: feeRateLabel,
          suffixText: 'sat/vB',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() => _selectedPresetIndex = null),
        onEditingComplete: () => setState(() => _feeEditing = false),
        onTapOutside: (_) => setState(() => _feeEditing = false),
      );
    }
    return InkWell(
      onTap: () {
        setState(() => _feeEditing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rateFocusNode.requestFocus();
        });
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: feeRateLabel,
          suffixText: 'sat/vB',
        ),
        isEmpty: false,
        child: Text(_feeRateCtrl.text),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final utxos = _utxos;
    final totalSat = utxos?.fold<int>(0, (s, u) => s + u.valueSat.toInt()) ?? 0;
    final hasUtxos = utxos != null && utxos.isNotEmpty;

    // Precompute per-address UTXO stats for O(M) lookup during address rendering.
    final utxosByAddr = <String, ({int count, int sat})>{};
    if (utxos != null) {
      for (final u in utxos) {
        final prev = utxosByAddr[u.address];
        utxosByAddr[u.address] = prev == null
            ? (count: 1, sat: u.valueSat.toInt())
            : (count: prev.count + 1, sat: prev.sat + u.valueSat.toInt());
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sweepWifTitle)),
      body: SingleChildScrollView(
        dragStartBehavior: DragStartBehavior.down,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── WIF input ──────────────────────────────────────────────────
            Text(l10n.sweepWifPrivateKeySection,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _wifCtrl,
              decoration: InputDecoration(
                hintText: l10n.sweepWifHint,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.paste_outlined, size: 20),
                      tooltip: l10n.pasteFromClipboard,
                      onPressed: _pasteWif,
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner_outlined, size: 20),
                      tooltip: l10n.scanQrCode,
                      onPressed: _scanWif,
                    ),
                  ],
                ),
              ),
              maxLines: 2,
              style: const TextStyle(fontFamily: kMonospaceFontFamily, fontSize: 12),
              onChanged: (_) => setState(() {
                _resolvedAddresses = null;
                _utxos = null;
                _queryError = null;
              }),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: _querying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(_querying ? l10n.sweepWifSearching : l10n.sweepWifFindUtxos),
              onPressed: _querying ? null : _queryUtxos,
            ),

            // ── Query error ────────────────────────────────────────────────
            if (_queryError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _queryError!,
                  style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                ),
              ),
            ],

            // ── Detected addresses ─────────────────────────────────────────
            if (_resolvedAddresses != null && _resolvedAddresses!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Text(l10n.sweepWifControlledAddresses,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 8),
              ..._resolvedAddresses!.map((a) {
                final stats = utxosByAddr[a.address];
                final utxoCount = stats?.count ?? 0;
                final utxoSat = stats?.sat ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          a.addressType.toUpperCase(),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSecondaryContainer),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ColoredGroupText(
                          text: a.address,
                          fontSize: 11,
                          truncate: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        utxoCount > 0
                            ? '$utxoSat sat ($utxoCount UTXO${utxoCount > 1 ? 's' : ''})'
                            : l10n.sweepWifEmpty,
                        style: TextStyle(
                          fontSize: 11,
                          color: utxoCount > 0
                              ? scheme.primary
                              : scheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              if (hasUtxos) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(l10n.sweepWifTotal(totalSat),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ],
            ],

            // ── No UTXOs message ───────────────────────────────────────────
            if (utxos != null && !hasUtxos) ...[
              const SizedBox(height: 12),
              Text(
                l10n.sweepWifNoFunds,
                style: TextStyle(color: scheme.onSurface.withAlpha(153)),
              ),
            ],

            // ── Sweep form (only shown when UTXOs found) ───────────────────
            if (hasUtxos) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),

              // Destination address.
              Text(l10n.sweepWifDestination,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _destEditMode
                          ? TextField(
                              controller: _destCtrl,
                              decoration: InputDecoration(
                                hintText: l10n.sweepWifAddressHint,
                                isDense: true,
                                filled: true,
                                fillColor: scheme.surface,
                              ),
                              keyboardType: TextInputType.text,
                              autocorrect: false,
                              style: const TextStyle(
                                  fontFamily: kMonospaceFontFamily, fontSize: 12),
                              onSubmitted: (_) => _confirmDest(),
                              onTapOutside: (_) => _confirmDest(),
                            )
                          : InkWell(
                              onTap: () =>
                                  setState(() => _destEditMode = true),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color:
                                          scheme.outline.withAlpha(180)),
                                ),
                                child: ColoredGroupText(
                                  text: _destCtrl.text,
                                  truncate: true,
                                ),
                              ),
                            ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        icon: const Icon(
                            Icons.account_balance_wallet_outlined),
                        color: scheme.onSurface.withAlpha(AppAlpha.secondary),
                        tooltip: l10n.createTxMyWalletsButton,
                        onPressed: _showWalletPickerSheet,
                      ),
                    ),
                    if (!_destEditMode && _destCtrl.text.isNotEmpty)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          icon: const Icon(Icons.close),
                          color:
                              scheme.onSurface.withAlpha(AppAlpha.secondary),
                          onPressed: () => setState(() {
                            _destCtrl.clear();
                            _destEditMode = true;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              buildFeePresetsSegments(_feePresets, _selectedPresetIndex, _applyPreset),
              if (_feePresets != null) const SizedBox(height: 8),

              // Fee rate field.
              _buildFeeRateField(context),
              const SizedBox(height: 24),

              // Sweep button.
              FilledButton.icon(
                icon: _sweeping
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(_sweeping
                    ? l10n.sweepWifSweeping
                    : l10n.sweepWifButton(totalSat)),
                onPressed: _sweeping ? null : _sweep,
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
