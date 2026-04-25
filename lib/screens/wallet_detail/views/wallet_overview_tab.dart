import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/utils/date_format.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';

enum BalanceUnit { sats, btc, fiat }

class OverviewView extends StatefulWidget {
  final WalletDetailLoaded state;
  final VoidCallback onSendTap;
  final VoidCallback onReceiveTap;
  final VoidCallback onSyncTap;
  final VoidCallback onRescanTap;
  final VoidCallback onExportLabelsTap;
  final VoidCallback onImportLabelsTap;
  final VoidCallback onHwTap;
  final VoidCallback onChangeProtectionTap;

  const OverviewView({
    super.key,
    required this.state,
    required this.onSendTap,
    required this.onReceiveTap,
    required this.onSyncTap,
    required this.onRescanTap,
    required this.onExportLabelsTap,
    required this.onImportLabelsTap,
    required this.onHwTap,
    required this.onChangeProtectionTap,
  });

  @override
  State<OverviewView> createState() => _OverviewViewState();
}

class _OverviewViewState extends State<OverviewView> {
  BalanceUnit _unit = BalanceUnit.sats;

  bool get _fiatAvailable =>
      widget.state.currentBtcPrice != null &&
      widget.state.fiatCurrency != null;

  List<BalanceUnit> get _availableUnits => [
        BalanceUnit.sats,
        BalanceUnit.btc,
        if (_fiatAvailable) BalanceUnit.fiat,
      ];

  void _cycleUnit() {
    final units = _availableUnits;
    final next = (units.indexOf(_unit) + 1) % units.length;
    setState(() => _unit = units[next]);
  }

  String _fmt(int sats) {
    final l10n = context.l10n;
    switch (_unit) {
      case BalanceUnit.sats:
        return l10n.balanceSats(sats);
      case BalanceUnit.btc:
        return l10n.balanceBtc(BitcoinFormatter.satsToBtcString(sats));
      case BalanceUnit.fiat:
        return BitcoinFormatter.formatSatsFiat(
          sats,
          widget.state.currentBtcPrice!,
          widget.state.fiatCurrency!,
        );
    }
  }

  List<APISpendPath> _inheritancePaths(WalletDetailLoaded state) {
    final minBlocks =
        context.watch<SettingsCubit>().state.inheritanceMinTimelockBlocks;
    return state.descriptorAnalysis?.spendPaths
            .where((p) =>
                p.relTimelock.timelockType == APIRelativeTimelockType.blocks &&
                p.relTimelock.value >= minBlocks)
            .toList() ??
        [];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final balance = state.balance;
    final walletInfo = state.walletInfo;
    final totalSats =
        balance.confirmed +
        balance.trustedPending +
        balance.untrustedPending +
        balance.immature;
    final lastSynced = walletInfo.lastSyncedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(walletInfo.lastSyncedAt! * 1000)
        : null;

    final heirPaths = _inheritancePaths(state);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Balance card ────────────────────────────────────────────────────
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _cycleUnit,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          _fmt(totalSats.toInt()),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.compare_arrows,
                        size: 18,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(AppAlpha.secondary),
                      ),
                    ],
                  ),
                  if (balance.trustedPending + balance.untrustedPending + balance.immature > BigInt.zero) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _BalanceChip(
                          label: l10n.balanceConfirmed,
                          value: _fmt(balance.confirmed.toInt()),
                        ),
                        if (balance.trustedPending + balance.untrustedPending >
                            BigInt.zero)
                          _BalanceChip(
                            label: l10n.balancePending,
                            value: _fmt((balance.trustedPending +
                                    balance.untrustedPending)
                                .toInt()),
                            dimmed: true,
                          ),
                        if (balance.immature > BigInt.zero)
                          _BalanceChip(
                            label: l10n.balanceImmature,
                            value: _fmt(balance.immature.toInt()),
                            dimmed: true,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    lastSynced != null
                        ? l10n.lastSynced(formatDateTime(lastSynced))
                        : l10n.notYetSynced,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(AppAlpha.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Primary actions (large cards) ───────────────────────────────────
        Row(
          children: [
            Expanded(child: _ActionButton(icon: Icons.arrow_upward, label: l10n.walletSendButton, filled: true, onTap: widget.onSendTap)),
            const SizedBox(width: 12),
            Expanded(child: _ActionButton(icon: Icons.arrow_downward, label: l10n.walletReceiveButton, filled: true, onTap: widget.onReceiveTap)),
          ],
        ),
        const SizedBox(height: 8),

        // ── Secondary actions (2-column outlined grid) ──────────────────────
        ..._buildSecondaryGrid([
          _ActionButton(icon: Icons.sync, label: l10n.syncButton, enabled: !state.isSyncing, onTap: widget.onSyncTap),
          _ActionButton(icon: Icons.manage_search, label: l10n.rescanButton, onTap: widget.onRescanTap),
          _ActionButton(icon: Icons.upload_outlined, label: l10n.exportBip329Button, onTap: widget.onExportLabelsTap),
          _ActionButton(icon: Icons.download_outlined, label: l10n.importBip329Button, onTap: widget.onImportLabelsTap),
          _ActionButton(icon: Icons.memory, label: l10n.hwWalletTitle, onTap: widget.onHwTap),
          _ActionButton(icon: Icons.security, label: l10n.walletSecurityLabel, onTap: widget.onChangeProtectionTap),
        ]),

        // ── Inheritance status card (below actions — advanced info) ─────────
        if (heirPaths.isNotEmpty) ...[
          const SizedBox(height: 20),
          _InheritanceStatusCard(state: state, heirPaths: heirPaths),
        ],
      ],
    );
  }

  static List<Widget> _buildSecondaryGrid(List<Widget> buttons) {
    final rows = <Widget>[];
    for (int i = 0; i < buttons.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(Row(
        children: [
          Expanded(child: buttons[i]),
          const SizedBox(width: 8),
          Expanded(child: i + 1 < buttons.length ? buttons[i + 1] : const SizedBox()),
        ],
      ));
    }
    return rows;
  }

}

