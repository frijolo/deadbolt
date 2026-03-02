import 'package:flutter/material.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/key_card_base.dart';

class KeyCard extends StatelessWidget {
  final ProjectKey keyData;
  final List<ProjectKey> allKeys;
  final Color mfpColor;
  final ValueChanged<String?>? onNameEdit;

  const KeyCard({
    super.key,
    required this.keyData,
    required this.allKeys,
    required this.mfpColor,
    this.onNameEdit,
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
            // MFP badge + custom name + copy button row
            KeyCardHeader(
              mfp: keyData.mfp,
              mfpColor: mfpColor,
              customName: keyData.customName,
              tapToNameLabel: l10n.tapToName,
              copyKeyspecTooltip: l10n.copyKeyspecTooltip,
              keyCopiedMessage: l10n.keyCopied,
              keyspec: '[${keyData.mfp}/${keyData.derivationPath}]${keyData.xpub}',
              onNameTap: () => _showNameDialog(context),
            ),
            const SizedBox(height: 8),
            // Derivation path
            Row(
              children: [
                Text(
                  l10n.pathPrefix,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withAlpha(AppAlpha.muted),
                  ),
                ),
                Expanded(
                  child: Text(
                    keyData.derivationPath.isEmpty
                        ? l10n.rootPath
                        : keyData.derivationPath,
                    style: TextStyle(
                      fontSize: 12,
                      color: keyData.derivationPath.isEmpty
                          ? AppAccent.color
                          : cs.onSurface.withAlpha(AppAlpha.mediumHigh),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Xpub
            Row(
              children: [
                Text(
                  l10n.xpubPrefix,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withAlpha(AppAlpha.muted),
                  ),
                ),
                Expanded(
                  child: Text(
                    keyData.xpub,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withAlpha(AppAlpha.secondary),
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
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
          k.id != keyData.id &&
          k.customName != null &&
          k.customName!.toLowerCase() == name.toLowerCase()),
    );
  }
}
