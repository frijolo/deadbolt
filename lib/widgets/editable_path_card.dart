import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';

class EditablePathCard extends StatelessWidget {
  final int index;
  final EditableSpendPath path;
  final List<ProjectKey> availableKeys;
  final Color Function(String) mfpColorProvider;
  final ValueChanged<int> onThresholdChanged;
  final void Function(String mfp) onMfpAdded;
  final void Function(String mfp) onMfpRemoved;
  final ValueChanged<int> onRelTimelockChanged;
  final ValueChanged<int> onAbsTimelockChanged;
  final VoidCallback onDelete;
  final bool isTaproot;
  final ValueChanged<bool>? onKeyPathChanged;
  final ValueChanged<String?>? onNameEdit;

  const EditablePathCard({
    super.key,
    required this.index,
    required this.path,
    required this.availableKeys,
    required this.mfpColorProvider,
    required this.onThresholdChanged,
    required this.onMfpAdded,
    required this.onMfpRemoved,
    required this.onRelTimelockChanged,
    required this.onAbsTimelockChanged,
    required this.onDelete,
    this.isTaproot = false,
    this.onKeyPathChanged,
    this.onNameEdit,
  });

  String? get _validationError {
    if (path.mfps.isEmpty) return 'Must have at least one key';
    if (path.threshold < 1) return 'Threshold must be at least 1';
    if (path.threshold > path.mfps.length) {
      return 'Threshold cannot exceed number of keys';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final validationError = _validationError;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: validationError != null
          ? Colors.red.withAlpha(20)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            if (validationError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(32),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        validationError,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildKeysSection(context),
            const SizedBox(height: 12),
            _buildThresholdRow(),
            const SizedBox(height: 8),
            _buildTimelockRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final canBeKeyPath = path.canBeKeyPath;
    final showKeyPathBadge = isTaproot && canBeKeyPath;

    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Colors.orange.withAlpha(32),
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _showNameDialog(context),
            child: Text(
              path.customName ?? 'Tap to name',
              style: TextStyle(
                fontSize: 14,
                fontWeight: path.customName != null
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: path.customName != null
                    ? Colors.white
                    : Colors.white38,
                fontStyle: path.customName != null
                    ? FontStyle.normal
                    : FontStyle.italic,
              ),
            ),
          ),
        ),
        if (showKeyPathBadge)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              onTap: onKeyPathChanged != null
                  ? () => onKeyPathChanged!(!path.isKeyPath)
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: path.isKeyPath
                      ? Colors.blue.withAlpha(32)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: path.isKeyPath
                        ? Colors.blue.withAlpha(100)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.key,
                      size: 10,
                      color: path.isKeyPath ? Colors.blue : Colors.white38,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      path.isKeyPath ? 'KEY PATH' : 'Set as key path',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: path.isKeyPath ? Colors.blue : Colors.white38,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          color: Colors.red.withAlpha(180),
          onPressed: onDelete,
          tooltip: 'Remove path',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  String _getKeyLabel(String mfp) {
    final key = availableKeys.firstWhere(
      (k) => k.mfp == mfp,
      orElse: () => availableKeys.first,
    );
    return key.customName ?? mfp.toUpperCase();
  }

  Widget _buildKeysSection(BuildContext context) {
    final unusedKeys =
        availableKeys.where((k) => !path.mfps.contains(k.mfp)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Keys',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var mfp in path.mfps)
              _buildRemovableMfpBadge(
                _getKeyLabel(mfp),
                mfpColorProvider(mfp),
                mfp,
              ),
            if (unusedKeys.isNotEmpty)
              _buildAddKeyButton(context, unusedKeys),
          ],
        ),
      ],
    );
  }

  Widget _buildRemovableMfpBadge(String label, Color color, String mfp) {
    return Container(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2, right: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(64), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(230),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () => onMfpRemoved(mfp),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: color.withAlpha(180)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddKeyButton(BuildContext context, List<ProjectKey> unusedKeys) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 32),
      onSelected: (mfp) => onMfpAdded(mfp),
      itemBuilder: (context) => unusedKeys
          .map((k) => PopupMenuItem<String>(
                value: k.mfp,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: mfpColorProvider(k.mfp),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      k.mfp.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (k.customName != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        k.customName!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ],
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.orange.withAlpha(100),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: Colors.orange),
            SizedBox(width: 4),
            Text(
              'Add key',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdRow() {
    final maxThreshold = path.mfps.isEmpty ? 1 : path.mfps.length;
    final currentThreshold = path.threshold.clamp(1, maxThreshold);

    return Row(
      children: [
        const Text(
          'Threshold',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<int>(
          offset: const Offset(0, 32),
          onSelected: (value) => onThresholdChanged(value),
          tooltip: 'Change threshold',
          itemBuilder: (context) => List.generate(
            maxThreshold,
            (i) => PopupMenuItem(
              value: i + 1,
              child: Text('${i + 1}'),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(32),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withAlpha(64)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$currentThreshold',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.edit,
                  size: 12,
                  color: Colors.orange,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'of ${path.mfps.length}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildTimelockRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TimelockField(
            label: 'Relative timelock',
            icon: Icons.update,
            value: path.relTimelock,
            onChanged: onRelTimelockChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TimelockField(
            label: 'Absolute timelock',
            icon: Icons.event_available,
            value: path.absTimelock,
            onChanged: onAbsTimelockChanged,
          ),
        ),
      ],
    );
  }

  void _showNameDialog(BuildContext context) {
    final controller = TextEditingController(text: path.customName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spend path name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Enter a name'),
          onSubmitted: (_) {
            final name = controller.text.trim();
            onNameEdit?.call(name.isEmpty ? null : name);
            Navigator.pop(ctx);
          },
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
            onPressed: () {
              final name = controller.text.trim();
              onNameEdit?.call(name.isEmpty ? null : name);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _TimelockField extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  const _TimelockField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.white54),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: TextFormField(
            initialValue: value == 0 ? '' : value.toString(),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              hintText: '0',
              hintStyle: TextStyle(color: Colors.white24),
            ),
            onChanged: (text) {
              final parsed = int.tryParse(text) ?? 0;
              onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }
}
