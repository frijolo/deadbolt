import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/mempool_blocks_service.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';

/// Collapsible histogram of projected mempool blocks, showing min fee (sat/vB)
/// per block. Tapping a bar sets that fee rate via [onFeeSelected].
///
/// Block 0 = next block to be mined ("Next"), block 1 = "+1", etc.
class FeeHistogramWidget extends StatefulWidget {
  const FeeHistogramWidget({
    super.key,
    required this.snapshot,
    required this.onFeeSelected,
    this.loading = false,
  });

  final MempoolBlocksSnapshot? snapshot;
  final bool loading;
  final void Function(double satPerVb) onFeeSelected;

  @override
  State<FeeHistogramWidget> createState() => _FeeHistogramWidgetState();
}

class _FeeHistogramWidgetState extends State<FeeHistogramWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    if (!widget.loading && snapshot == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final next = snapshot?.blocks.isNotEmpty == true
        ? snapshot!.blocks.first
        : null;
    final feeRange = (next != null && next.minFee > 0)
        ? '${BitcoinFormatter.formatFeeRate(next.minFee)} ~ ${BitcoinFormatter.formatFeeRate(next.p75Fee)} sat/vB'
        : null;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: Row(
          children: [
            Text(
              l10n.feeHistogramTitle,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            if (feeRange != null)
              Text(
                feeRange,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        children: [
          if (widget.loading && snapshot == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (snapshot != null)
            _FeeHistogramChart(
              snapshot: snapshot,
              onFeeSelected: widget.onFeeSelected,
            ),
        ],
      ),
    );
  }
}


class _FeeHistogramChart extends StatelessWidget {
  const _FeeHistogramChart({
    required this.snapshot,
    required this.onFeeSelected,
  });

  final MempoolBlocksSnapshot snapshot;
  final void Function(double) onFeeSelected;

  static const _chartHeight = 72.0;
  static const _minBarHeight = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final projected = snapshot.blocks;
    if (projected.isEmpty) return const SizedBox.shrink();

    final maxFee =
        projected.map((b) => b.minFee).reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(projected.length, (i) {
          final block = projected[i];
          final fee = block.minFee;
          final fraction =
              maxFee > 0 ? (fee / maxFee).clamp(0.0, 1.0) : 1.0;
          final barH =
              _minBarHeight + (_chartHeight - _minBarHeight) * fraction;

          // Next block uses tertiary (urgent), subsequent blocks use primary.
          final barColor = i == 0
              ? theme.colorScheme.tertiary
              : theme.colorScheme.primary
                  .withValues(alpha: 0.65 - 0.08 * i);

          final label =
              i == 0 ? l10n.feeHistogramNext : '+$i';

          return Expanded(
            child: GestureDetector(
              onTap: () => onFeeSelected(fee),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    BitcoinFormatter.formatFeeRate(fee),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: barH,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: i == 0
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
