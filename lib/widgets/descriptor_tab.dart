import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/export_sheet.dart';

/// Descriptor tab used in both the project designer and the wallet detail view.
/// When [isDirty] is true, shows a banner indicating the descriptor is outdated.
class DescriptorTab extends StatelessWidget {
  final String descriptor;
  final bool isDirty;

  const DescriptorTab({super.key, required this.descriptor, this.isDirty = false});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        if (isDirty)
          _StaleBanner(label: l10n.descriptorOutdatedBanner),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  descriptor,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showDescriptorExportSheet(
                context,
                descriptor: descriptor,
                fileName: 'descriptor',
                copiedMessage: l10n.descriptorCopied,
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: Text(l10n.copyDescriptorTooltip),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppAccent.color,
                side: BorderSide(color: AppAccent.color.withAlpha(100)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  final String label;

  const _StaleBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    const color = Colors.amber;
    return Container(
      width: double.infinity,
      color: color.withAlpha(20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