// ---------------------------------------------------------------------------
// Inheritance status card
// ---------------------------------------------------------------------------

/// Returns the minimum blocks remaining until any heir can access funds,
/// based on the most vulnerable (oldest) confirmed UTXO.
/// Returns null if wallet is not synced or there are no confirmed UTXOs.
int? _earliestHeirAccessBlocks({
  required List<APISpendPath> heirPaths,
  required List<APIUtxo> utxos,
  required int tipHeight,
}) {
  if (tipHeight == 0) return null;
  final confirmedUtxos =
      utxos.where((u) => u.isConfirmed && u.confirmationHeight != null).toList();
  if (confirmedUtxos.isEmpty) return null;

  int? earliest;
  for (final path in heirPaths) {
    if (path.relTimelock.timelockType != APIRelativeTimelockType.blocks) continue;
    final required = path.relTimelock.value;
    for (final utxo in confirmedUtxos) {
      final elapsed = tipHeight - utxo.confirmationHeight!.toInt();
      final remaining = required - elapsed;
      final clamped = remaining < 0 ? 0 : remaining;
      if (earliest == null || clamped < earliest) {
        earliest = clamped;
      }
    }
  }
  return earliest;
}

class _InheritanceStatusCard extends StatelessWidget {
  final WalletDetailLoaded state;
  final List<APISpendPath> heirPaths;

