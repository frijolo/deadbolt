import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/mfp_badge.dart';

/// Per-MFP signing options sheet. Replaces the previous picker — the MFP
/// is already fixed by the row the user tapped, so this sheet only has
/// to ask which signing channel to use for that key.
enum TxPlanningSignChannel { hotKey, qr }

Future<TxPlanningSignChannel?> showTxPlanningSignMfpSheet(
  BuildContext context, {
  required String mfp,
  required String? label,
  required bool hasHotKey,
}) {
  return showSheet<TxPlanningSignChannel>(
    context,
    (ctx) => SafeArea(
      top: false,
      child: _SignMfpSheet(mfp: mfp, label: label, hasHotKey: hasHotKey),
    ),
  );
}

class _SignMfpSheet extends StatelessWidget {
  final String mfp;
  final String? label;
  final bool hasHotKey;

  const _SignMfpSheet({
    required this.mfp,
    required this.label,
    required this.hasHotKey,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          Text(
            l10n.txPlanningSignMfpTitle,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MfpBadge(
                label: mfp.substring(0, 8).toUpperCase(),
                color: theme.colorScheme.outline,
              ),
              if (label != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label!, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (hasHotKey)
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context)
                  .pop(TxPlanningSignChannel.hotKey),
              icon: const Icon(Icons.key_outlined),
              label: Text(l10n.txPlanningSignerHotKeyOption),
            ),
          if (hasHotKey) const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(TxPlanningSignChannel.qr),
            icon: const Icon(Icons.qr_code_2),
            label: Text(l10n.txPlanningSignerQr),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}
