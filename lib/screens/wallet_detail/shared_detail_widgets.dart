import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/spend_path_unlock.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart';

// ─────────────────────────────────────────────────────────────
// Dialog helper — preserves the WalletDetailCubit across dialog pushes
// ─────────────────────────────────────────────────────────────

/// Show a dialog that inherits the current [WalletDetailCubit] from [context].
///
/// Set [barrierDismissible] to false for form dialogs (e.g. [LabelDialog])
/// to prevent accidental data loss when tapping the barrier.
void showWalletDialog(
  BuildContext context,
  Widget child, {
  bool barrierDismissible = true,
}) {
  final cubit = context.read<WalletDetailCubit>();
  showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => BlocProvider.value(value: cubit, child: child),
  );
}

// ─────────────────────────────────────────────────────────────
// Public shared utility widgets
// ─────────────────────────────────────────────────────────────

/// Small colored status badge (confirmation state, keychain type, etc.)
///
/// When [onTap] is provided the entire badge is tappable. Optionally show a
/// leading [icon] inside the pill and a [tooltip] on hover / long-press.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget badge = Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
    if (onTap == null) return badge;
    final tappable = GestureDetector(onTap: onTap, child: badge);
    return tooltip != null
        ? Tooltip(message: tooltip, child: tappable)
        : tappable;
  }
}

/// Summary badge shown on the coin tile: unlocked/total spend paths.
class SpendPathSummaryBadge extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;

  const SpendPathSummaryBadge({
    super.key,
    required this.unlockedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final allUnlocked = unlockedCount == totalCount;
    final color = allUnlocked ? Colors.green : AppAccent.color;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(AppAlpha.pale)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allUnlocked ? Icons.lock_open : Icons.lock_outline,
            size: 9,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '$unlockedCount/$totalCount',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Private shared layout widgets
// ─────────────────────────────────────────────────────────────

class SpendPathStatusRow extends StatelessWidget {
  final APISpendPath path;
  final SpendPathStatus status;
  final Map<String, String> keyLabels;

  const SpendPathStatusRow({
    super.key,
    required this.path,
    required this.status,
    required this.keyLabels,
  });

  String _pathName() {
    if (path.mfps.isEmpty) return '…';
    final labels =
        path.mfps.map((m) => keyLabels[m] ?? m.toUpperCase()).toList();
    final prefix = path.threshold < path.mfps.length
        ? '${path.threshold}/${path.mfps.length} '
        : '';
    return '$prefix${labels.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final (icon, color, subtitle) = switch (status) {
      SpendPathUnlocked() => (
        Icons.lock_open,
        Colors.green,
        l10n.spendPathUnlocked,
      ),
      SpendPathUnconfirmed() => (
        Icons.hourglass_empty,
        Colors.amber,
        l10n.spendPathUnconfirmed,
      ),
      SpendPathNeedsSync() => (
        Icons.sync_disabled,
        Colors.grey,
        l10n.spendPathNeedsSync,
      ),
      SpendPathAbsLocked(:final remainingBlocks, :final remainingSeconds) => (
        Icons.lock_outline,
        Colors.red,
        remainingBlocks != null
            ? l10n.spendPathLockedBlocks(remainingBlocks)
            : remainingSeconds != null
            ? _formatRemainingTime(remainingSeconds)
            : l10n.spendPathLocked,
      ),
      SpendPathRelLocked(:final remainingBlocks, :final remainingSeconds) => (
        Icons.lock_clock,
        Colors.orange,
        remainingBlocks != null
            ? l10n.spendPathLockedBlocks(remainingBlocks)
            : remainingSeconds != null
            ? _formatRemainingTime(remainingSeconds)
            : l10n.spendPathLocked,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pathName(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                Text(subtitle, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRemainingTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}min';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    return '${seconds ~/ 86400}d';
  }
}

class DetailRow extends StatelessWidget {
  final String label;
  final Widget child;

  const DetailRow({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withAlpha(AppAlpha.secondary),
            ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

// Two DetailRow widgets placed side by side (equal width columns)
class DetailRowPair extends StatelessWidget {
  final String label1;
  final Widget child1;
  final String label2;
  final Widget child2;

  const DetailRowPair({super.key,
    required this.label1,
    required this.child1,
    required this.label2,
    required this.child2,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: DetailRow(label: label1, child: child1)),
        const SizedBox(width: 8),
        Expanded(child: DetailRow(label: label2, child: child2)),
      ],
    );
  }
}

/// Shows an effective label with inherited styling (italic + outline) when [isAuto].
class EffectiveLabelText extends StatelessWidget {
  final String? effectiveLabel;
  final bool isAuto;
  const EffectiveLabelText(
      {super.key, required this.effectiveLabel, required this.isAuto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasLabel = effectiveLabel?.isNotEmpty == true;
    if (!hasLabel) {
      return Text(
        '—',
        style: TextStyle(
          color: scheme.onSurface.withAlpha(AppAlpha.muted),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (isAuto) {
      return Row(
        children: [
          Icon(Icons.label_outline, size: 14, color: scheme.outline),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              effectiveLabel!,
              style: TextStyle(
                  fontStyle: FontStyle.italic, color: scheme.outline),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.label, size: 14),
        const SizedBox(width: 4),
        Expanded(child: Text(effectiveLabel!)),
      ],
    );
  }
}

/// Rebuilds [EffectiveLabelText] whenever [WalletDetailLoaded] state changes.
class LiveEffectiveLabelText extends StatelessWidget {
  const LiveEffectiveLabelText({
    super.key,
    required this.resolve,
    required this.fallbackLabel,
    required this.fallbackIsAuto,
  });

  final (String?, bool) Function(WalletDetailLoaded) resolve;
  final String? fallbackLabel;
  final bool fallbackIsAuto;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WalletDetailCubit, WalletDetailState>(
      buildWhen: (_, next) => next is WalletDetailLoaded,
      builder: (context, state) {
        final (label, isAuto) = state is WalletDetailLoaded
            ? resolve(state)
            : (fallbackLabel, fallbackIsAuto);
        return EffectiveLabelText(effectiveLabel: label, isAuto: isAuto);
      },
    );
  }
}

/// Generic label-edit dialog used by address, coin, and tx label editors.
class LabelDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String currentLabel;
  final String removeLabel;
  final ValueChanged<String> onSave;
  final VoidCallback? onRemove;

  const LabelDialog({
    super.key,
    required this.title,
    required this.hintText,
    required this.currentLabel,
    required this.removeLabel,
    required this.onSave,
    this.onRemove,
  });

  @override
  State<LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<LabelDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController.fromValue(TextEditingValue(
      text: widget.currentLabel,
      selection:
          TextSelection.collapsed(offset: widget.currentLabel.length),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    widget.onSave(_controller.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      titlePadding: kDialogTitlePadding,
      title: dialogCloseTitle(widget.title,
          onClose: () => Navigator.of(context).pop(), tooltip: l10n.cancel),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(context),
        onTapOutside: (_) {
          final label = _controller.text.trim();
          if (label != widget.currentLabel) widget.onSave(label);
        },
      ),
      actions: [
        if (widget.currentLabel.isNotEmpty)
          TextButton(
            onPressed: () {
              widget.onRemove?.call();
              Navigator.of(context).pop();
            },
            child: Text(
              widget.removeLabel,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        FilledButton(
            onPressed: () => _save(context), child: Text(l10n.save)),
      ],
    );
  }
}
