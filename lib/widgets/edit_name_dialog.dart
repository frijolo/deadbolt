import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';

/// Show a dialog to edit a custom name.
///
/// [title] is the dialog title (e.g. 'Key name', 'Spend path name').
/// [currentName] is the pre-filled current value.
/// [onSave] is called with the new name, or null when cleared.
/// [isDuplicate] is an optional validator; return true if the name is already
/// in use by another item. When provided the dialog shows an inline error
/// and requires a StatefulBuilder to update it reactively.
void showEditNameDialog(
  BuildContext context, {
  required String title,
  required String? currentName,
  required ValueChanged<String?> onSave,
  bool Function(String name)? isDuplicate,
}) {
  final controller = TextEditingController(text: currentName);
  final l10n = context.l10n;

  if (isDuplicate == null) {
    // Simple dialog — no duplicate validation needed.
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: l10n.enterName),
          onSubmitted: (_) {
            final name = controller.text.trim();
            onSave(name.isEmpty ? null : name);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              onSave(null);
              Navigator.pop(ctx);
            },
            child: Text(l10n.clear),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              onSave(name.isEmpty ? null : name);
              Navigator.pop(ctx);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  } else {
    // Dialog with duplicate validation.
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void saveName() {
            final name = controller.text.trim();
            if (name.isNotEmpty && isDuplicate(name)) {
              setState(() => errorText = l10n.nameAlreadyUsed);
              return;
            }
            onSave(name.isEmpty ? null : name);
            Navigator.pop(ctx);
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.enterName,
                errorText: errorText,
              ),
              onChanged: (_) {
                if (errorText != null) {
                  setState(() => errorText = null);
                }
              },
              onSubmitted: (_) => saveName(),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  onSave(null);
                  Navigator.pop(ctx);
                },
                child: Text(l10n.clear),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: saveName,
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
  }
}
