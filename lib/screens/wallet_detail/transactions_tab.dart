import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/config/app_settings_extensions.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/psbt_detail_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/psbt_timelock.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/screens/wallet_detail/wallet_detail_shared.dart';

// ─────────────────────────────────────────────────────────────
// Transactions view (tab 1)
// ─────────────────────────────────────────────────────────────

class TransactionsView extends StatelessWidget {
  final WalletDetailLoaded state;

  const TransactionsView({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final network = state.walletInfo.network;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.transactionsSection,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppAccent.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // ── Unsigned transactions (PSBTs) ──────────────────────────────────
        ...state.psbts.map((psbt) {
          final analysis = state.psbtAnalyses[psbt.id.toInt()];
          return _PsbtTile(
            psbt: psbt,
            analysis: analysis,
            spendPaths: state.descriptorAnalysis?.spendPaths ?? [],
            keyLabels: state.keyLabels,
            pathLabels: state.pathLabels,
            tipHeight: state.tipHeight,
            network: network,
          );
        }),

        // ── Confirmed / mempool transactions ───────────────────────────────
        if (state.transactions.isEmpty && state.psbts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.noTransactions,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
            ),
          )
        else ...[
          Builder(builder: (ctx) {
            // Build a map of unconfirmed UTXOs per parent txid so each tile
            // can show the "Accelerate" button when it has spendable outputs.
            // Exclude UTXOs already spent by another mempool tx — spending them
            // would be an involuntary RBF, not a pure CPFP.
            final unconfirmedUtxosByTxid = <String, List<APIUtxo>>{};
            for (final u in state.utxos) {
              if (!u.isConfirmed && u.mempoolSpendingTxid == null) {
                unconfirmedUtxosByTxid.putIfAbsent(u.txid, () => []).add(u);
              }
            }
            final sorted = [...state.transactions]..sort((a, b) {
              final aConfirmed = a.confirmationHeight != null;
              final bConfirmed = b.confirmationHeight != null;
              if (aConfirmed != bConfirmed) return aConfirmed ? 1 : -1;
              if (!aConfirmed) return a.txid.compareTo(b.txid);
              final cmp = b.confirmationHeight!.compareTo(a.confirmationHeight!);
              if (cmp != 0) return cmp;
              return a.txid.compareTo(b.txid);
            });
            return Column(
              children: sorted.map((tx) {
                final cpfpUtxos = tx.confirmationHeight == null
                    ? (unconfirmedUtxosByTxid[tx.txid] ?? [])
                    : <APIUtxo>[];
                return _TransactionTile(
                  tx: tx,
                  network: network,
                  fiatPrice: state.fiatPrices[tx.txid],
                  fiatCurrency: state.fiatCurrency,
                  cpfpUtxos: cpfpUtxos,
                  walletState: state,
                );
              }).toList(),
            );
          }),
          if (state.hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton(
                onPressed: () =>
                    context.read<WalletDetailCubit>().loadMoreTransactions(),
                child: Text(l10n.loadMore),
              ),
            ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Transaction tile
// ─────────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final APITransaction tx;
  final APINetwork network;
  final double? fiatPrice;
  final String? fiatCurrency;
  final List<APIUtxo> cpfpUtxos;
  final WalletDetailLoaded walletState;

  const _TransactionTile({
    required this.tx,
    required this.network,
    required this.walletState,
    this.fiatPrice,
    this.fiatCurrency,
    this.cpfpUtxos = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fee = tx.fee;
    final isSelfTransfer = tx.sent > BigInt.zero &&
        tx.received > BigInt.zero &&
        fee != null &&
        tx.sent - tx.received == fee;
    final isReceived = !isSelfTransfer && tx.received > tx.sent;
    final netSats = BitcoinFormatter.signedNetSats(
      isSelfTransfer: isSelfTransfer,
      isReceived: isReceived,
      feeSat: fee?.toInt() ?? 0,
      sentSat: tx.sent.toInt(),
      receivedSat: tx.received.toInt(),
    );
    final txType = isSelfTransfer
        ? l10n.txSelfTransfer
        : isReceived
        ? l10n.txReceived
        : l10n.txSent;
    final label = tx.effectiveLabel;
    final isInherited = tx.isAuto;
    final txColor = isSelfTransfer
        ? Colors.blue
        : isReceived
        ? Colors.green
        : Colors.orange;

    final canCpfp = cpfpUtxos.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isSelfTransfer
              ? Icons.swap_horiz
              : isReceived
              ? Icons.arrow_downward
              : Icons.arrow_upward,
          color: txColor,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Row(
                children: [
                  Icon(
                    isInherited ? Icons.label_outline : Icons.label,
                    size: 12,
                    color:
                        isInherited ? Theme.of(context).colorScheme.outline : null,
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
            if (label == null)
              Text(
                txType,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
          ],
        ),
        subtitle: Text(
          BitcoinFormatter.satsLabel(netSats, showSign: true),
          style: TextStyle(color: txColor, fontWeight: FontWeight.w600),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (tx.confirmationTime != null)
                  Text(
                    formatTimestamp(tx.confirmationTime!.toInt()),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(AppAlpha.secondary),
                    ),
                  )
                else
                  StatusBadge(
                    label: l10n.txUnconfirmed,
                    color: canCpfp ? AppAccent.color : Colors.grey,
                    icon: canCpfp ? Icons.trending_up : null,
                    onTap: canCpfp ? () => _openCpfpTx(context) : null,
                    tooltip: canCpfp ? l10n.cpfpAccelerate : null,
                  ),
                if (fiatPrice != null && fiatCurrency != null)
                  Text(
                    BitcoinFormatter.formatSatsFiat(
                      netSats,
                      fiatPrice!,
                      fiatCurrency!,
                    ),
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
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
        onTap: () => _showDetails(context, isSelfTransfer, isReceived, netSats),
      ),
    );
  }

  Future<void> _openCpfpTx(BuildContext context) =>
      openCpfpTx(context, walletState, cpfpUtxos);

  void _showDetails(
    BuildContext context,
    bool isSelfTransfer,
    bool isReceived,
    int netSats,
  ) {
    showWalletDialog(
      context,
      TxDetailDialog(
        tx: tx,
        network: network,
        isSelfTransfer: isSelfTransfer,
        isReceived: isReceived,
        netSats: netSats,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PSBT tile — shown at the top of the transactions tab
// ─────────────────────────────────────────────────────────────

class _PsbtTile extends StatelessWidget {
  final APIPsbtInfo psbt;
  final APIPsbtAnalysis? analysis;
  final List<APISpendPath> spendPaths;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;
  final int tipHeight;
  final APINetwork network;

  const _PsbtTile({
    required this.psbt,
    required this.analysis,
    required this.spendPaths,
    required this.keyLabels,
    required this.pathLabels,
    required this.tipHeight,
    required this.network,
  });

  bool get _isFinalized => psbt.isReadyToBroadcast(analysis);

  Future<void> _broadcast(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<WalletDetailCubit>();
    final settings = context.read<SettingsCubit>().state;
    final electrumUrl = settings.electrumUrlForNetwork(network);
    try {
      final txid = await cubit.broadcastPsbt(psbt.id.toInt(), electrumUrl);
      if (!context.mounted) return;
      if (txid != null) showSuccessToast(l10n.psbtBroadcastSuccess(txid));
    } catch (e) {
      if (context.mounted) showErrorToastException(e);
    }
  }

  Widget _buildActionIcon(BuildContext context) {
    final l10n = context.l10n;
    final eta = psbt.unlockEta(tipHeight);
    if (eta != null) {
      final queued = psbt.autoBroadcast;
      final locked = l10n.psbtLockedTooltip(
        formatShortSlashed(eta),
        psbt.blocksLeft(tipHeight),
      );
      final tooltip = queued
          ? '${l10n.psbtAutoBroadcastQueuedTooltip} · $locked'
          : locked;
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            queued ? Icons.schedule_send_outlined : Icons.hourglass_bottom,
            size: 18,
            color: queued ? Colors.blue : Colors.orange,
          ),
        ),
      );
    }
    return IconButton(
      tooltip: l10n.psbtBroadcastReady,
      icon: const Icon(Icons.send, size: 18, color: Colors.green),
      onPressed: () => _broadcast(context),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
    );
  }

  String _statusLabel(BuildContext context, int signedCount) {
    final l10n = context.l10n;
    if (psbt.hasSpentInputs) return l10n.psbtStatusSpent;
    if (analysis == null) return l10n.psbtStatusUnsigned;
    if (_isFinalized) return l10n.psbtStatusSigned;
    if (signedCount > 0) return l10n.psbtStatusPartial;
    return l10n.psbtStatusUnsigned;
  }

  Color _statusColor(int signedCount) {
    if (psbt.hasSpentInputs) return Colors.red;
    if (analysis == null) return AppAccent.color;
    if (_isFinalized) return Colors.green;
    if (signedCount > 0) return Colors.amber;
    return AppAccent.color;
  }

  APISpendPath? _findSpendPath() {
    try {
      return spendPaths.firstWhere((p) => p.id == psbt.spendPathId.toInt());
    } catch (_) {
      return spendPaths.isNotEmpty ? spendPaths.first : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final signedCount =
        analysis?.signers.where((s) => s.hasSigned).length ?? 0;
    final statusColor = _statusColor(signedCount);
    final statusLabel = _statusLabel(context, signedCount);
    final isSelfTransfer = psbt.isSelfTransfer;
    final effectiveLabel = psbt.effectiveLabel;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.lock_clock_outlined, color: AppAccent.color),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (effectiveLabel != null)
              Row(
                children: [
                  Icon(
                    psbt.isAuto ? Icons.label_outline : Icons.label,
                    size: 12,
                    color: psbt.isAuto ? theme.colorScheme.outline : null,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      effectiveLabel,
                      style: TextStyle(
                        fontWeight: psbt.isAuto ? null : FontWeight.w500,
                        fontStyle: psbt.isAuto ? FontStyle.italic : null,
                        color: psbt.isAuto ? theme.colorScheme.outline : null,
                      ),
                    ),
                  ),
                ],
              ),
            if (effectiveLabel == null)
              Text(
                isSelfTransfer ? l10n.txSelfTransfer : l10n.txSent,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              ),
          ],
        ),
        subtitle: Text(
          BitcoinFormatter.satsLabel(
            BitcoinFormatter.signedNetSats(
              isSelfTransfer: isSelfTransfer,
              isReceived: false,
              feeSat: psbt.feeSat.toInt(),
              sentSat: psbt.amountSat.toInt(),
              receivedSat: 0,
            ),
            showSign: true,
          ),
          style: const TextStyle(
            color: AppAccent.color,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(AppAlpha.dim),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(fontSize: 10, color: statusColor),
              ),
            ),
            const SizedBox(width: 4),
            if (_isFinalized && !psbt.hasSpentInputs) _buildActionIcon(context),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<WalletDetailCubit>(),
                child: PsbtDetailScreen(
                  psbt: psbt,
                  spendPath: _findSpendPath(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
