import 'package:flutter/material.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart';

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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // MFP badge + custom name + copy button row
            Row(
              children: [
                MfpBadge(label: keyData.mfp.toUpperCase(), color: mfpColor),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showNameDialog(context),
                    child: Text(
                      keyData.customName ?? l10n.tapToName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: keyData.customName != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: keyData.customName != null
                            ? Colors.white
                            : Colors.white38,
                        fontStyle: keyData.customName != null
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share, size: 16),
                  color: Colors.white38,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: l10n.copyKeyspecTooltip,
                  onPressed: () {
                    final keyspec =
                        '[${keyData.mfp}/${keyData.derivationPath}]${keyData.xpub}';
                    showTextExportSheet(
                      context,
                      text: keyspec,
                      fileName: 'key_${keyData.mfp}',
                      copiedMessage: l10n.keyCopied,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Derivation path
            Row(
              children: [
                Text(
                  l10n.pathPrefix,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white38,
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
                          ? Colors.orange
                          : Colors.white70,
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white38,
                  ),
                ),
                Expanded(
                  child: Text(
                    keyData.xpub,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
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
