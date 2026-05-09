import 'package:flutter/material.dart';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart' show APINetwork;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/colored_group_text.dart';
import 'package:deadbolt/widgets/key_edit_sheet.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

/// Unified key card used in both the project designer (edit mode) and the
/// wallet detail view (read-only mode).
///
/// When [onDelete] is provided the card shows an edit icon and exposes delete
/// functionality inside the sheet.  Without it, a chevron is shown instead
/// and the sheet only allows renaming.
///
/// When [isHot] is true the card shows an inline "HOT" badge next to the label
/// and the sheet exposes [onRevealSeed] / [onDeletePrivateInfo] actions.
class KeyCard extends StatelessWidget {
  final String mfp;
  final String derivationPath;
  final String xpub;
  final String? label;
  final Color mfpColor;
  final ValueChanged<String?> onNameSave;
  final bool Function(String)? isDuplicateName;
  final VoidCallback? onDelete;
  final bool canDelete;
  final VoidCallback? onMakeHot;
  final bool isHot;
  /// Called when the user confirms they want to view the seed phrase.
  /// Must return the decrypted seed string.
  final Future<String?> Function()? onRevealSeed;
  /// Called when the user confirms they want to delete the private key data.
  final VoidCallback? onDeletePrivateInfo;
  /// Override for the disclaimer shown before deleting private info.
  final String? deletePrivateInfoDisclaimer;
  /// Network for mnemonic SeedQR export.
  final APINetwork? network;
  const KeyCard({
    super.key,
    required this.mfp,
    required this.derivationPath,
    required this.xpub,
    required this.mfpColor,
    required this.onNameSave,
    this.label,
    this.isDuplicateName,
    this.onDelete,
    this.canDelete = true,
    this.onMakeHot,
    this.isHot = false,
    this.onRevealSeed,
    this.onDeletePrivateInfo,
    this.deletePrivateInfoDisclaimer,
    this.network,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final hasLabel = label != null;
    final isEditMode = onDelete != null;
    final derivPath = derivationPath.isEmpty ? l10n.rootPath : derivationPath;
    final derivColor = derivationPath.isEmpty
        ? AppAccent.color
        : cs.onSurface.withAlpha(AppAlpha.secondary);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: mfpColor.withAlpha(AppAlpha.subtle),
          child: Icon(
            Icons.key,
            color: mfpColor,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label ?? mfp.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasLabel ? FontWeight.w600 : FontWeight.normal,
                  color: hasLabel
                      ? cs.onSurface
                      : cs.onSurface.withAlpha(AppAlpha.muted),
                  fontStyle: hasLabel ? FontStyle.normal : FontStyle.italic,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isHot) ...[
              const SizedBox(width: 6),
              _HotBadge(),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                MfpBadge(
                  label: mfp.toUpperCase(),
                  color: mfpColor,
                  letterSpacing: 0.5,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    derivPath,
                    style: TextStyle(
                      fontSize: 11,
                      color: derivColor,
                      fontFamily: kMonospaceFontFamily,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            ColoredGroupText(text: xpub, fontSize: 11, truncate: true, monospace: true),
          ],
        ),
        trailing: Icon(
          isEditMode ? Icons.edit_outlined : Icons.chevron_right,
          size: 18,
          color: isEditMode ? cs.onSurface.withAlpha(AppAlpha.muted) : null,
        ),
        onTap: () => showKeySheet(
          context,
          mfp: mfp,
          initialName: label,
          derivationPath: derivationPath,
          xpub: xpub,
          mfpColor: mfpColor,
          onNameSave: onNameSave,
          isDuplicateName: isDuplicateName,
          onDelete: onDelete,
          canDelete: canDelete,
          onMakeHot: isHot ? null : onMakeHot,
          isHot: isHot,
          onRevealSeed: onRevealSeed,
          onDeletePrivateInfo: onDeletePrivateInfo,
          deletePrivateInfoDisclaimer: deletePrivateInfoDisclaimer,
          network: network,
        ),
      ),
    );
  }
}


/// Small orange "HOT" pill badge shown inline next to the key label.
class _HotBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppAccent.color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppAccent.color.withAlpha(AppAlpha.deleteAction), width: 1),
      ),
      child: Text(
        l10n.hotKeyBadge,
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
