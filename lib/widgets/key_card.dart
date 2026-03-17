import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/key_edit_sheet.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

/// Unified key card used in both the project designer (edit mode) and the
/// wallet detail view (read-only mode).
///
/// When [onDelete] is provided the card shows an edit icon and exposes delete
/// functionality inside the sheet.  Without it, a chevron is shown instead
/// and the sheet only allows renaming.
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
          child: Icon(Icons.key, color: mfpColor, size: 18),
        ),
        title: Text(
          label ?? mfp.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: hasLabel ? FontWeight.w600 : FontWeight.normal,
            color: hasLabel
                ? cs.onSurface
                : cs.onSurface.withAlpha(AppAlpha.muted),
            fontStyle: hasLabel ? FontStyle.normal : FontStyle.italic,
          ),
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
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              xpub,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withAlpha(AppAlpha.secondary),
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
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
        ),
      ),
    );
  }
}
