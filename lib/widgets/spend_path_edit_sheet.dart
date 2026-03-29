import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/add_key_dialog.dart';
import 'package:deadbolt/widgets/dialog_helpers.dart' show SheetHandle, showSheet;
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/timelock_dialog.dart';

Color _colorForMfp(BuildContext context, ProjectDetailCubit cubit, String mfp) {
  final ext = Theme.of(context).extension<KeyColorExtension>()!;
  final idx = cubit.getMfpColorIndex(mfp);
  return ext.keyColors[idx % ext.keyColors.length];
}

/// Opens the spend path editor as a modal bottom sheet.
void showSpendPathEditSheet(
  BuildContext context, {
  required ProjectDetailCubit cubit,
  required int index,
  required bool isTaproot,
}) {
  showSheet<void>(context, (_) => BlocProvider.value(
    value: cubit,
    child: _SpendPathEditSheetContent(index: index, isTaproot: isTaproot),
  ));
}

class _SpendPathEditSheetContent extends StatelessWidget {
  final int index;
  final bool isTaproot;

  const _SpendPathEditSheetContent({
    required this.index,
    required this.isTaproot,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, state) {
          if (state is! ProjectDetailLoaded ||
              state.editedPaths == null ||
              index >= state.editedPaths!.length) {
            return const SizedBox.shrink();
          }

          final cubit = context.read<ProjectDetailCubit>();
          final path = state.editedPaths![index];
          final availableKeys = state.editedKeys!
              .map((k) => k.toProjectKey(state.project.id))
              .toList();

          // Look up computed stats from the last-saved DB path (may be null
          // for newly added paths that haven't been built yet).
          final dbPath = path.originalDbId != null
              ? state.spendPaths
                  .where((p) => p.id == path.originalDbId)
                  .firstOrNull
              : null;

          final validationError = _getValidationError(context, path);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Label ─────────────────────────────────────────
                      _buildLabelSection(context, cubit, path, availableKeys),
                      const SizedBox(height: 16),
                      const Divider(),
                      // ── Timelock · Priority · KeyPath ─────────────────
                      const SizedBox(height: 8),
                      _buildControlsRow(context, cubit, path),
                      if (validationError != null) ...[
                        const SizedBox(height: 12),
                        _buildValidationError(validationError),
                      ],
                      // ── Keys ──────────────────────────────────────────
                      const SizedBox(height: 16),
                      _buildKeysSection(context, cubit, path, availableKeys),
                      // ── Threshold ─────────────────────────────────────
                      const SizedBox(height: 16),
                      _buildThresholdRow(context, cubit, path),
                      // ── Stats (vbSweep, trDepth) from DB ──────────────
                      // Hidden when dirty: values reflect the last build, not current edits.
                      if (dbPath != null && !state.isDirty) ...[
                        const SizedBox(height: 16),
                        _buildStatsRow(context, dbPath),
                      ],
                      // ── Delete ────────────────────────────────────────
                      const SizedBox(height: 24),
                      _buildDeleteButton(context, cubit),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Validation ────────────────────────────────────────────────────────────

  String? _getValidationError(BuildContext context, EditableSpendPath path) {
    final l = context.l10n;
    if (path.mfps.isEmpty) return l.mustHaveAtLeastOneKey;
    if (path.threshold < 1) return l.thresholdMustBeAtLeastOne;
    if (path.threshold > path.mfps.length) return l.thresholdCannotExceed;
    return null;
  }

  Widget _buildValidationError(String error) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(AppAlpha.subtle),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.withAlpha(AppAlpha.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error,
                style: const TextStyle(fontSize: 12, color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Controls row: timelock + priority + key-path ──────────────────────────

  Widget _buildControlsRow(
      BuildContext context, ProjectDetailCubit cubit, EditableSpendPath path) {
    final isScriptPath = isTaproot && !path.isKeyPath;
    final showKeyPath = isTaproot && path.canBeKeyPath;

    return Row(
      children: [
        _buildTimelockButton(context, cubit, path),
        const Spacer(),
        if (isScriptPath) ...[
          _buildPriorityBadge(context, cubit, path),
          const SizedBox(width: 8),
        ],
        if (showKeyPath) _buildKeyPathToggle(context, cubit, path),
      ],
    );
  }

  Widget _buildTimelockButton(
      BuildContext context, ProjectDetailCubit cubit, EditableSpendPath path) {
    final l10n = context.l10n;
    final hasTimelock = path.timelockMode != TimelockMode.none &&
        ((path.timelockMode == TimelockMode.relative &&
                path.relTimelockValue > 0) ||
            (path.timelockMode == TimelockMode.absolute &&
                path.absTimelockValue > 0));

    final IconData icon;
    final String text;
    if (!hasTimelock) {
      icon = Icons.lock_clock;
      text = l10n.noTimelock;
    } else if (path.timelockMode == TimelockMode.relative) {
      icon = Icons.update;
      text = BitcoinFormatter.formatRelativeTimelock(
          path.relTimelockType, path.relTimelockValue);
    } else {
      icon = Icons.event_available;
      text = BitcoinFormatter.formatAbsoluteTimelock(
          path.absTimelockType, path.absTimelockValue);
    }

    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showTimelockDialog(context, cubit, path),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasTimelock
              ? AppAccent.color.withAlpha(AppAlpha.subtle)
              : cs.onSurface.withAlpha(AppAlpha.subtle),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasTimelock
                ? AppAccent.color.withAlpha(AppAlpha.mediumLow)
                : cs.onSurface.withAlpha(AppAlpha.disabled),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: hasTimelock
                    ? AppAccent.color
                    : cs.onSurface.withAlpha(AppAlpha.secondary)),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                    fontSize: 11,
                    color: hasTimelock
                        ? cs.onSurface
                        : cs.onSurface.withAlpha(AppAlpha.secondary))),
            const SizedBox(width: 4),
            Icon(Icons.edit,
                size: 12,
                color: hasTimelock
                    ? AppAccent.color.withAlpha(AppAlpha.deleteAction)
                    : cs.onSurface.withAlpha(AppAlpha.muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(
      BuildContext context, ProjectDetailCubit cubit, EditableSpendPath path) {
    final l10n = context.l10n;
    final p = path.priority;
    final maxOption = (p + 1).clamp(0, 9);
    final active = p > 0;

    return PopupMenuButton<int>(
      offset: const Offset(0, 32),
      onSelected: (value) => cubit.updatePathPriority(index, value),
      tooltip: l10n.changePriorityTooltip,
      itemBuilder: (_) => List.generate(
          maxOption + 1, (i) => PopupMenuItem(value: i, child: Text('$i'))),
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? AppAccent.color.withAlpha(AppAlpha.subtle)
                : cs.onSurface.withAlpha(AppAlpha.subtle),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? AppAccent.color.withAlpha(AppAlpha.mediumLow)
                  : cs.onSurface.withAlpha(AppAlpha.disabled),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.priorityBadge(p),
                  style: TextStyle(
                      fontSize: 12,
                      color: active
                          ? cs.onSurface.withAlpha(AppAlpha.mediumHigh)
                          : cs.onSurface.withAlpha(AppAlpha.muted))),
              const SizedBox(width: 4),
              Icon(Icons.edit,
                  size: 12,
                  color: active ? AppAccent.color : cs.onSurface.withAlpha(AppAlpha.muted)),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildKeyPathToggle(
      BuildContext context, ProjectDetailCubit cubit, EditableSpendPath path) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => cubit.updatePathIsKeyPath(index, !path.isKeyPath),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color:
              path.isKeyPath ? Colors.blue.withAlpha(AppAlpha.subtle) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: path.isKeyPath
                ? Colors.blue.withAlpha(AppAlpha.border)
                : cs.onSurface.withAlpha(AppAlpha.disabled),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key,
                size: 12,
                color:
                    path.isKeyPath ? Colors.blue : cs.onSurface.withAlpha(AppAlpha.muted)),
            const SizedBox(width: 3),
            Text(
              path.isKeyPath ? l10n.keyPathBadge : l10n.setAsKeyPath,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color:
                    path.isKeyPath ? Colors.blue : cs.onSurface.withAlpha(AppAlpha.muted),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Keys section ──────────────────────────────────────────────────────────

  Widget _buildKeysSection(BuildContext context, ProjectDetailCubit cubit,
      EditableSpendPath path, List<ProjectKey> availableKeys) {
    final l10n = context.l10n;
    final unusedKeys =
        availableKeys.where((k) => !path.mfps.contains(k.mfp)).toList();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.keysLabel,
            style:
                TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary))),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mfp in path.mfps)
              _buildRemovableMfpBadge(context, cubit, mfp, availableKeys),
            _buildAddKeyButton(context, cubit, unusedKeys),
          ],
        ),
      ],
    );
  }

  Widget _buildRemovableMfpBadge(BuildContext context, ProjectDetailCubit cubit,
      String mfp, List<ProjectKey> availableKeys) {
    final key = availableKeys.where((k) => k.mfp == mfp).firstOrNull;
    final label = key?.customName ?? mfp.toUpperCase();
    final color = _colorForMfp(context, cubit, mfp);
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2, right: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(AppAlpha.subtle),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(AppAlpha.mediumLow), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                color: cs.onSurface.withAlpha(AppAlpha.high),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
              )),
          const SizedBox(width: 2),
          InkWell(
            onTap: () => cubit.removeMfpFromPath(index, mfp),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child:
                  Icon(Icons.close, size: 14, color: color.withAlpha(AppAlpha.deleteAction)),
            ),
          ),
        ],
      ),
    );
  }

  static const _newKeySentinel = '__new_key__';

  Widget _buildAddKeyButton(BuildContext context, ProjectDetailCubit cubit,
      List<ProjectKey> unusedKeys) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      offset: const Offset(0, 32),
      onSelected: (value) {
        if (value == _newKeySentinel) {
          showAddKeyDialog(context, cubit,
              onKeyAdded: (mfp) => cubit.addMfpToPath(index, mfp));
        } else {
          cubit.addMfpToPath(index, value);
        }
      },
      itemBuilder: (context) => [
        ...unusedKeys.map((k) => PopupMenuItem<String>(
              value: k.mfp,
              child: Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _colorForMfp(context, cubit, k.mfp),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(k.mfp.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                if (k.customName != null) ...[
                  const SizedBox(width: 8),
                  Text(k.customName!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(AppAlpha.secondary))),
                ],
              ]),
            )),
        if (unusedKeys.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: _newKeySentinel,
          child: Row(children: [
            const Icon(Icons.add, size: 16, color: AppAccent.color),
            const SizedBox(width: 8),
            Text(l10n.newKey,
                style: const TextStyle(color: AppAccent.color)),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppAccent.color.withAlpha(AppAlpha.border)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 14, color: AppAccent.color),
            const SizedBox(width: 4),
            Text(l10n.addKeyButton,
                style:
                    const TextStyle(fontSize: 12, color: AppAccent.color)),
          ],
        ),
      ),
    );
  }

  // ── Threshold ─────────────────────────────────────────────────────────────

  Widget _buildThresholdRow(
      BuildContext context, ProjectDetailCubit cubit, EditableSpendPath path) {
    final l10n = context.l10n;
    final maxThreshold = path.mfps.isEmpty ? 1 : path.mfps.length;
    final currentThreshold = path.threshold.clamp(1, maxThreshold);
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(l10n.thresholdLabel,
            style:
                TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary))),
        const SizedBox(width: 12),
        PopupMenuButton<int>(
          offset: const Offset(0, 32),
          onSelected: (value) => cubit.updatePathThreshold(index, value),
          tooltip: l10n.changeThresholdTooltip,
          itemBuilder: (_) => List.generate(maxThreshold,
              (i) => PopupMenuItem(value: i + 1, child: Text('${i + 1}'))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppAccent.color.withAlpha(AppAlpha.subtle),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppAccent.color.withAlpha(AppAlpha.mediumLow)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$currentThreshold',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withAlpha(AppAlpha.mediumHigh))),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 12, color: AppAccent.color),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(l10n.ofCount(path.mfps.length),
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withAlpha(AppAlpha.mediumHigh))),
      ],
    );
  }

  // ── Stats (from last saved DB path) ──────────────────────────────────────

  Widget _buildStatsRow(BuildContext context, ProjectSpendPath dbPath) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final labelStyle =
        TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary));
    final valueStyle = TextStyle(
        fontSize: 13,
        color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
        fontWeight: FontWeight.w600);

    return Row(
      children: [
        // Sweep cost
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sweepCostLabel, style: labelStyle),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.payments_outlined,
                  size: 13, color: AppAccent.color),
              const SizedBox(width: 4),
              Text(
                '${BitcoinFormatter.formatDouble(dbPath.vbSweep, 2)} vB',
                style: valueStyle,
              ),
            ]),
          ],
        ),
        // TR depth (Taproot script paths only)
        if (dbPath.trDepth >= 0) ...[
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.trDepthLabel, style: labelStyle),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.account_tree_outlined,
                    size: 13, color: AppAccent.color),
                const SizedBox(width: 4),
                Text('${dbPath.trDepth}', style: valueStyle),
              ]),
            ],
          ),
        ],
      ],
    );
  }

  // ── Label section ─────────────────────────────────────────────────────────

  Widget _buildLabelSection(BuildContext context, ProjectDetailCubit cubit,
      EditableSpendPath path, List<ProjectKey> availableKeys) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final hasCustomName = path.customName != null;
    final displayName = hasCustomName ? path.customName! : _autoPathLabel(path, availableKeys);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.spendPathNameDialogTitle,
          style:
              TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(AppAlpha.secondary)),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showNameDialog(context, cubit, path),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: hasCustomName ? FontWeight.w600 : FontWeight.normal,
                    color: hasCustomName
                        ? cs.onSurface
                        : cs.onSurface.withAlpha(AppAlpha.muted),
                    fontStyle: hasCustomName ? FontStyle.normal : FontStyle.italic,
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

  String _autoPathLabel(EditableSpendPath path, List<ProjectKey> availableKeys) {
    String keyLabel(String mfp) {
      final key = availableKeys.where((k) => k.mfp == mfp).firstOrNull;
      return key?.customName ?? mfp.toUpperCase();
    }
    return BitcoinFormatter.pathLabel(path.threshold, path.mfps, keyLabel);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Widget _buildDeleteButton(BuildContext context, ProjectDetailCubit cubit) {
    final l10n = context.l10n;
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.pop(context);
        cubit.removeSpendPath(index);
      },
      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
      label: Text(l10n.removePathTooltip,
          style: const TextStyle(color: Colors.red)),
      style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.red.withAlpha(AppAlpha.border))),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showNameDialog(BuildContext context, ProjectDetailCubit cubit,
      EditableSpendPath path) {
    showEditNameDialog(
      context,
      title: context.l10n.spendPathNameDialogTitle,
      currentName: path.customName,
      onSave: (name) => cubit.updatePathCustomName(index, name),
    );
  }

  void _showTimelockDialog(BuildContext context, ProjectDetailCubit cubit,
      EditableSpendPath path) {
    showDialog(
      context: context,
      builder: (_) => TimelockDialog(
        initialMode: path.timelockMode,
        initialRelType: path.relTimelockType,
        initialRelValue: path.relTimelockValue,
        initialAbsType: path.absTimelockType,
        initialAbsValue: path.absTimelockValue,
        onSave: (mode, relType, relValue, absType, absValue) {
          if (relValue == 0 && absValue == 0) {
            mode = TimelockMode.none;
          }
          if (mode != path.timelockMode) {
            cubit.updatePathTimelockMode(index, mode);
          }
          if (relType != path.relTimelockType) {
            cubit.updatePathRelTimelockType(index, relType);
          }
          if (relValue != path.relTimelockValue) {
            cubit.updatePathRelTimelockValue(index, relValue);
          }
          if (absType != path.absTimelockType) {
            cubit.updatePathAbsTimelockType(index, absType);
          }
          if (absValue != path.absTimelockValue) {
            cubit.updatePathAbsTimelockValue(index, absValue);
          }
        },
      ),
    );
  }
}
