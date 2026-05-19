import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_reserved_chip.dart';
import 'package:deadbolt/screens/wallet_detail/wallet_detail_shared.dart';

// ─────────────────────────────────────────────────────────────
// Coins (UTXOs) view (tab 3) — with coin control selection
// ─────────────────────────────────────────────────────────────

enum _CoinSortField { size, age }

enum _CoinSortDir { asc, desc }

class CoinsView extends StatefulWidget {
  final WalletDetailLoaded state;

  const CoinsView({super.key, required this.state});

  @override
  State<CoinsView> createState() => _CoinsViewState();
}

class _CoinsViewState extends State<CoinsView> {
  static const _kSortFieldKey = 'coin_sort_field';
  static const _kSortDirKey = 'coin_sort_dir';

  _CoinSortField _sortField = _CoinSortField.size;
  _CoinSortDir _sortDir = _CoinSortDir.desc;
  SharedPreferences? _prefs;
  List<APIUtxo>? _cachedSortedUtxos;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      _prefs = prefs;
      setState(() {
        _sortField = _CoinSortField.values.byName(
          prefs.getString(_kSortFieldKey) ?? _CoinSortField.size.name,
        );
        _sortDir = _CoinSortDir.values.byName(
          prefs.getString(_kSortDirKey) ?? _CoinSortDir.desc.name,
        );
        _cachedSortedUtxos = null;
      });
    });
  }

  @override
  void didUpdateWidget(CoinsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.utxos != widget.state.utxos) {
      _cachedSortedUtxos = null;
    }
  }

  Future<void> _setSort(_CoinSortField field, _CoinSortDir dir) async {
    setState(() {
      _sortField = field;
      _sortDir = dir;
      _cachedSortedUtxos = null;
    });
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(_kSortFieldKey, field.name);
    await prefs.setString(_kSortDirKey, dir.name);
  }

  List<APIUtxo> get _sortedUtxos {
    if (_cachedSortedUtxos != null) return _cachedSortedUtxos!;
    final list = List<APIUtxo>.from(widget.state.utxos);
    list.sort((a, b) {
      if (_sortField == _CoinSortField.size) {
        final cmp = a.valueSat.compareTo(b.valueSat);
        return _sortDir == _CoinSortDir.asc ? cmp : -cmp;
      } else {
        final aSpending =
            a.mempoolSpendingTxid != null || a.pendingPsbtIds.isNotEmpty;
        final bSpending =
            b.mempoolSpendingTxid != null || b.pendingPsbtIds.isNotEmpty;
        if (aSpending != bSpending) return aSpending ? -1 : 1;

        final aH = a.confirmationHeight;
        final bH = b.confirmationHeight;
        if (aH == null && bH == null) return 0;
        if (aH == null) return -1; // unconfirmed above confirmed
        if (bH == null) return 1;
        final cmp = bH.compareTo(aH);
        return _sortDir == _CoinSortDir.asc ? cmp : -cmp;
      }
    });
    return _cachedSortedUtxos = list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final network = widget.state.walletInfo.network;

    if (!widget.state.utxosLoaded) {
      return LoadingIndicator(message: l10n.loadingCoins);
    }

    final minBlocks =
        context.watch<SettingsCubit>().state.inheritanceMinTimelockBlocks;
    final isInheritance =
        widget.state.descriptorAnalysis?.spendPaths.any(
          (p) =>
              p.relTimelock.timelockType == APIRelativeTimelockType.blocks &&
              p.relTimelock.value >= minBlocks,
        ) ??
        false;

    final utxos = widget.state.utxos;
    final totalSats = utxos
        .where((u) => u.mempoolSpendingTxid == null && u.pendingPsbtIds.isEmpty)
        .fold<int>(0, (sum, u) => sum + u.valueSat.toInt());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.coinsSection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppAccent.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (utxos.isNotEmpty) ...[
              Text(
                l10n.coinTotalCount(utxos.length),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
              const SizedBox(width: 4),
              _SortButton(
                sortField: _sortField,
                sortDir: _sortDir,
                onSelected: _setSort,
              ),
            ],
          ],
        ),
        if (utxos.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            l10n.coinTotalValue(totalSats),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withAlpha(AppAlpha.secondary),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (utxos.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.noCoins,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
            ),
          )
        else
          ..._sortedUtxos.map(
            (utxo) => _CoinTile(
              utxo: utxo,
              network: network,
              spendPaths: widget.state.descriptorAnalysis?.spendPaths ?? [],
              tipHeight: widget.state.tipHeight,
              keyLabels: widget.state.keyLabels,
              currentBtcPrice: widget.state.currentBtcPrice,
              fiatCurrency: widget.state.fiatCurrency,
              walletState: widget.state,
              isInheritance: isInheritance,
            ),
          ),
      ],
    );
  }
}

