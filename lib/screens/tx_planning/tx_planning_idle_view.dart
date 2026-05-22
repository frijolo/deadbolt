import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/config/app_settings_extensions.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/errors.dart' show formatRustError;
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/coin_selector_screen.dart';
import 'package:deadbolt/screens/create_tx/create_tx_models.dart' show ThousandsSeparatorFormatter;
import 'package:deadbolt/screens/create_tx/selected_path_card.dart';
import 'package:deadbolt/services/mempool_blocks_service.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;
import 'package:deadbolt/src/rust/api/tor.dart' show isTorRunning, torSocksAddr;
import 'package:deadbolt/utils/spend_path_dropdown.dart'
    show pathLabel, pathTimelockStatus;
import 'package:deadbolt/src/rust/api/model.dart'
    show
        APICoinControl,
        APIKeychain,
        APIUtxo,
        APISpendPath,
        APISpacedPlanParams,
        APINetwork,
        APIWalletInfo,
        APIWalletProtection,
        APIProtectionType,
        APISecurityLevel;
import 'package:deadbolt/utils/bitcoin_formatter.dart' show BitcoinFormatter;
import 'package:deadbolt/widgets/fee_histogram_widget.dart';
import 'package:deadbolt/widgets/fee_presets_widget.dart';

/// Idle screen: comprehensive configuration for spaced TX planning.
///
/// Features (vs v1 ChoiceChip presets):
///   • Fee histogram (FeeHistogramWidget) + preset segments (buildFeePresetsSegments)
///   • Manual fee rate min/max (sat/vB)
///   • Manual delay min/max (blocks)
///   • Coin selector (all confirmed UTXOs selected by default)
///   • Destination wallet selector (self = refresh, other = migrate)
///   • Spend path selector (when descriptor has multiple paths)
///   • Split probability + min output controls
class TxPlanningIdleView extends StatefulWidget {
  final APISpacedPlanDetail? lastTerminal;
  const TxPlanningIdleView({super.key, this.lastTerminal});

  @override
  State<TxPlanningIdleView> createState() => _TxPlanningIdleViewState();
}

class _TxPlanningIdleViewState extends State<TxPlanningIdleView> {
  // Fee defaults are sat/vB; `_compute` multiplies by 1000 before FFI.
  final _feeRateMinCtrl = TextEditingController(text: '');
  final _feeRateMaxCtrl = TextEditingController(text: '');
  final _delayMinCtrl = TextEditingController(text: '24');
  final _delayMaxCtrl = TextEditingController(text: '288');
  final _splitProbCtrl = TextEditingController(text: '0');
  final _minOutputCtrl = TextEditingController(text: BitcoinFormatter.formatNum(100000));
  final _minOutputFocus = FocusNode();

  MempoolBlocksSnapshot? _blockSnapshot;
  bool _feeLoading = true;
  int? _presetIndex;

  List<APIUtxo> _selectedUtxos = const [];
  bool _allCoinsSelected = true;

  APISpendPath? _selectedSpendPath;

