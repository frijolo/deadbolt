import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:flutter/material.dart';

class SelectedPathCard extends StatelessWidget {
  final APISpendPath path;
  final int tipHeight;
  final int? utxoMaxConfHeight;
  final Map<String, String> keyLabels;

  const SelectedPathCard({
    super.key,
    required this.path,
    required this.tipHeight,
    required this.utxoMaxConfHeight,
    required this.keyLabels,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${path.threshold}-of-${path.mfps.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(AppAlpha.medium),
              ),
            ),
            const SizedBox(height: 8),
            ...path.mfps.map((mfp) {
              final label = keyLabels[mfp];
              final display = mfp.substring(0, 8).toUpperCase();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    MfpBadge(label: display, color: theme.colorScheme.outline),
                    if (label != null && label.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
