import 'dart:math' show max;

import 'package:deadbolt/screens/create_tx/create_tx_models.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';

class RbfCard extends StatelessWidget {
  final Map<String, APIRbfInfo?> rbfInfos;
  final String feeRateText;
  final TxSummary? txSummary;

  const RbfCard({
    super.key,
    required this.rbfInfos,
    required this.feeRateText,
    required this.txSummary,
  });

  int _totalConflictFee(List<APIRbfInfo> infos) => infos.fold<int>(
        0,
        (s, i) => s + i.origFeeSat.toInt() + (i.descendantFeeSat?.toInt() ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final resolvedInfos = rbfInfos.values.whereType<APIRbfInfo>().toList();
    final hasLoading = rbfInfos.values.any((v) => v == null);

    final maxOrigRate = resolvedInfos.fold<double>(
      0.0,
      (m, i) => max(m, i.minFeeRateSatPerVb),
    );
    final currentRate = double.tryParse(feeRateText) ?? 0.0;
    final rateTooLow = resolvedInfos.isNotEmpty && currentRate <= maxOrigRate;

    final summary = txSummary;
    final totalConflictFee = _totalConflictFee(resolvedInfos);
    final int? actualNewVsize =
        summary != null ? (summary.totalWu / 4.0).ceil() : null;
    final int minFeeSat = actualNewVsize != null
        ? totalConflictFee + actualNewVsize
        : resolvedInfos.fold<int>(0, (m, i) => max(m, i.minFeeSat.toInt()));
    final bool absFeeTooLow = resolvedInfos.isNotEmpty &&
        summary != null &&
        !summary.insufficientFunds &&
        summary.feeSats <= minFeeSat;

    final bool feeTooLow = rateTooLow || absFeeTooLow;
    const accentColor = AppAccent.color;
    final warningColor = feeTooLow ? colorScheme.error : accentColor;

    final bgColor = theme.brightness == Brightness.light
        ? Color.lerp(colorScheme.primaryContainer, Colors.white, 0.5)!
        : colorScheme.surfaceContainerHigh;

    return Card(
      margin: EdgeInsets.zero,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(AppAlpha.medium)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: warningColor),
                const SizedBox(width: 6),
                Text(
                  l10n.rbfWarningTitle,
                  style: theme.textTheme.labelMedium?.copyWith(color: warningColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (resolvedInfos.isEmpty && hasLoading)
              Text(
                l10n.rbfUnknownFee,
                style: theme.textTheme.bodySmall,
              )
            else if (resolvedInfos.isNotEmpty) ...[
              Builder(builder: (ctx) {
                final info = resolvedInfos.reduce(
                  (a, b) => b.origFeeSat > a.origFeeSat ? b : a,
                );
                final dimColor =
                    theme.colorScheme.onSurface.withAlpha(AppAlpha.secondary);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rbfRow(
                      l10n.rbfOriginalFee,
                      '${info.origFeeSat} sats  (${info.origFeeRateSatPerVb.toStringAsFixed(1)} sat/vB, ${info.origVsize} vB)',
                      dimColor,
                      theme,
                    ),
                    if (info.descendantCount > 0) ...[
                      const SizedBox(height: 4),
                      rbfRow(
                        l10n.rbfDescendants,
                        info.descendantFeeSat != null
                            ? '${info.descendantCount} tx${info.descendantCount > 1 ? 's' : ''}, ${info.descendantFeeSat} sats'
                            : '${info.descendantCount} tx${info.descendantCount > 1 ? 's' : ''} (fee unknown)',
                        dimColor,
                        theme,
                      ),
                    ],
                    const SizedBox(height: 4),
                    rbfRow(
                      l10n.rbfMinFee,
                      '> $minFeeSat sats${actualNewVsize == null ? ' ~' : ''}',
                      absFeeTooLow ? warningColor : dimColor,
                      theme,
                    ),
                    const SizedBox(height: 4),
                    rbfRow(
                      l10n.rbfMinRate,
                      '> ${maxOrigRate.toStringAsFixed(1)} sat/vB',
                      rateTooLow ? warningColor : dimColor,
                      theme,
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