  const _InheritanceStatusCard({
    required this.state,
    required this.heirPaths,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final tipHeight = state.tipHeight;
    final utxos = state.utxos;
    final hasConfirmedBalance = state.balance.confirmed > BigInt.zero;

    final earliestBlocks = _earliestHeirAccessBlocks(
      heirPaths: heirPaths,
      utxos: utxos,
      tipHeight: tipHeight,
    );

    // Determine status color and label
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;

    if (tipHeight == 0 || !state.utxosLoaded) {
      statusColor = scheme.onSurfaceVariant;
      statusLabel = l10n.inheritanceNeedsSync;
      statusIcon = Icons.sync_outlined;
    } else if (!hasConfirmedBalance || earliestBlocks == null) {
      statusColor = scheme.onSurfaceVariant;
      statusLabel = l10n.inheritanceNoFunds;
      statusIcon = Icons.lock_open_outlined;
    } else if (earliestBlocks == 0) {
      statusColor = Colors.red;
      statusLabel = l10n.inheritanceUnlocked;
      statusIcon = Icons.warning_amber_rounded;
    } else if (earliestBlocks < 1008) {
      statusColor = Colors.orange;
      statusLabel = l10n.inheritanceApproaching;
      statusIcon = Icons.timer_outlined;
    } else {
      statusColor = Colors.green;
      statusLabel = l10n.inheritanceSafe;
      statusIcon = Icons.lock_outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.family_restroom, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  l10n.inheritanceStatus,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Heir paths list
            for (final path in heirPaths) ...[
              _HeirPathRow(
                path: path,
                tipHeight: tipHeight,
                utxos: utxos,
                label: state.pathLabels[path.id],
                keyLabels: state.keyLabels,
              ),
              const SizedBox(height: 6),
            ],

            // Re-vault button — navigates to the coins tab so the user can
            // pick which coin(s) to re-vault individually.
            if (hasConfirmedBalance) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.read<WalletDetailCubit>().selectTab(WalletDetailCubit.tabCoins),
                  icon: const Icon(Icons.update, size: 16),
                  label: Text(l10n.revaultNow),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}

class _HeirPathRow extends StatelessWidget {
  final APISpendPath path;
  final int tipHeight;
  final List<APIUtxo> utxos;
  final String? label;
  final Map<String, String> keyLabels;

  const _HeirPathRow({
    required this.path,
    required this.tipHeight,
    required this.utxos,
    required this.keyLabels,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final staticLabel = BitcoinFormatter.formatRelativeTimelock(
      RelativeTimelockType.fromApi(path.relTimelock.timelockType),
      path.relTimelock.value,
    );

    // Worst-case (oldest/most vulnerable) UTXO determines displayed status.
    SpendPathStatus? worstStatus;
    for (final utxo in utxos.where((u) => u.isConfirmed)) {
      final s = spendPathStatus(path: path, utxo: utxo, tipHeight: tipHeight);
      if (worstStatus == null || _statusRank(s) < _statusRank(worstStatus)) {
        worstStatus = s;
      }
    }

    final isUnlocked = worstStatus is SpendPathUnlocked;
    final dotColor = isUnlocked ? Colors.red : scheme.onSurfaceVariant;
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    // Show remaining time when data is available; fall back to static timelock.
    // Unlocked → null (icon already communicates the state).
    final timeText = switch (worstStatus) {
      SpendPathRelLocked(:final remainingBlocks) when remainingBlocks != null =>
        BitcoinFormatter.formatDuration(remainingBlocks * 10),
      SpendPathUnlocked() => null,
      _ => staticLabel,
    };

    final hasCustomLabel = label != null && label!.isNotEmpty;
    final displayLabel = hasCustomLabel
        ? label!
        : BitcoinFormatter.pathLabel(
            path.threshold, path.mfps, (mfp) => keyLabels[mfp] ?? mfp.toUpperCase());

    return Row(
      children: [
        Icon(
          isUnlocked ? Icons.lock_open_outlined : Icons.lock_clock_outlined,
          size: 14,
          color: dotColor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  displayLabel,
                  style: bodySmall?.copyWith(
                    color: hasCustomLabel
                        ? scheme.onSurface.withAlpha(AppAlpha.high)
                        : scheme.onSurfaceVariant,
                    fontStyle: hasCustomLabel ? FontStyle.normal : FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timeText != null) ...[
                const SizedBox(width: 8),
                Text(
                  timeText,
                  style: bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Lower rank = closer to unlocked (worse for security).
  int _statusRank(SpendPathStatus s) => switch (s) {
        SpendPathUnlocked() => 0,
        SpendPathRelLocked() => 1,
        SpendPathUnconfirmed() => 2,
        SpendPathNeedsSync() => 3,
        SpendPathAbsLocked() => 4,
      };
}

// ---------------------------------------------------------------------------
// Shared action widgets
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = enabled ? scheme.onSurfaceVariant : scheme.onSurface.withAlpha(AppAlpha.muted);
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: Card(
      color: filled ? scheme.primaryContainer : Colors.transparent,
      elevation: filled ? null : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: filled
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: filled
              ? const EdgeInsets.symmetric(vertical: 20, horizontal: 8)
              : const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: filled
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 28, color: scheme.onPrimaryContainer),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: effectiveColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: effectiveColor),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
    );
  }
}


class _BalanceChip extends StatelessWidget {
  final String label;
  final String value;
  final bool dimmed;

  const _BalanceChip({
    required this.label,
    required this.value,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(dimmed ? 97 : 178),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(dimmed ? 97 : 210),
          ),
        ),
      ],
    );
  }
}

