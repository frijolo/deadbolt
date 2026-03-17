import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

class PathCard extends StatelessWidget {
  final ProjectSpendPath path;
  final List<ProjectKey> keys;
  final Color Function(String) mfpColorProvider;
  final ValueChanged<String?>? onNameEdit;
  final bool isTaproot;

  const PathCard({
    super.key,
    required this.path,
    required this.keys,
    required this.mfpColorProvider,
    this.onNameEdit,
    this.isTaproot = false,
  });

  List<String> get _mfps =>
      (jsonDecode(path.mfps) as List).cast<String>();

  String _getKeyLabel(String mfp) {
    final key = keys.where((k) => k.mfp == mfp).firstOrNull;
    return key?.customName ?? mfp.toUpperCase();
  }

  String _autoPathLabel(List<String> mfps) =>
      BitcoinFormatter.pathLabel(path.threshold, mfps, _getKeyLabel);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildLeading(context),
        title: _buildTitle(context),
        subtitle: _buildSubtitle(context),
      ),
    );
  }

  Widget _buildLeading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mfps = _mfps;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppAccent.color.withAlpha(AppAlpha.subtle),
            child: Icon(
              mfps.length == 1 ? Icons.key : Icons.diversity_3,
              color: AppAccent.color,
              size: 20,
            ),
          ),
          if (mfps.length > 1)
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
                  '${path.threshold}/${mfps.length}',
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

  Widget _buildTitle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mfps = _mfps;
    final isKeyPath = path.trDepth == -1;
    final hasRelTimelock = path.relTimelockValue > 0;
    final hasAbsTimelock = path.absTimelockValue > 0;
    final hasTimelock = hasRelTimelock || hasAbsTimelock;
    final hasCustomName = path.customName != null;
    final displayName =
        hasCustomName ? path.customName! : _autoPathLabel(mfps);

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _showNameDialog(context),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          hasCustomName ? FontWeight.w600 : FontWeight.normal,
                      color: hasCustomName
                          ? cs.onSurface
                          : cs.onSurface.withAlpha(AppAlpha.muted),
                      fontStyle:
                          hasCustomName ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
                Icon(Icons.edit, size: 14, color: cs.onSurface.withAlpha(120)),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        if (hasTimelock)
          PathTimelockBadge(
            isRelative: hasRelTimelock,
            label: hasRelTimelock
                ? BitcoinFormatter.formatRelativeTimelock(
                    RelativeTimelockType.fromString(path.relTimelockType),
                    path.relTimelockValue,
                  )
                : BitcoinFormatter.formatAbsoluteTimelock(
                    AbsoluteTimelockType.fromString(path.absTimelockType),
                    path.absTimelockValue,
                  ),
          ),
        if (isTaproot && isKeyPath) const PathKeyPathBadge(),
      ],
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    final mfps = _mfps;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...mfps.map((mfp) {
              final label = _getKeyLabel(mfp);
              return MfpBadge(
                label: label,
                color: mfpColorProvider(mfp),
                letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
              );
            }),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Icon(Icons.payments_outlined,
                  size: 13, color: AppAccent.color),
              const SizedBox(width: 4),
              Text(
                '${BitcoinFormatter.formatDouble(path.vbSweep, 2)} vB',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (path.trDepth >= 0) ...[
                _buildSeparator(context),
                const Icon(Icons.account_tree_outlined,
                    size: 13, color: AppAccent.color),
                const SizedBox(width: 4),
                Text(
                  '${path.trDepth}',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.mediumHigh)),
                ),
              ],
              if (path.priority > 0) ...[
                _buildSeparator(context),
                const Icon(Icons.keyboard_double_arrow_up,
                    size: 13, color: AppAccent.color),
                const SizedBox(width: 2),
                Text(
                  '${path.priority}',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.mediumHigh)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(77)),
      ),
    );
  }

  void _showNameDialog(BuildContext context) {
    showEditNameDialog(
      context,
      title: context.l10n.spendPathNameDialogTitle,
      currentName: path.customName,
      onSave: (name) => onNameEdit?.call(name),
    );
  }
}

// ─── Shared badge widgets (also used by _WalletPathCard) ──────────────────────

class PathTimelockBadge extends StatelessWidget {
  final bool isRelative;
  final String label;

  const PathTimelockBadge({
    super.key,
    required this.isRelative,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppAccent.color.withAlpha(24),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppAccent.color.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRelative ? Icons.update : Icons.event_available,
              size: 10,
              color: AppAccent.color,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: AppAccent.color,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PathKeyPathBadge extends StatelessWidget {
  const PathKeyPathBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(32),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blue.withAlpha(100)),
        ),
        child: Text(
          context.l10n.keyPathBadge,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
