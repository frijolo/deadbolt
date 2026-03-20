import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/path_card.dart' show PathTimelockBadge, PathKeyPathBadge;

void showWalletPathSheet(
  BuildContext context, {
  required APISpendPath path,
  required String? initialLabel,
  required bool isTaproot,
  required Color Function(String mfp) mfpColorProvider,
  required String Function(String mfp) keyLabelProvider,
  required void Function(String? name) onLabelSave,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WalletPathSheetContent(
      path: path,
      initialLabel: initialLabel,
      isTaproot: isTaproot,
      mfpColorProvider: mfpColorProvider,
      keyLabelProvider: keyLabelProvider,
      onLabelSave: onLabelSave,
    ),
  );
}

class _WalletPathSheetContent extends StatefulWidget {
  final APISpendPath path;
  final String? initialLabel;
  final bool isTaproot;
  final Color Function(String mfp) mfpColorProvider;
  final String Function(String mfp) keyLabelProvider;
  final void Function(String? name) onLabelSave;

  const _WalletPathSheetContent({
    required this.path,
    required this.initialLabel,
    required this.isTaproot,
    required this.mfpColorProvider,
    required this.keyLabelProvider,
    required this.onLabelSave,
  });

  @override
  State<_WalletPathSheetContent> createState() =>
      _WalletPathSheetContentState();
}

class _WalletPathSheetContentState extends State<_WalletPathSheetContent> {
  late String? _currentLabel;

  @override
  void initState() {
    super.initState();
    _currentLabel = widget.initialLabel;
  }

  APISpendPath get path => widget.path;

  String _autoLabel() =>
      BitcoinFormatter.pathLabel(path.threshold, path.mfps, widget.keyLabelProvider);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final hasRelTimelock = path.relTimelock.value > 0;
    final hasAbsTimelock = path.absTimelock.value > 0;
    final hasTimelock = hasRelTimelock || hasAbsTimelock;
    final isKeyPath = path.trDepth == -1;

    final relType =
        path.relTimelock.timelockType == APIRelativeTimelockType.blocks
            ? RelativeTimelockType.blocks
            : RelativeTimelockType.time;
    final absType =
        path.absTimelock.timelockType == APIAbsoluteTimelockType.blocks
            ? AbsoluteTimelockType.blocks
            : AbsoluteTimelockType.timestamp;
    final timelockFormatted = hasRelTimelock
        ? BitcoinFormatter.formatRelativeTimelock(
            relType, path.relTimelock.value)
        : BitcoinFormatter.formatAbsoluteTimelock(
            absType, path.absTimelock.value);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => SafeArea(
        top: false,
        child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withAlpha(AppAlpha.dim),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // ── Label ──────────────────────────────────────────────
                  _buildLabelSection(context, cs, l10n),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  // ── Keys ───────────────────────────────────────────────
                  _PathInfoRow(
                    label: l10n.keysLabel,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final mfp in path.mfps)
                          MfpBadge(
                            label: widget.keyLabelProvider(mfp),
                            color: widget.mfpColorProvider(mfp),
                            letterSpacing:
                                widget.keyLabelProvider(mfp) ==
                                        mfp.toUpperCase()
                                    ? 0.5
                                    : 0.0,
                          ),
                      ],
                    ),
                  ),
                  // ── Threshold (multisig only) ───────────────────────────
                  if (path.mfps.length > 1)
                    _PathInfoRow(
                      label: l10n.thresholdLabel,
                      child: Text('${path.threshold} / ${path.mfps.length}'),
                    ),
                  // ── Timelock ───────────────────────────────────────────
                  if (hasTimelock)
                    _PathInfoRow(
                      label: l10n.timelockDialogTitle,
                      child: PathTimelockBadge(
                        isRelative: hasRelTimelock,
                        label: timelockFormatted,
                      ),
                    ),
                  // ── Key path badge ─────────────────────────────────────
                  if (widget.isTaproot && isKeyPath)
                    _PathInfoRow(
                      label: '',
                      child: const PathKeyPathBadge(),
                    ),
                  // ── Stats ──────────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _PathInfoRow(
                          label: l10n.sweepCostLabel,
                          child: Row(
                            children: [
                              const Icon(Icons.payments_outlined,
                                  size: 13, color: AppAccent.color),
                              const SizedBox(width: 4),
                              Text(
                                '${BitcoinFormatter.formatDouble(path.vbSweep, 2)} vB',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (path.trDepth >= 0)
                        Expanded(
                          child: _PathInfoRow(
                            label: l10n.trDepthLabel,
                            child: Row(
                              children: [
                                const Icon(Icons.account_tree_outlined,
                                    size: 13, color: AppAccent.color),
                                const SizedBox(width: 4),
                                Text('${path.trDepth}'),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildLabelSection(
      BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    final hasLabel = _currentLabel != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.spendPathNameDialogTitle,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withAlpha(AppAlpha.secondary),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showLabelDialog(context),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _currentLabel ?? _autoLabel(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: hasLabel ? FontWeight.w600 : FontWeight.normal,
                    color: hasLabel ? cs.onSurface : cs.onSurface.withAlpha(AppAlpha.muted),
                    fontStyle: hasLabel ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
              Icon(Icons.edit, size: 14, color: cs.onSurface.withAlpha(AppAlpha.inactive)),
            ],
          ),
        ),
      ],
    );
  }

  void _showLabelDialog(BuildContext context) {
    showEditNameDialog(
      context,
      title: context.l10n.spendPathNameDialogTitle,
      currentName: _currentLabel,
      onSave: (name) {
        setState(() => _currentLabel = name);
        widget.onLabelSave(name);
      },
    );
  }
}

class _PathInfoRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _PathInfoRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color:
                    Theme.of(context).colorScheme.onSurface.withAlpha(AppAlpha.secondary),
              ),
            ),
          if (label.isNotEmpty) const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}