typedef _SortChoice = ({_CoinSortField field, _CoinSortDir dir});

class _SortButton extends StatelessWidget {
  static const _choices = <_SortChoice>[
    (field: _CoinSortField.size, dir: _CoinSortDir.desc),
    (field: _CoinSortField.size, dir: _CoinSortDir.asc),
    (field: _CoinSortField.age, dir: _CoinSortDir.desc),
    (field: _CoinSortField.age, dir: _CoinSortDir.asc),
  ];

  final _CoinSortField sortField;
  final _CoinSortDir sortDir;
  final void Function(_CoinSortField, _CoinSortDir) onSelected;

  const _SortButton({
    required this.sortField,
    required this.sortDir,
    required this.onSelected,
  });

  String _choiceLabel(AppLocalizations l10n, _SortChoice c) =>
      switch ((c.field, c.dir)) {
        (_CoinSortField.size, _CoinSortDir.desc) => l10n.coinSortSizeDesc,
        (_CoinSortField.size, _CoinSortDir.asc) => l10n.coinSortSizeAsc,
        (_CoinSortField.age, _CoinSortDir.desc) => l10n.coinSortAgeDesc,
        (_CoinSortField.age, _CoinSortDir.asc) => l10n.coinSortAgeAsc,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;


    final fieldLabel = sortField == _CoinSortField.size
        ? l10n.coinSortLabelSize
        : l10n.coinSortLabelAge;
    final dirArrow = sortDir == _CoinSortDir.asc ? '↑' : '↓';

    return PopupMenuButton<_SortChoice>(
      onSelected: (c) => onSelected(c.field, c.dir),
      itemBuilder: (_) => _choices
          .map(
            (c) => CheckedPopupMenuItem<_SortChoice>(
              value: c,
              checked: c.field == sortField && c.dir == sortDir,
              child: Text(_choiceLabel(l10n, c)),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$dirArrow $fieldLabel',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withAlpha(AppAlpha.secondary),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withAlpha(AppAlpha.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinTile extends StatelessWidget {
  final APIUtxo utxo;
  final APINetwork network;
  final List<APISpendPath> spendPaths;
  final int tipHeight;
  final Map<String, String> keyLabels;
  final double? currentBtcPrice;
  final String? fiatCurrency;
  final WalletDetailLoaded walletState;
  final bool isInheritance;

  const _CoinTile({
    required this.utxo,
    required this.network,
    required this.spendPaths,
    required this.tipHeight,
    required this.keyLabels,
    required this.walletState,
    this.currentBtcPrice,
    this.fiatCurrency,
    this.isInheritance = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sats = utxo.valueSat.toInt();
    final isChange = utxo.keychain == APIKeychain.internal;

    final statuses = spendPaths.isEmpty
        ? <(APISpendPath, SpendPathStatus)>[]
        : spendPaths
              .map(
                (p) => (
                  p,
                  spendPathStatus(path: p, utxo: utxo, tipHeight: tipHeight),
                ),
              )
              .toList();

    final unlockedCount =
        statuses.where((s) => s.$2 is SpendPathUnlocked).length;
    final hasTimelocks = spendPaths.any(
      (p) => p.relTimelock.value > 0 || p.absTimelock.value > 0,
    );
    final label = utxo.effectiveLabel;
    final isInherited = utxo.isAuto;
    final amountStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: label != null ? 12 : null,
      color: label != null
          ? Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh)
          : null,
    );
    final isMempool = utxo.mempoolSpendingTxid != null;
    final isSpending = isMempool || utxo.pendingPsbtIds.isNotEmpty;

    final opacity = isMempool ? 0.35 : isSpending ? 0.55 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(
            isChange ? Icons.repeat : Icons.arrow_downward,
            color: isChange ? Colors.amber : Colors.green,
          ),
          onTap: () => _showDetails(context, statuses),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Row(
                  children: [
                    Icon(
                      isInherited ? Icons.label_outline : Icons.label,
                      size: 12,
                      color: isInherited
                          ? Theme.of(context).colorScheme.outline
                          : null,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isInherited ? null : FontWeight.w500,
                          fontStyle: isInherited ? FontStyle.italic : null,
                          color: isInherited
                              ? Theme.of(context).colorScheme.outline
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              Row(
                children: [
                  Text(
                    BitcoinFormatter.satsLabel(sats),
                    style: amountStyle,
                  ),
                  if (currentBtcPrice != null && fiatCurrency != null) ...[
                    const Spacer(),
                    Text(
                      BitcoinFormatter.formatSatsFiat(
                          sats, currentBtcPrice!, fiatCurrency!),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(AppAlpha.secondary),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ColoredGroupText(text: utxo.address, truncate: true),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (hasTimelocks && spendPaths.isNotEmpty)
                    SpendPathSummaryBadge(
                      unlockedCount: unlockedCount,
                      totalCount: spendPaths.length,
                      nearestUnlockBlocks: nearestUnlockBlocks(statuses),
                    ),
                  if (isMempool) ...[
                    if (hasTimelocks && spendPaths.isNotEmpty)
                      const SizedBox(width: 6),
                    StatusBadge(
                        label: l10n.coinMempoolSpend, color: Colors.red),
                  ] else if (utxo.pendingPsbtIds.isNotEmpty) ...[
                    if (hasTimelocks && spendPaths.isNotEmpty)
                      const SizedBox(width: 6),
                    StatusBadge(
                        label: l10n.coinPendingSpend, color: Colors.orange),
                  ],
                  if (!utxo.isConfirmed) ...[
                    const SizedBox(width: 6),
                    StatusBadge(
                      label: l10n.txUnconfirmed,
                      color: !isMempool ? AppAccent.color : Colors.grey,
                      icon: !isMempool ? Icons.trending_up : null,
                      onTap: !isMempool ? () => _openCpfpTx(context) : null,
                      tooltip: !isMempool ? l10n.cpfpAccelerate : null,
                    ),
                  ],
                  // Spaced-TX-plan reservation badge. Renders nothing
                  // until a TxPlanningCubit is provided (step 11) and
                  // this outpoint is one of the plan's children.
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: TxPlanningReservedBadge(
                      outpointKey: '${utxo.txid}:${utxo.vout}',
                    ),
                  ),
                  const Spacer(),
                  if (utxo.confirmationTime != null)
                    Text(
                      formatTimestamp(utxo.confirmationTime!.toInt()),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(AppAlpha.secondary),
                      ),
                    ),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isInheritance && !isSpending)
                IconButton(
                  icon: const Icon(Icons.update, size: 16),
                  tooltip: l10n.revaultNow,
                  onPressed: () => openRevaultTx(context, walletState, utxo),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    maxWidth: 32,
                    maxHeight: 32,
                  ),
                ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCpfpTx(BuildContext context) =>
      openCpfpTx(context, walletState, [utxo]);

  void _showDetails(
    BuildContext context,
    List<(APISpendPath, SpendPathStatus)> statuses,
  ) {
    showWalletDialog(
      context,
      CoinDetailDialog(
        utxo: utxo,
        network: network,
        spendPathStatuses: statuses,
        keyLabels: keyLabels,
      ),
    );
  }
}
