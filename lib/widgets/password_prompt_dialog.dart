import 'package:flutter/material.dart';
import 'package:deadbolt/widgets/text_import_sheet.dart';

/// Show a modal dialog requesting a password or xpub.
///
/// Returns the entered value if confirmed, or `null` if dismissed.
/// When [confirmRequired] is true, shows a second field for confirmation.
/// [inputLabel] overrides the default "Password" field label.
/// [obscureByDefault] controls whether the input is hidden initially (default true).
Future<String?> showPasswordPrompt(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool confirmRequired = false,
  String inputLabel = 'Password',
  bool obscureByDefault = true,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PasswordPromptDialog(
      title: title,
      subtitle: subtitle,
      confirmRequired: confirmRequired,
      inputLabel: inputLabel,
      obscureByDefault: obscureByDefault,
    ),
  );
}

/// Extracts the bare xpub from either a bare xpub or a keyspec `[mfp/path]xpub`.
/// Returns the xpub string, or null if the input is empty/invalid.
String? _extractXpub(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  // Keyspec format: [fingerprint/path]xpub
  final match = RegExp(r'^\[[^\]]+\](.+)$').firstMatch(trimmed);
  return match != null ? match.group(1)!.trim() : trimmed;
}

/// Show a dialog to unlock an XpubKey-protected wallet.
/// Accepts either a bare xpub or a full keyspec (`[mfp/path]xpub`).
/// Returns the extracted bare xpub, or null if cancelled.
Future<String?> showXpubUnlockDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _XpubUnlockDialog(),
  );
}

class _XpubUnlockDialog extends StatefulWidget {
  const _XpubUnlockDialog();

  @override
  State<_XpubUnlockDialog> createState() => _XpubUnlockDialogState();
}

class _XpubUnlockDialogState extends State<_XpubUnlockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_extractXpub(_ctrl.text)!);
    }
  }

  Future<void> _onImport() async {
    final result = await showTextImportSheet(context);
    if (result == null || result.trim().isEmpty || !mounted) return;
    final xpub = _extractXpub(result);
    if (xpub == null) return;
    setState(() => _ctrl.text = xpub);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter xpub to unlock'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste any xpub registered for this wallet. Keyspec format ([mfp/path]xpub) is also accepted.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'xpub or keyspec',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (_extractXpub(v) == null) return 'Invalid xpub or keyspec';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton.icon(
          onPressed: _onImport,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Import'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

class _PasswordPromptDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool confirmRequired;
  final String inputLabel;
  final bool obscureByDefault;

  const _PasswordPromptDialog({
    required this.title,
    this.subtitle,
    required this.confirmRequired,
    this.inputLabel = 'Password',
    this.obscureByDefault = true,
  });

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  late bool _obscure = widget.obscureByDefault;
  late bool _obscureConfirm = widget.obscureByDefault;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_passwordCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            TextFormField(
              controller: _passwordCtrl,
              autofocus: true,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: widget.inputLabel,
                border: const OutlineInputBorder(),
                suffixIcon: widget.obscureByDefault
                    ? IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )
                    : null,
              ),
              onFieldSubmitted: (_) =>
                  widget.confirmRequired ? FocusScope.of(context).nextFocus() : _submit(),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return '${widget.inputLabel} cannot be empty';
                }
                return null;
              },
            ),
            if (widget.confirmRequired) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  if (v != _passwordCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
