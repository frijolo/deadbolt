import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';

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
    final key = keys.firstWhere((k) => k.mfp == mfp, orElse: () => keys.first);
    return key.customName ?? mfp.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _buildLeading(),
        title: _buildTitle(context),
        subtitle: _buildMetrics(),
      ),
    );
  }

  Widget _buildLeading() {
    final mfps = _mfps;
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.orange.withAlpha(32),
          child: Icon(
            mfps.length == 1 ? Icons.key : Icons.diversity_3,
            color: Colors.orange,
            size: 20,
          ),
        ),
        if (mfps.length > 1)
          Positioned(
            bottom: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(64),
                border: Border.all(color: Colors.orange, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "${path.threshold} of ${mfps.length}",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    final mfps = _mfps;
    final isKeyPath = path.trDepth == -1;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showNameDialog(context),
                    child: Text(
                      path.customName ?? 'Tap to name',
                      style: TextStyle(
                        fontSize: 13,
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
                if (isTaproot && isKeyPath)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(32),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.withAlpha(100)),
                      ),
                      child: const Text(
                        'KEY PATH',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var mfp in mfps)
                _buildMfpBadge(
                  _getKeyLabel(mfp),
                  mfpColorProvider(mfp),
                  mfp,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMfpBadge(String label, Color backgroundColor, String mfp) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: backgroundColor.withAlpha(64), width: 2),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withAlpha(230),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
        ),
      ),
    );
  }

  Widget _buildMetrics() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.payments_outlined, size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Text(
              "${path.vbSweep.toStringAsFixed(2)} vB",
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (path.trDepth >= 0) ...[
              _buildSeparator(),
              const Icon(Icons.account_tree_outlined,
                  size: 14, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                "${path.trDepth}",
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
            if (path.relTimelockValue > 0) ...[
              _buildSeparator(),
              const Icon(Icons.update, size: 14, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                BitcoinFormatter.formatRelativeTimelock(
                  RelativeTimelockType.fromString(path.relTimelockType),
                  path.relTimelockValue,
                ),
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
            if (path.absTimelockValue > 0) ...[
              _buildSeparator(),
              const Icon(Icons.event_available, size: 14, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                BitcoinFormatter.formatAbsoluteTimelock(
                  AbsoluteTimelockType.fromString(path.absTimelockType),
                  path.absTimelockValue,
                ),
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text("|", style: TextStyle(color: Colors.grey.withAlpha(77))),
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
