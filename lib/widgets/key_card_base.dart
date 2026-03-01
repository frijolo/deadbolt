import 'package:flutter/material.dart';

import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';
import 'package:deadbolt/widgets/text_export_sheet.dart';

/// Shared header row used by both [KeyCard] and [EditableKeyCard].
///
/// Displays an MFP badge, a tappable name label, and a share button.
/// Additional trailing widgets can be appended via [trailingActions].
class KeyCardHeader extends StatelessWidget {
  final String mfp;
  final Color mfpColor;
  final String? customName;
  final String tapToNameLabel;
  final String copyKeyspecTooltip;
  final String keyCopiedMessage;
  final String keyspec;
  final VoidCallback onNameTap;
  /// Optional extra widgets appended after the share button (e.g., delete button).
  final List<Widget> trailingActions;

  const KeyCardHeader({
    super.key,
    required this.mfp,
    required this.mfpColor,
    required this.customName,
    required this.tapToNameLabel,
    required this.copyKeyspecTooltip,
    required this.keyCopiedMessage,
    required this.keyspec,
    required this.onNameTap,
    this.trailingActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        MfpBadge(label: mfp.toUpperCase(), color: mfpColor),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: onNameTap,
            child: Text(
              customName ?? tapToNameLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: customName != null ? FontWeight.w600 : FontWeight.normal,
                color: customName != null
                    ? cs.onSurface
                    : cs.onSurface.withAlpha(AppAlpha.muted),
                fontStyle: customName != null ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.ios_share, size: 16),
          color: cs.onSurface.withAlpha(AppAlpha.muted),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: copyKeyspecTooltip,
          onPressed: () {
            showTextExportSheet(
              context,
              text: keyspec,
              fileName: 'key_$mfp',
              copiedMessage: keyCopiedMessage,
            );
          },
        ),
        ...trailingActions,
      ],
    );
  }
}
