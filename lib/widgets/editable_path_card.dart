import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/path_card.dart'
    show PathTimelockBadge, PathKeyPathBadge;
import 'package:deadbolt/widgets/spend_path_edit_sheet.dart';

class EditablePathCard extends StatelessWidget {
  final int index;
  final EditableSpendPath path;
  final List<ProjectKey> availableKeys;
  final Color Function(String) mfpColorProvider;
  final bool isTaproot;
  final ProjectDetailCubit cubit;

  const EditablePathCard({
    super.key,
    required this.index,
    required this.path,
    required this.availableKeys,
    required this.mfpColorProvider,
    required this.isTaproot,
    required this.cubit,
  });

  bool get _hasValidationError =>
      path.mfps.isEmpty ||
      path.threshold < 1 ||
      path.threshold > path.mfps.length;

  bool get _hasTimelock =>
      path.timelockMode != TimelockMode.none &&
      ((path.timelockMode == TimelockMode.relative && path.relTimelockValue > 0) ||
          (path.timelockMode == TimelockMode.absolute && path.absTimelockValue > 0));

  String _getKeyLabel(String mfp) {
    final key = availableKeys.where((k) => k.mfp == mfp).firstOrNull;
    return key?.customName ?? mfp.toUpperCase();
  }

  String _autoPathLabel() =>
      BitcoinFormatter.pathLabel(path.threshold, path.mfps, _getKeyLabel);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _hasValidationError ? Colors.red.withAlpha(20) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildLeading(context),
        title: _buildTitle(context, cs),
        subtitle: _buildSubtitle(context),
        trailing: Icon(
          Icons.edit_outlined,
          size: 18,
          color: cs.onSurface.withAlpha(AppAlpha.muted),
        ),
        onTap: () => showSpendPathEditSheet(
          context,
          cubit: cubit,
          index: index,
          isTaproot: isTaproot,
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _hasValidationError
                ? Colors.red.withAlpha(AppAlpha.subtle)
                : AppAccent.color.withAlpha(AppAlpha.subtle),
            child: Icon(
              path.mfps.length == 1 ? Icons.key : Icons.diversity_3,
              color: _hasValidationError ? Colors.red : AppAccent.color,
              size: 20,
            ),
          ),
          if (path.mfps.length > 1)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppAccent.color.withAlpha(AppAlpha.mediumLow),
                  border: Border.all(color: AppAccent.color, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${path.threshold}/${path.mfps.length}',
                  style: TextStyle(
                    color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTitle(BuildContext context, ColorScheme cs) {
    final hasCustomName = path.customName != null;
    final displayName = hasCustomName ? path.customName! : _autoPathLabel();
    return Row(
      children: [
        Expanded(
          child: Text(
            displayName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: hasCustomName ? FontWeight.w600 : FontWeight.normal,
              color: hasCustomName
                  ? cs.onSurface
                  : cs.onSurface.withAlpha(AppAlpha.muted),
              fontStyle: hasCustomName ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ),
        if (_hasTimelock)
          PathTimelockBadge(
            isRelative: path.timelockMode == TimelockMode.relative,
            label: path.timelockMode == TimelockMode.relative
                ? BitcoinFormatter.formatRelativeTimelock(
                    path.relTimelockType, path.relTimelockValue)
                : BitcoinFormatter.formatAbsoluteTimelock(
                    path.absTimelockType, path.absTimelockValue),
          ),
        if (isTaproot && path.isKeyPath) const PathKeyPathBadge(),
      ],
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    if (path.mfps.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    // Look up last-saved DB path for computed stats.
    // Hidden when dirty: values reflect the last build, not current edits.
    final state = cubit.state;
    final ProjectSpendPath? dbPath =
        (state is ProjectDetailLoaded &&
                !state.isDirty &&
                path.originalDbId != null)
            ? state.spendPaths
                .where((p) => p.id == path.originalDbId)
                .firstOrNull
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...path.mfps.map((mfp) {
              final label = _getKeyLabel(mfp);
              return MfpBadge(
                label: label,
                color: mfpColorProvider(mfp),
                letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
              );
            }),
          ],
        ),
        if (dbPath != null) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.payments_outlined,
                    size: 13, color: AppAccent.color),
                const SizedBox(width: 4),
                Text(
                  '${BitcoinFormatter.formatDouble(dbPath.vbSweep, 2)} vB',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (dbPath.trDepth >= 0) ...[
                  _buildSeparator(context),
                  const Icon(Icons.account_tree_outlined,
                      size: 13, color: AppAccent.color),
                  const SizedBox(width: 4),
                  Text(
                    '${dbPath.trDepth}',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withAlpha(AppAlpha.mediumHigh)),
                  ),
                ],
                if (dbPath.priority > 0) ...[
                  _buildSeparator(context),
                  const Icon(Icons.keyboard_double_arrow_up,
                      size: 13, color: AppAccent.color),
                  const SizedBox(width: 2),
                  Text(
                    '${dbPath.priority}',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withAlpha(AppAlpha.mediumHigh)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text('|',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(77))),
    );
  }
}
