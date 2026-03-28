import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';
import 'package:deadbolt/screens/wallet_detail/wallet_detail_shared.dart';

// ─────────────────────────────────────────────────────────────
// Coins (UTXOs) view (tab 3) — with coin control selection
// ─────────────────────────────────────────────────────────────

class CoinsView extends StatelessWidget {
  final WalletDetailLoaded state;

  const CoinsView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final network = state.walletInfo.network;

    if (!state.utxosLoaded) {
      return LoadingIndicator(message: l10n.loadingCoins);
    }

    final utxos = state.utxos;
    final totalSats = utxos.fold<int>(0, (sum, u) => sum + u.valueSat.toInt());

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
            if (utxos.isNotEmpty)
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
          ...utxos.map(
            (utxo) => _CoinTile(
              utxo: utxo,
              network: network,
              spendPaths: state.descriptorAnalysis?.spendPaths ?? [],
              tipHeight: state.tipHeight,
              keyLabels: state.keyLabels,
              currentBtcPrice: state.currentBtcPrice,
              fiatCurrency: state.fiatCurrency,
              walletState: state,
            ),
          ),
      ],
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

  const _CoinTile({
    required this.utxo,
    required this.network,
    required this.spendPaths,
    required this.tipHeight,
    required this.keyLabels,
    required this.walletState,
    this.currentBtcPrice,
    this.fiatCurrency,
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
          leading: CircleAvatar(
            backgroundColor: isChange
                ? Colors.amber.withAlpha(AppAlpha.dim)
                : Colors.green.withAlpha(AppAlpha.dim),
            child: Icon(
              isChange ? Icons.repeat : Icons.arrow_downward,
              size: 18,
              color: isChange ? Colors.amber : Colors.green,
            ),
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
                    '${BitcoinFormatter.formatNum(sats)} sats',
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
                  StatusBadge(
                    label: isChange
                        ? l10n.coinKeychainChange
                        : l10n.coinKeychainReceive,
                    color: isChange ? Colors.amber : Colors.green,
                  ),
                  if (hasTimelocks && spendPaths.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    SpendPathSummaryBadge(
                      unlockedCount: unlockedCount,
                      totalCount: spendPaths.length,
                    ),
                  ],
                  if (isMempool) ...[
                    const SizedBox(width: 6),
                    StatusBadge(
                        label: l10n.coinMempoolSpend, color: Colors.red),
                  ] else if (utxo.pendingPsbtIds.isNotEmpty) ...[
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
                ],
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
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
