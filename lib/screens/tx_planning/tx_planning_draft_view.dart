import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_hw_batch_sheet.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_qr_sign_view.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_sign_mfp_sheet.dart';
import 'package:deadbolt/src/rust/api/model.dart'
    show APIHotKeyInfo, APIPsbtSignerStatus, APISpendPath;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/toast_helper.dart'
    show showErrorToast, showErrorToastException;
import 'package:deadbolt/utils/date_format.dart' show etaFromBlocks, formatDateTime;
import 'package:deadbolt/widgets/mfp_badge.dart';

/// Draft view: per-row status badges + a bottom action bar that drives
/// the full sign-then-commit flow with two confirmation gates (sign
/// batch + commit). Signing each row individually via the PSBT detail
/// screen is no longer required.
class TxPlanningDraftView extends StatelessWidget {
  final APISpacedPlanDetail detail;
  final APICommitSpacedPlanReport? lastCommitReport;
  final Map<int, List<APIPsbtSignerStatus>>? signers;
  /// Plan-level signing threshold (`m` in `m-of-n`). Must travel
  /// alongside [signers]; falls back to `n` when missing so the view
  /// stays safe even if the snapshot fetch failed.
  final int? signersThreshold;
  final List<APIHotKeyInfo> hotKeys;
  /// Current chain tip. `0` when the wallet is not yet synced — the
  /// commit dialog falls back to a tip-unknown message in that case
  /// instead of showing "broadcast in 1970".
  final int tipHeight;
  final APISpendPath? spendPath;
  final Map<String, String> keyLabels;

  const TxPlanningDraftView({
    super.key,
    required this.detail,
    required this.hotKeys,
    required this.tipHeight,
    required this.keyLabels,
    this.spendPath,
    this.lastCommitReport,
    this.signers,
    this.signersThreshold,
  });

