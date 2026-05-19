import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';

/// Terminal summary: DONE / CANCELLED / FAILED. Offers "New plan" which
/// triggers a refresh, sending the cubit back to Idle (the underlying
/// plan row stays in the listing for history).
class TxPlanningTerminalView extends StatelessWidget {
  final APISpacedPlanDetail detail;
  const TxPlanningTerminalView({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final (icon, color, headline) = switch (parseTxPlanningStatus(detail.status)) {
      TxPlanningStatus.done =>
        (Icons.check_circle, cs.primary, l10n.txPlanningTerminalDone),
      TxPlanningStatus.cancelled =>
        (Icons.cancel, cs.outline, l10n.txPlanningTerminalCancelled),
      TxPlanningStatus.failed =>
        (Icons.error, cs.error, l10n.txPlanningTerminalFailed),
      _ => (
          Icons.info_outline,
          cs.secondary,
          l10n.txPlanningTerminalGeneric(detail.status),
        ),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 64, color: color),
          const SizedBox(height: 16),
          Center(
            child: Text(
              headline,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.txPlanningPlanHeader(
                detail.planId.toInt(),
                formatPlanKindLabel(context, detail, l10n),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => context.read<TxPlanningCubit>().refresh(),
            icon: const Icon(Icons.add),
            label: Text(l10n.txPlanningNewPlanButton),
          ),
        ],
      ),
    );
  }
}
