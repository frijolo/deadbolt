import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/key_card_base.dart';

class EditableKeyCard extends StatelessWidget {
  final EditableKey keyData;
  final List<EditableKey> allKeys;
  final Color mfpColor;
  final ValueChanged<String?>? onNameEdit;
  final VoidCallback? onDelete;
  final bool canDelete;

  const EditableKeyCard({
    super.key,
    required this.keyData,
    required this.allKeys,
    required this.mfpColor,
    this.onNameEdit,
    this.onDelete,
    this.canDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // MFP badge + custom name + share + delete buttons row
            KeyCardHeader(
              mfp: keyData.mfp,
              mfpColor: mfpColor,
              customName: keyData.customName,
              tapToNameLabel: l10n.tapToName,
              copyKeyspecTooltip: l10n.copyKeyspecTooltip,
              keyCopiedMessage: l10n.keyCopied,
              keyspec: '[${keyData.mfp}/${keyData.derivationPath}]${keyData.xpub}',
              onNameTap: () => _showNameDialog(context),
              trailingActions: [
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    canDelete ? Icons.delete_outline : Icons.delete_forever_outlined,
                    size: 20,
                  ),
                  color: canDelete
                      ? Colors.red.withAlpha(AppAlpha.deleteAction)
                      : cs.onSurface.withAlpha(AppAlpha.disabled),
                  onPressed: canDelete ? onDelete : null,
                  tooltip: canDelete ? l10n.removeKeyTooltip : l10n.keyInUseTooltip,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Derivation path
            Row(
              children: [
                Text(
                  l10n.pathPrefix,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withAlpha(AppAlpha.secondary),
                  ),
                ),
                Expanded(
                  child: Text(
                    keyData.derivationPath,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // xpub
            Row(
              children: [
                Text(
                  l10n.xpubPrefix,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withAlpha(AppAlpha.secondary),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${keyData.xpub.substring(0, 20)}...${keyData.xpub.substring(keyData.xpub.length - 6)}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showNameDialog(BuildContext context) {
    showEditNameDialog(
      context,
      title: context.l10n.keyNameDialogTitle,
      currentName: keyData.customName,
      onSave: (name) => onNameEdit?.call(name),
      isDuplicate: (name) => allKeys.any((k) =>
          k.mfp != keyData.mfp &&
          k.customName != null &&
          k.customName!.toLowerCase() == name.toLowerCase()),
    );
  }
}
