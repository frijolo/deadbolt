import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart'
    show APISpacedPlanSigningBundle;
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_signing_cursor.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/mfp_badge.dart';

/// Lists the plan's threshold MFPs with a "signed / total" counter so
/// the user picks which key they are about to sign with (QR flow).
/// Rows whose pending count is zero are disabled. Returns the chosen
/// `mfp` or `null` on dismiss.
///
/// Pulls signer membership from `bundle.children[0].signers` — every
/// child in a single plan shares the same threshold set, so the first
/// row is authoritative.
Future<String?> showTxPlanningMfpPickerSheet(
  BuildContext context, {
  required APISpacedPlanSigningBundle bundle,
  required Map<String, String> keyLabels,
}) {
  final mfps = bundle.children.isEmpty
      ? const <String>[]
      : bundle.children.first.signers.map((s) => s.mfp).toList();
  return showSheet<String>(
    context,
    (ctx) => SafeArea(
      top: false,
      child: _MfpPickerSheet(
        bundle: bundle,
        mfps: mfps,
        keyLabels: keyLabels,
      ),
    ),
  );
}

class _MfpPickerSheet extends StatelessWidget {
  final APISpacedPlanSigningBundle bundle;
  final List<String> mfps;
  final Map<String, String> keyLabels;

  const _MfpPickerSheet({
    required this.bundle,
    required this.mfps,
    required this.keyLabels,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = bundle.children.length;
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
            l10n.txPlanningMfpPickerTitle,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.txPlanningMfpPickerSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          for (final mfp in mfps)
            _MfpPickerRow(
              mfp: mfp,
              label: keyLabels[mfp],
              signedCount: bundle.signedCountForMfp(mfp),
              totalCount: total,
              onTap: () => Navigator.of(context).pop(mfp),
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

class _MfpPickerRow extends StatelessWidget {
  final String mfp;
  final String? label;
  final int signedCount;
  final int totalCount;
  final VoidCallback onTap;

  const _MfpPickerRow({
    required this.mfp,
    required this.label,
    required this.signedCount,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pending = totalCount - signedCount;
    final done = pending <= 0;

    final Color color;
    final IconData icon;
    final String trailing;
    if (done) {
      color = Colors.green;
      icon = Icons.check_circle;
      trailing = l10n.psbtSignerSigned;
    } else if (signedCount > 0) {
      color = Colors.orange;
      icon = Icons.adjust;
      trailing = l10n.txPlanningMfpPickerPending(pending, totalCount);
    } else {
      color = theme.colorScheme.outline;
      icon = Icons.radio_button_unchecked;
      trailing = l10n.txPlanningMfpPickerPending(pending, totalCount);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: done ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              MfpBadge(
                label: mfp.substring(0, 8).toUpperCase(),
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: done
                        ? theme.colorScheme.onSurface
                            .withAlpha(AppAlpha.medium)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
