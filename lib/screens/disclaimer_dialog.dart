import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/config/constants.dart' show kDisclaimerHiddenUntilKey;
import 'package:deadbolt/l10n/l10n.dart';

/// Returns true if the disclaimer should be shown right now.
Future<bool> shouldShowDisclaimer() async {
  final prefs = await SharedPreferences.getInstance();
  final hiddenUntil = prefs.getInt(kDisclaimerHiddenUntilKey);
  if (hiddenUntil == null) return true;
  return DateTime.now().millisecondsSinceEpoch > hiddenUntil;
}

Future<void> _suppressFor7Days() async {
  final prefs = await SharedPreferences.getInstance();
  final until = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
  await prefs.setInt(kDisclaimerHiddenUntilKey, until);
}

class DisclaimerDialog extends StatelessWidget {
  const DisclaimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, size: 36, color: theme.colorScheme.error),
      title: Text(l10n.disclaimerTitle, textAlign: TextAlign.center),
      content: Text(l10n.disclaimerBody),
      actions: [
        TextButton(
          onPressed: () async {
            await _suppressFor7Days();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l10n.disclaimerDontShow7Days),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
