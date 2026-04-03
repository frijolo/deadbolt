import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/create_tx/create_tx_models.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:flutter/material.dart';

class CpfpBanner extends StatelessWidget {
  final APICpfpInfo? cpfpInfo;
  final bool cpfpInfoLoading;
  final TxSummary? txSummary;

  const CpfpBanner({
    super.key,
    required this.cpfpInfo,
    required this.cpfpInfoLoading,
    required this.txSummary,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accentColor = AppAccent.color;
    final cpfp = cpfpInfo;
    final summary = txSummary;

    String effectiveRateText = '—';
    if (cpfp != null && summary != null) {
      final ancestorFee = cpfp.ancestorFeeSat?.toInt();
      final ancestorVsize = cpfp.ancestorVsize.toInt();
      final childFee = summary.feeSats;
      final childVsize = (summary.totalWu / 4.0).ceil();
      if (ancestorFee != null && (ancestorVsize + childVsize) > 0) {
        final effectiveRate =
            (ancestorFee + childFee) / (ancestorVsize + childVsize);
        effectiveRateText = '${effectiveRate.toStringAsFixed(1)} sat/vB';
      }
    }

    final String ancestorFeeText;
    if (cpfp != null) {
      if (cpfp.ancestorFeeSat != null) {
        ancestorFeeText =
            '${cpfp.ancestorFeeSat} sats  (${cpfp.ancestorFeeRateSatPerVb.toStringAsFixed(1)} sat/vB, ${cpfp.ancestorVsize} vB)';
      } else {
        ancestorFeeText = l10n.rbfUnknownFee;
      }
    } else {
      ancestorFeeText = cpfpInfoLoading ? '…' : '—';
    }

    return Card(
      margin: EdgeInsets.zero,
      color: accentColor.withAlpha(AppAlpha.faint),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accentColor.withAlpha(AppAlpha.pale)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  l10n.cpfpBannerTitle,
                  style:
                      theme.textTheme.labelMedium?.copyWith(color: accentColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            rbfRow(
              l10n.cpfpParentFee,
              ancestorFeeText,
              colorScheme.onSurface.withAlpha(AppAlpha.secondary),
              theme,
            ),
            if (cpfp != null && cpfp.ancestorCount > 1) ...[
              const SizedBox(height: 4),
              rbfRow(
                l10n.cpfpAncestorCount,
                '${cpfp.ancestorCount}',
                colorScheme.onSurface.withAlpha(AppAlpha.secondary),
                theme,
              ),
            ],
            const SizedBox(height: 4),
            rbfRow(
              l10n.cpfpEffectiveRate,
              effectiveRateText,
              accentColor,
              theme,
            ),
          ],
        ),
      ),
    );
  }
}
