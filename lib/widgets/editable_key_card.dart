import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/utils/toast_helper.dart';

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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // MFP badge + custom name + buttons row
            Row(
              children: [
                _buildMfpBadge(),
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
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    canDelete ? Icons.delete_outline : Icons.delete_forever_outlined,
                    size: 20,
                  ),
                  color: canDelete
                      ? Colors.red.withAlpha(180)
                      : Colors.grey.withAlpha(100),
                  onPressed: canDelete ? onDelete : null,
                  tooltip: canDelete
                      ? 'Remove key'
                      : 'Key in use - cannot delete',
                  visualDensity: VisualDensity.compact,
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
                    color: Colors.white54,
                  ),
                ),
                Expanded(
                  child: Text(
                    keyData.derivationPath,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // xpub
            Row(
              children: [
                const Text(
                  'xpub: ',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${keyData.xpub.substring(0, 20)}...${keyData.xpub.substring(keyData.xpub.length - 6)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white70,
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

  Widget _buildMfpBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: mfpColor.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: mfpColor.withAlpha(64), width: 2),
      ),
      child: Text(
        keyData.mfp.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withAlpha(230),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showNameDialog(BuildContext context) {
    final controller = TextEditingController(text: keyData.customName);
    String? errorText;

    void saveName(StateSetter setState, BuildContext dialogContext) {
      final name = controller.text.trim();

      // Check if name is already used by another key
      if (name.isNotEmpty) {
        final duplicate = allKeys.any((k) =>
            k.mfp != keyData.mfp &&
            k.customName != null &&
            k.customName!.toLowerCase() == name.toLowerCase());

        if (duplicate) {
          setState(() =>
              errorText = 'This name is already used by another key');
          return;
        }
      }

      onNameEdit?.call(name.isEmpty ? null : name);
      Navigator.pop(dialogContext);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Key name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Enter a name',
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) {
                setState(() => errorText = null);
              }
            },
            onSubmitted: (_) => saveName(setState, ctx),
          ),
          actions: [
            TextButton(
              onPressed: () {
                onNameEdit?.call(null);
                Navigator.pop(ctx);
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => saveName(setState, ctx),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
