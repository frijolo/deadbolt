import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';

/// Small orange "HOT" pill badge. Used inline next to a key label or a
/// spend path label to indicate enough private key material is present
/// in the app to sign with it.
class HotBadge extends StatelessWidget {
  const HotBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppAccent.color.withAlpha(AppAlpha.dim),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppAccent.color.withAlpha(AppAlpha.deleteAction), width: 1),
      ),
      child: Text(
        l10n.hotKeyBadge,
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
