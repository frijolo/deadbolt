import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/psbt_detail_screen.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
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
          ...([...state.transactions]..sort((a, b) {
                final aConfirmed = a.confirmationHeight != null;
                final bConfirmed = b.confirmationHeight != null;
                if (aConfirmed != bConfirmed) return aConfirmed ? 1 : -1;
                if (!aConfirmed) return a.txid.compareTo(b.txid);
                final cmp = b.confirmationHeight!
                    .compareTo(a.confirmationHeight!);
                if (cmp != 0) return cmp;
                return a.txid.compareTo(b.txid);
              }))
              .map((tx) => _TransactionTile(tx: tx, network: network)),
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

  const _TransactionTile({required this.tx, required this.network});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fee = tx.fee;
    final isSelfTransfer = tx.sent > BigInt.zero &&
        tx.received > BigInt.zero &&
        fee != null &&
        tx.sent - tx.received == fee;
    final isReceived = !isSelfTransfer && tx.received > tx.sent;
    final netSats = isSelfTransfer
        ? fee.toInt()
        : (isReceived ? tx.received - tx.sent : tx.sent - tx.received).toInt();
    final txType = isSelfTransfer
        ? l10n.txSelfTransfer
        : isReceived
        ? l10n.txReceived
        : l10n.txSent;
    final label = tx.effectiveLabel;
    final isInherited = tx.isAuto;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isSelfTransfer
              ? Icons.swap_horiz
              : isReceived
              ? Icons.arrow_downward
              : Icons.arrow_upward,
          color: isSelfTransfer
              ? Colors.blue
              : isReceived
              ? Colors.green
              : Colors.orange,
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
          isSelfTransfer
              ? '-${BitcoinFormatter.formatNum(netSats)} sats'
              : '${isReceived ? '+' : '-'}${BitcoinFormatter.formatNum(netSats)} sats',
          style: TextStyle(
            color: isSelfTransfer
                ? Colors.blue
                : isReceived
                ? Colors.green
                : Colors.orange,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tx.confirmationTime != null)
              Text(
                _formatTimestamp(tx.confirmationTime!),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(AppAlpha.secondary),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(AppAlpha.dim),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.txUnconfirmed,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
        onTap: () => _showDetails(context, isSelfTransfer, isReceived, netSats),
      ),
    );
  }

  String _formatTimestamp(BigInt unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds.toInt() * 1000,
      isUtc: false,
    );
    final y = dt.year.toString();
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$y/$mo/$d $h:$mi';
  }

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

  const _PsbtTile({
    required this.psbt,
    required this.analysis,
    required this.spendPaths,
    required this.keyLabels,
    required this.pathLabels,
  });

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    if (psbt.hasSpentInputs) return l10n.psbtStatusSpent;
    if (analysis == null) return l10n.psbtStatusUnsigned;
    final signed = analysis!.signers.where((s) => s.hasSigned).length;
    if (analysis!.isFinalized || signed >= psbt.threshold.toInt()) {
      return l10n.psbtStatusSigned;
    }
    if (signed > 0) return l10n.psbtStatusPartial;
    return l10n.psbtStatusUnsigned;
  }

  Color _statusColor(BuildContext context) {
    if (psbt.hasSpentInputs) return Colors.red;
    if (analysis == null) return AppAccent.color;
    final signed = analysis!.signers.where((s) => s.hasSigned).length;
    if (analysis!.isFinalized || signed >= psbt.threshold.toInt()) {
      return Colors.green;
    }
    if (signed > 0) return Colors.amber;
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
    final statusColor = _statusColor(context);
    final statusLabel = _statusLabel(context);
    final isSelfTransfer = psbt.isSelfTransfer;
    final effectiveLabel = psbt.effectiveLabel;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.lock_clock_outlined, color: AppAccent.color),
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
          '-${BitcoinFormatter.formatNum(psbt.amountSat.toInt())} sats',
          style: TextStyle(
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