  @override
  Widget build(BuildContext context) {
    final totalFee = detail.rows.fold<BigInt>(
      BigInt.zero,
      (acc, r) => acc + r.feeSat,
    );
    final totalAmount = detail.rows.fold<BigInt>(
      BigInt.zero,
      (acc, r) => acc + r.amountSat,
    );
    final allSigned = _allSigned();
    final fullySignedPsbts = _fullySignedPsbtCount();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary(
                  context,
                  totalFee: totalFee,
                  totalAmount: totalAmount,
                  signedPsbts: fullySignedPsbts,
                ),
                if (lastCommitReport != null) ...[
                  const SizedBox(height: 12),
                  _legacyCommitBanner(context, lastCommitReport!),
                ],
                const SizedBox(height: 16),
                _signersSection(context, totalFee: totalFee),
              ],
            ),
          ),
        ),
        _actions(context, totalFee, allSigned: allSigned),
      ],
    );
  }

  Widget _summary(
    BuildContext context, {
    required BigInt totalFee,
    required BigInt totalAmount,
    required int signedPsbts,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.txPlanningPlanHeader(
                detail.planId.toInt(),
                formatPlanKindLabel(context, detail, l10n),
              ),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _summaryRow(
              context,
              l10n.txPlanningSummaryCoins,
              detail.rows.length.toString(),
            ),
            _summaryRow(
              context,
              l10n.txPlanningSummaryTotalAmount,
              BitcoinFormatter.satsLabel(totalAmount.toInt()),
            ),
            _summaryRow(
              context,
              l10n.txPlanningSummaryTotalFee,
              BitcoinFormatter.satsLabel(totalFee.toInt()),
            ),
            _summaryRow(
              context,
              l10n.txPlanningSummarySigned,
              '$signedPsbts / ${detail.rows.length}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(AppAlpha.medium),
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signersSection(BuildContext context, {required BigInt totalFee}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sp = spendPath;
    final mfps = sp?.mfps ?? _fallbackMfps();
    final threshold = sp?.threshold ?? mfps.length;
    final total = detail.rows.length;
    final fullySigned = mfps.where((m) => _mfpSignedCount(m) == total).length;
    final hotKeyMfps = hotKeys.map((k) => k.mfp).toSet();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.txPlanningSignersTitle(fullySigned, threshold),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '$threshold-of-${mfps.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(AppAlpha.medium),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...mfps.map((mfp) => _PlanSignerRow(
                  mfp: mfp,
                  label: keyLabels[mfp],
                  signedCount: _mfpSignedCount(mfp),
                  totalCount: total,
                  onSign: () => _openSignSheet(
                    context,
                    mfp: mfp,
                    hasHotKey: hotKeyMfps.contains(mfp),
                    totalFee: totalFee,
                  ),
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _signWithHw(context),
                icon: const Icon(Icons.hardware_outlined, size: 18),
                label: Text(l10n.signWithHwWallet),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _fallbackMfps() {
    final snap = signers;
    if (snap == null) return const [];
    for (final row in detail.rows) {
      final perRow = snap[row.psbtId.toInt()];
      if (perRow != null && perRow.isNotEmpty) {
        return perRow.map((s) => s.mfp).toList();
      }
    }
    return const [];
  }

  int _mfpSignedCount(String mfp) {
    final snap = signers;
    if (snap == null) return 0;
    var count = 0;
    for (final row in detail.rows) {
      final perRow = snap[row.psbtId.toInt()];
      if (perRow == null) continue;
      if (perRow.any((s) => s.mfp == mfp && s.hasSigned)) count++;
    }
    return count;
  }

  int _fullySignedPsbtCount() {
    final snap = signers;
    if (snap == null) return 0;
    var count = 0;
    for (final row in detail.rows) {
      final perRow = snap[row.psbtId.toInt()];
      if (perRow == null) continue;
      final threshold = _planThreshold(perRow);
      final signed = perRow.where((s) => s.hasSigned).length;
      if (signed >= threshold) count++;
    }
    return count;
  }

  /// Fallback banner shown when the user pressed Commit before signing
  /// anything via the batch flow — preserved so existing manual-sign
  /// behaviour keeps surfacing the unsigned count.
  Widget _legacyCommitBanner(
    BuildContext context,
    APICommitSpacedPlanReport r,
  ) {
    if (r.committed) return const SizedBox.shrink();
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        color: cs.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.draw),
          title: Text(l10n.txPlanningSignedRatio(r.signedCount, r.totalCount)),
          subtitle:
              Text(l10n.txPlanningUnsignedRemaining(r.unsignedPsbtIds.length)),
        ),
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    BigInt totalFee, {
    required bool allSigned,
  }) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _confirmCancel(context),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.cancel),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: allSigned
                  ? () => _confirmAndCommit(context, totalFee)
                  : null,
              icon: const Icon(Icons.check),
              label: Text(l10n.txPlanningCommitArmButton),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmBatchSign(
    BuildContext context, {
    required BigInt totalFee,
    required String signerLabel,
  }) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.txPlanningConfirmBatchTitle(detail.rows.length)),
        content: Text(
          l10n.txPlanningConfirmBatchBody(totalFee.toString(), signerLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.txPlanningSignAllButton),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _openSignSheet(
    BuildContext context, {
    required String mfp,
    required bool hasHotKey,
    required BigInt totalFee,
  }) async {
    final channel = await showTxPlanningSignMfpSheet(
      context,
      mfp: mfp,
      label: keyLabels[mfp],
      hasHotKey: hasHotKey,
    );
    if (channel == null || !context.mounted) return;
    switch (channel) {
      case TxPlanningSignChannel.hotKey:
        await _confirmAndSignWithHotKey(
          context,
          mfp: mfp,
          totalFee: totalFee,
        );
      case TxPlanningSignChannel.qr:
        await _signWithQr(context, mfp: mfp);
    }
  }

  Future<void> _signWithQr(
    BuildContext context, {
    required String mfp,
  }) async {
    final cubit = context.read<TxPlanningCubit>();
    final APISpacedPlanSigningBundle? bundle;
    try {
      bundle = await cubit.prepareForBatchSigning();
    } catch (e) {
      showErrorToastException(e);
      return;
    }
    if (bundle == null || !context.mounted) return;
    await TxPlanningQrSignView.push(
      context,
      bundle: bundle,
      activeMfp: mfp,
    );
  }

  Future<void> _signWithHw(BuildContext context) async {
    final cubit = context.read<TxPlanningCubit>();
    final APISpacedPlanSigningBundle? bundle;
    try {
      bundle = await cubit.prepareForBatchSigning();
    } catch (e) {
      showErrorToastException(e);
      return;
    }
    if (bundle == null || !context.mounted) return;
    await showTxPlanningHwBatchSheet(context, bundle: bundle);
  }

  Future<void> _confirmAndSignWithHotKey(
    BuildContext context, {
    required String mfp,
    required BigInt totalFee,
  }) async {
    final l10n = context.l10n;
    final ok = await _confirmBatchSign(
      context,
      totalFee: totalFee,
      signerLabel: l10n.txPlanningSignerHotKey(mfp),
    );
    if (!ok || !context.mounted) return;
    try {
      final report =
          await context.read<TxPlanningCubit>().signBatchWithHotKey(mfp);
      if (report != null && report.failed.isNotEmpty) {
        showErrorToast(l10n.txPlanningBatchFailures(report.failed.length));
      }
    } catch (e) {
      showErrorToastException(e);
    }
  }

  Future<void> _confirmAndCommit(BuildContext context, BigInt totalFee) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.txPlanningConfirmCommitTitle(detail.rows.length)),
        content: Text(_commitDialogBody(context, totalFee)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.txPlanningCommitConfirmButton),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await context.read<TxPlanningCubit>().commit();
      } catch (e) {
        showErrorToastException(e);
      }
    }
  }

  /// Best-effort body text for the commit dialog. When the wallet is
  /// still syncing (tip = 0) we can't project absolute heights to
  /// wall-clock; surface the tip-unknown copy so the user knows the
  /// totals but not the broadcast window.
  String _commitDialogBody(BuildContext context, BigInt totalFee) {
    final l10n = context.l10n;
    if (tipHeight <= 0 || detail.rows.isEmpty) {
      return l10n.txPlanningConfirmCommitBodyTipUnknown(totalFee.toString());
    }
    int minLock = detail.rows.first.absNlocktime;
    int maxLock = minLock;
    for (final row in detail.rows) {
      if (row.absNlocktime < minLock) minLock = row.absNlocktime;
      if (row.absNlocktime > maxLock) maxLock = row.absNlocktime;
    }
    final earliestDelta = (minLock - tipHeight).clamp(0, 1 << 31);
    final latestDelta = (maxLock - tipHeight).clamp(0, 1 << 31);
    final earliest = formatDateTime(etaFromBlocks(earliestDelta));
    final latest = formatDateTime(etaFromBlocks(latestDelta));
    return l10n.txPlanningConfirmCommitBody(
      totalFee.toString(),
      earliest,
      latest,
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.txPlanningCancelDialogTitle),
        content: Text(l10n.txPlanningCancelDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.txPlanningKeepButton),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await context.read<TxPlanningCubit>().cancel();
      } catch (e) {
        showErrorToastException(e);
      }
    }
  }

  bool _allSigned() {
    final snap = signers;
    if (snap == null) return false;
    for (final row in detail.rows) {
      final perRow = snap[row.psbtId.toInt()];
      if (perRow == null) return false;
      final threshold = _planThreshold(perRow);
      final count = perRow.where((s) => s.hasSigned).length;
      if (count < threshold) return false;
    }
    return true;
  }

  /// Plan-level `m` from the signing bundle. Falls back to `n` (the
  /// number of signers in the row) when the bundle snapshot didn't
  /// reach the state — that's a strict overestimate, so Commit can
  /// only be blocked, never spuriously enabled.
  int _planThreshold(List<APIPsbtSignerStatus> perRow) {
    final t = signersThreshold;
    if (t != null && t > 0) return t;
    return perRow.isEmpty ? 1 : perRow.length;
  }

}

class _PlanSignerRow extends StatelessWidget {
  final String mfp;
  final String? label;
  final int signedCount;
  final int totalCount;
  final VoidCallback onSign;

  const _PlanSignerRow({
    required this.mfp,
    required this.label,
    required this.signedCount,
    required this.totalCount,
    required this.onSign,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fullySigned = totalCount > 0 && signedCount == totalCount;
    final partial = signedCount > 0 && !fullySigned;
    final Color color;
    final IconData icon;
    if (fullySigned) {
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (partial) {
      color = Colors.orange;
      icon = Icons.adjust;
    } else {
      color = theme.colorScheme.outline;
      icon = Icons.radio_button_unchecked;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          MfpBadge(
            label: mfp.substring(0, 8).toUpperCase(),
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          if (label != null)
            Expanded(
              child: Text(label!, overflow: TextOverflow.ellipsis),
            )
          else
            const Spacer(),
          Text(
            '$signedCount / $totalCount',
            style: TextStyle(color: color, fontSize: 12),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.signButton,
            onPressed: fullySigned ? null : onSign,
            icon: const Icon(Icons.draw_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}
