import 'package:flutter/material.dart';

/// Show a modal dialog requesting a password.
///
/// Returns the entered password if confirmed, or `null` if dismissed.
/// When [confirmRequired] is true, shows a second field for confirmation.
Future<String?> showPasswordPrompt(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool confirmRequired = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PasswordPromptDialog(
      title: title,
      subtitle: subtitle,
      confirmRequired: confirmRequired,
    ),
  );
}

class _PasswordPromptDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool confirmRequired;

  const _PasswordPromptDialog({
    required this.title,
    this.subtitle,
    required this.confirmRequired,
  });

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;

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
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onFieldSubmitted: (_) =>
                  widget.confirmRequired ? FocusScope.of(context).nextFocus() : _submit(),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password cannot be empty';
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
