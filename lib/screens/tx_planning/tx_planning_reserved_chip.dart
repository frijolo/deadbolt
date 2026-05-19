import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/tx_planning_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/screens/tx_planning/tx_planning_earmark.dart';
import 'package:deadbolt/screens/wallet_detail/shared_detail_widgets.dart'
    show StatusBadge;

/// Inline pill rendered on a coin row when the UTXO is reserved by an
/// active spaced TX plan. Reuses the project's [StatusBadge] visual so
/// it sits naturally alongside the existing "Pending spend" badges.
///
/// Returns [SizedBox.shrink] when the UTXO outpoint is not earmarked,
/// or when no [TxPlanningCubit] has been provided up the widget tree
/// (lets coin tiles stay agnostic — wiring slots opt in by mounting the
/// cubit at the wallet detail level).
class TxPlanningReservedBadge extends StatelessWidget {
  final String outpointKey;
  const TxPlanningReservedBadge({super.key, required this.outpointKey});

  @override
  Widget build(BuildContext context) {
    final earmarks = TxPlanningEarmarks.ofWatch(context);
    if (!earmarks.contains(outpointKey)) return const SizedBox.shrink();
    return StatusBadge(
      label: context.l10n.txPlanningReservedBadge,
      color: Theme.of(context).colorScheme.primary,
      icon: Icons.lock_clock,
    );
  }
}

/// "Reserved Nsats" chip for the wallet overview balance row. Renders
/// nothing when no active plan exists.
class TxPlanningReservedBalanceChip extends StatelessWidget {
  /// Formatter the surrounding overview tab uses for sat values — kept
  /// as a callback so we don't pull in any of the formatter's locale
  /// machinery.
  final String Function(int sats) formatSats;
  const TxPlanningReservedBalanceChip({super.key, required this.formatSats});

  @override
  Widget build(BuildContext context) {
    final earmarks = TxPlanningEarmarks.ofWatch(context);
    if (!earmarks.hasAny) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_clock, size: 12, color: cs.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            context.l10n.txPlanningReservedBalance(
              formatSats(earmarks.reservedSat.toInt()),
            ),
            style: TextStyle(
              fontSize: 11,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


