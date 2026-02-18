import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

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
                      keyData.customName ?? 'Tap to name',
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
                  icon: const Icon(Icons.copy, size: 16),
                  color: Colors.white38,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Copy keyspec',
                  onPressed: () {
                    final keyspec =
                        '[${keyData.mfp}/${keyData.derivationPath}]${keyData.xpub}';
                    Clipboard.setData(ClipboardData(text: keyspec));
                    showSuccessToast(context, 'Key copied');
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Derivation path
            Row(
              children: [
                const Text(
                  'Path: ',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white38,
                  ),
                ),
                Expanded(
                  child: Text(
                    keyData.derivationPath.isEmpty
                        ? '(root)'
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
                const Text(
                  'Xpub: ',
                  style: TextStyle(
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
      title: 'Key name',
      currentName: keyData.customName,
      onSave: (name) => onNameEdit?.call(name),
      isDuplicate: (name) => allKeys.any((k) =>
          k.id != keyData.id &&
          k.customName != null &&
          k.customName!.toLowerCase() == name.toLowerCase()),
    );
  }
}