  String? _selectedDstWalletPath;
  List<APIWalletInfo> _allWallets = const [];

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWallets();
    _minOutputFocus.addListener(_reformatMinOutput);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autofillFeeFields(null);
      _refreshBlockSnapshot();
    });
  }

  void _reformatMinOutput() {
    if (_minOutputFocus.hasFocus) return;
    final raw = _minOutputCtrl.text.replaceAll(',', '').replaceAll('.', '').trim();
    final n = int.tryParse(raw);
    if (n == null || n <= 0) return;
    _minOutputCtrl.text = BitcoinFormatter.formatNum(n);
  }

  @override
  void dispose() {
    _feeRateMinCtrl.dispose();
    _feeRateMaxCtrl.dispose();
    _delayMinCtrl.dispose();
    _delayMaxCtrl.dispose();
    _splitProbCtrl.dispose();
    _minOutputCtrl.dispose();
    _minOutputFocus.removeListener(_reformatMinOutput);
    _minOutputFocus.dispose();
    super.dispose();
  }

  void _loadWallets() {
    final walletsCubit = context.read<WalletListCubit>();
    if (walletsCubit.state is WalletListLoaded) {
      final list = walletsCubit.state as WalletListLoaded;
      setState(() => _allWallets = list.wallets);
    }
  }

  Future<void> _refreshBlockSnapshot() async {
    final settings = context.read<SettingsCubit>().state;
    final wallet = _walletDetailLoaded(context);
    final network = wallet?.walletInfo.network ?? APINetwork.bitcoin;
    final explorerBase = settings.explorerBaseForNetwork(network);
    final socksAddr = isTorRunning() ? torSocksAddr() : null;
    final snapshot = await MempoolBlocksService.getSnapshot(
      explorerBase,
      torSocksAddr: socksAddr,
    );
    if (mounted) {
      setState(() {
        _blockSnapshot = snapshot;
        _feeLoading = false;
      });
      _autofillFeeFields(snapshot);
    }
  }

  void _autofillFeeFields(MempoolBlocksSnapshot? snapshot) {
    if (!mounted) return;
    final floor = context.read<SettingsCubit>().state.minFeeRate;
    final median = (snapshot != null && snapshot.blocks.isNotEmpty)
        ? snapshot.blocks.first.medianFee
        : 0.0;
    final minFee = median > floor ? median : floor;
    setState(() {
      _feeRateMinCtrl.text = minFee.toStringAsFixed(1);
      _feeRateMaxCtrl.text = (minFee * 2).toStringAsFixed(1);
    });
  }

  void _applyPreset(int index) {
    if (_blockSnapshot == null) return;
    final floor = context.read<SettingsCubit>().state.minFeeRate;
    final presets = _blockSnapshot!.presetsFromSnapshot(floor);
    final raw = switch (index) {
      0 => presets.economy,
      1 => presets.normal,
      2 => presets.priority,
      _ => presets.normal,
    };
    final feeRate = raw > floor ? raw : floor;
    setState(() {
      _presetIndex = index;
      _feeRateMinCtrl.text = feeRate.toStringAsFixed(1);
      _feeRateMaxCtrl.text = (feeRate * 2).toStringAsFixed(1);
    });
  }

  Future<void> _openCoinSelector() async {
    final wallet = _walletDetailLoaded(context);
    if (wallet == null || !mounted) return;
    final apiWallet = wallet.walletHandle;
    final utxos = await apiWallet.getUtxos();
    final confirmed = utxos.where((u) => u.isConfirmed).toList();
    if (confirmed.isEmpty || !mounted) return;

    final spendPaths = wallet.descriptorAnalysis?.spendPaths ?? const [];
    final selectedPath = _selectedSpendPath ?? spendPaths.firstOrNull;
    final result = await CoinSelectorScreen.push(
      context,
      allUtxos: confirmed,
      network: wallet.walletInfo.network,
      selectedPath: selectedPath,
      tipHeight: wallet.tipHeight,
      initiallySelected: _allCoinsSelected ? confirmed : _selectedUtxos,
      keyLabels: wallet.keyLabels,
    );
    if (result != null && mounted) {
      setState(() {
        _selectedUtxos = result;
        _allCoinsSelected = result.length == confirmed.length;
      });
    }
  }

  Future<void> _openWalletSelector() async {
    final wallet = _walletDetailLoaded(context);
    if (wallet == null || !mounted) return;

    final currentPath = wallet.walletInfo.walletPath;
    final wallets = _allWallets.where((w) {
      if (w.walletPath == currentPath) return true;
      return w.network == wallet.walletInfo.network;
    }).toList();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.txPlanningDestinationLabel),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: wallets.length,
            itemBuilder: (context, index) {
              final w = wallets[index];
              final isSelf = w.walletPath == currentPath;
              final kind = isSelf
                  ? ctx.l10n.txPlanningRefresh
                  : ctx.l10n.txPlanningMigrate;
              return ListTile(
                leading: Icon(
                  isSelf ? Icons.refresh : Icons.swap_horiz,
                  size: 20,
                ),
                title: Text(w.name),
                subtitle: Text(kind),
                selected: _selectedDstWalletPath == w.walletPath,
                onTap: () => Navigator.of(ctx).pop(w.walletPath),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() => _selectedDstWalletPath = result);
    }
  }

  Future<void> _compute() async {
    final l10n = context.l10n;
    // Capture the service synchronously — we need it after an await to
    // open the destination wallet (Migrate plans) and `context.read`
    // across async gaps trips the lint.
    final walletService = context.read<WalletService>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wallet = _walletDetailLoaded(context);
      if (wallet == null) {
        setState(() => _error = l10n.txPlanningWalletNotLoaded);
        return;
      }
      final apiWallet = wallet.walletHandle;
      final walletPath = wallet.walletInfo.walletPath;

      // Validate fee rates (can contain decimals, displayed in sat/vB)
      final feeRateMinParsed = double.tryParse(_feeRateMinCtrl.text);
      final feeRateMaxParsed = double.tryParse(_feeRateMaxCtrl.text);
      if (feeRateMinParsed == null || feeRateMaxParsed == null || feeRateMinParsed <= 0 || feeRateMaxParsed <= 0) {
        setState(() => _error = l10n.txPlanningInvalidFeeRate);
        return;
      }
      if (feeRateMinParsed > feeRateMaxParsed) {
        setState(() => _error = l10n.txPlanningFeeRateOrder);
        return;
      }
      final feeRateMin = feeRateMinParsed;
      final feeRateMax = feeRateMaxParsed;

      // Validate delay ranges
      final delayMin = int.tryParse(_delayMinCtrl.text);
      final delayMax = int.tryParse(_delayMaxCtrl.text);
      if (delayMin == null || delayMax == null || delayMin <= 0 || delayMax <= 0) {
        setState(() => _error = l10n.txPlanningInvalidDelay);
        return;
      }
      if (delayMin > delayMax) {
        setState(() => _error = l10n.txPlanningDelayOrder);
        return;
      }

      // Validate split probability (input is in percentage 0–100)
      final splitProbPct = double.tryParse(_splitProbCtrl.text);
      if (splitProbPct == null || splitProbPct < 0 || splitProbPct > 100) {
        setState(() => _error = l10n.txPlanningInvalidSplitProbability);
        return;
      }
      final splitProb = splitProbPct / 100;

      // Validate min output
      final minOutput = BigInt.tryParse(
        _minOutputCtrl.text.replaceAll(',', '').replaceAll('.', '').trim(),
      );
      if (minOutput == null || minOutput <= BigInt.zero) {
        setState(() => _error = l10n.txPlanningInvalidMinOutput);
        return;
      }

      // Determine spend path
      final spendPaths = wallet.descriptorAnalysis?.spendPaths ?? const [];
      final effectiveSpendPath = _selectedSpendPath ?? spendPaths.firstOrNull;
      if (effectiveSpendPath == null) {
        setState(() => _error = l10n.txPlanningWalletNotLoaded);
        return;
      }

      // Determine destination
      final dstWalletPath = _selectedDstWalletPath ?? walletPath;
      final isMigrate = dstWalletPath != walletPath;

      // Get destination addresses
      final utxos = await apiWallet.getUtxos();
      final confirmedCount = utxos.where((u) => u.isConfirmed).length;
      if (confirmedCount == 0) {
        setState(() => _error = l10n.txPlanningNoConfirmedUtxos);
        return;
      }

      // For Refresh the destination addresses live in this wallet, so
      // we reuse the source handle. For Migrate they belong to the
      // selected wallet — open its handle (cached credentials only;
      // surface a clear error if the wallet hasn't been unlocked this
      // session). The same handle is later passed to the cubit so it
      // can mirror the plan's auto-labels into the dst DB.
      ApiWallet dstApiWallet;
      if (isMigrate) {
        try {
          dstApiWallet = await walletService.openWallet(dstWalletPath);
        } catch (e) {
          setState(() => _error = formatRustError(e));
          return;
        }
      } else {
        dstApiWallet = apiWallet;
      }

      final externals = (await dstApiWallet.getAddresses(
        keychain: APIKeychain.external_,
      ))
          .toList()
        ..sort((a, b) => b.index.compareTo(a.index));
      final budget = splitProb > 0 ? confirmedCount * 2 : confirmedCount;
      if (externals.length < budget) {
        setState(() => _error = l10n.txPlanningTooFewAddresses(budget));
        return;
      }
      final dstAddresses = externals.take(budget).map((a) => a.address).toList();

      // Destination wallet name snapshot — used by Rust to label
      // each Migrate child PSBT/transaction. Empty on Refresh.
      String? dstWalletName;
      if (isMigrate) {
        for (final w in _allWallets) {
          if (w.walletPath == dstWalletPath) {
            dstWalletName = w.name;
            break;
          }
        }
      }

      // Build params
      final params = APISpacedPlanParams(
        dstWalletPath: dstWalletPath,
        dstWalletName: dstWalletName,
        feerateMinMsatvb: BigInt.from((feeRateMin * 1000).toInt()),
        feerateMaxMsatvb: BigInt.from((feeRateMax * 1000).toInt()),
        delayBlocksMin: delayMin,
        delayBlocksMax: delayMax,
        splitProbability: splitProb,
        minSplitOutput: minOutput,
        spendPathId: effectiveSpendPath.id,
        threshold: effectiveSpendPath.threshold,
        mfps: effectiveSpendPath.mfps,
        policyPath: effectiveSpendPath.policyPath,
        dstAddresses: dstAddresses,
        selectedUtxos: _selectedUtxos
            .map((u) => APICoinControl(txid: u.txid, vout: u.vout))
            .toList(),
      );
      if (!mounted) return;
      await context.read<TxPlanningCubit>().createPlan(
            params,
            dstWallet: isMigrate ? dstApiWallet : null,
          );
    } catch (e) {
      setState(() => _error = formatRustError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  WalletDetailLoaded? _walletDetailLoaded(BuildContext context) {
    final s = context.read<WalletDetailCubit>().state;
    return s is WalletDetailLoaded ? s : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final wallet = _walletDetailLoaded(context);
    final spendPaths = wallet?.descriptorAnalysis?.spendPaths ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      dragStartBehavior: DragStartBehavior.down,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.lastTerminal != null) ...[
            Card(
              color: cs.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  l10n.txPlanningLastPlanTitle(widget.lastTerminal!.status),
                ),
                subtitle: Text(
                  l10n.txPlanningLastPlanSubtitle(
                    widget.lastTerminal!.planId.toInt(),
                    widget.lastTerminal!.kind,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(l10n.txPlanningIdleDescription),
          const SizedBox(height: 16),

          // Fee histogram
          FeeHistogramWidget(
            snapshot: _blockSnapshot,
            loading: _feeLoading,
            onFeeSelected: (fee) {
              final floor = context.read<SettingsCubit>().state.minFeeRate;
              final minFee = fee > floor ? fee : floor;
              setState(() {
                _presetIndex = 1;
                _feeRateMinCtrl.text = minFee.toStringAsFixed(1);
                _feeRateMaxCtrl.text = (minFee * 2).toStringAsFixed(1);
              });
            },
          ),
          const SizedBox(height: 8),

          // Fee presets
          if (_blockSnapshot != null) ...[
            buildFeePresetsSegments(
              _blockSnapshot!.presetsFromSnapshot(
                _blockSnapshot!.nextBlockMinFee ?? 1.0,
              ),
              _presetIndex,
              _applyPreset,
            ),
            const SizedBox(height: 16),
          ],

            if (_blockSnapshot != null) ...[
              Builder(
                builder: (ctx) {
                  final next = _blockSnapshot!.blocks.isNotEmpty
                      ? _blockSnapshot!.blocks.first
                      : null;
                  final feeRange = (next != null && next.minFee > 0)
                      ? '${BitcoinFormatter.formatFeeRate(next.minFee)} ~ ${BitcoinFormatter.formatFeeRate(next.p75Fee)} sat/vB'
                      : null;
                  final Widget hint = feeRange != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 4),
                          child: Text(
                            feeRange,
                            style: Theme.of(ctx).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : const SizedBox.shrink();
                  return hint;
                },
              ),
            ],

            const SizedBox(height: 16),

             // Fee rate min/max
             Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _feeRateMinCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.txPlanningFeeRateMinLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'sat/vB',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _feeRateMaxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.txPlanningFeeRateMaxLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'sat/vB',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Delay min/max
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _delayMinCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.txPlanningDelayMinLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _delayMaxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.txPlanningDelayMaxLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Split probability
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _splitProbCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.txPlanningSplitProbabilityLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixText: '%',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minOutputCtrl,
                    focusNode: _minOutputFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      ThousandsSeparatorFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.txPlanningMinOutputLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'sats',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Spend path selector — same shape as the send flow's
            // (`create_tx_screen.dart`): rich dropdown items with lock
            // status + a `SelectedPathCard` summary underneath.
            if (spendPaths.isNotEmpty) ...[
              Text(
                l10n.txPlanningSpendPathLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (ctx) {
                  final effectivePath = _selectedSpendPath ?? spendPaths.first;
                  final tipHeight = wallet?.tipHeight ?? 0;
                  final keyLabels = wallet?.keyLabels ?? const {};
                  final pathLabels = wallet?.pathLabels ?? const {};
                  // Conf-height pool: only the coins the user picked. When
                  // "All coins" is the default, `_selectedUtxos` is empty
                  // and rel-block locks render no per-path hint — same as
                  // create_tx before the user picks coins.
                  final confHeights = _selectedUtxos
                      .where((u) => u.confirmationHeight != null)
                      .map((u) => u.confirmationHeight!)
                      .toList();
                  final int? utxoMaxConfHeight = confHeights.isEmpty
                      ? null
                      : confHeights.reduce((a, b) => a > b ? a : b);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<APISpendPath>(
                        initialValue: effectivePath,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: spendPaths.map((p) {
                          final lock = pathTimelockStatus(
                            ctx,
                            p,
                            tipHeight: tipHeight,
                            utxoMaxConfHeight: utxoMaxConfHeight,
                            hasSelectedUtxos: _selectedUtxos.isNotEmpty,
                          );
                          return DropdownMenuItem(
                            value: p,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    pathLabel(
                                      p,
                                      keyLabels: keyLabels,
                                      pathLabels: pathLabels,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (lock != null) ...[
                                  const SizedBox(width: 6),
                                  Icon(lock.icon, size: 14, color: lock.color),
                                  const SizedBox(width: 3),
                                  Text(
                                    lock.text,
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: lock.color),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (p) {
                          if (p == null) return;
                          setState(() => _selectedSpendPath = p);
                        },
                      ),
                      const SizedBox(height: 12),
                      SelectedPathCard(
                        path: effectivePath,
                        tipHeight: tipHeight,
                        utxoMaxConfHeight: utxoMaxConfHeight,
                        keyLabels: keyLabels,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // Destination wallet selector
            Text(
              l10n.txPlanningDestinationLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _openWalletSelector,
              child: Card(
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _selectedDstWalletPath == wallet?.walletInfo.walletPath
                            ? Icons.refresh
                            : Icons.swap_horiz,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDstWalletPath == null ||
                                  _selectedDstWalletPath == wallet?.walletInfo.walletPath
                              ? l10n.txPlanningDestinationSelf
                              : _formatWalletName(_selectedDstWalletPath!, l10n),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Coin selector
            Text(
              l10n.txPlanningSelectCoins,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _openCoinSelector,
              child: Card(
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _allCoinsSelected ? Icons.check_circle : Icons.numbers,
                        size: 20,
                        color: _allCoinsSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _allCoinsSelected
                              ? l10n.txPlanningAllCoins
                              : l10n.txPlanningCoinsSelected(
                                  _selectedUtxos.length.toString(),
                                ),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 32),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _compute,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.calculate),
            label: Text(l10n.txPlanningComputePlanButton),
          ),
        ],
      ),
    );
  }

  String _formatWalletName(String path, AppLocalizations l) {
    final w = _allWallets.firstWhere(
      (w) => w.walletPath == path,
      orElse: () => APIWalletInfo(
        walletPath: path,
        name: path,
        descriptor: '',
        network: APINetwork.bitcoin,
        createdAt: 0,
        protection: const APIWalletProtection(
          protectionType: APIProtectionType.deviceKey,
          needsPassword: false,
          securityLevel: APISecurityLevel.standard,
        ),
      ),
    );
    final srcPath = _walletDetailLoaded(context)?.walletInfo.walletPath;
    final isSelf = srcPath != null && path == srcPath;
    final kind = isSelf ? l.txPlanningRefresh : l.txPlanningMigrate;
    return l.txPlanningDestinationWallet(w.name, kind);
  }
}
