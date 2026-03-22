import 'package:flutter/material.dart';

import 'package:deadbolt/src/rust/api/model.dart';

/// Result returned by [showExportBackupDialog].
class ExportBackupOptions {
  final APIProtectionType protectionType;
  final String? password;
  final APISecurityLevel securityLevel;

  ExportBackupOptions({
    required this.protectionType,
    required this.securityLevel,
    this.password,
  });
}

/// Shows a dialog where the user chooses:
/// - export protection type (Password or XPub)
/// - anti-brute-force security level
/// - password (when UserPassword is selected)
///
/// Returns [ExportBackupOptions] on confirm, null on cancel.
Future<ExportBackupOptions?> showExportBackupDialog(
  BuildContext context,
) async {
  return showDialog<ExportBackupOptions>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ExportBackupDialog(),
  );
}

class _ExportBackupDialog extends StatefulWidget {
  const _ExportBackupDialog();

  @override
  State<_ExportBackupDialog> createState() => _ExportBackupDialogState();
}

class _ExportBackupDialogState extends State<_ExportBackupDialog> {
  APIProtectionType _protection = APIProtectionType.userPassword;
  APISecurityLevel _level = APISecurityLevel.standard;
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

  void _confirm() {
    if (_protection == APIProtectionType.userPassword) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }
    Navigator.of(context).pop(ExportBackupOptions(
      protectionType: _protection,
      securityLevel: _level,
      password: _protection == APIProtectionType.userPassword
          ? _passwordCtrl.text
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Export backup'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Protection', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<APIProtectionType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: APIProtectionType.userPassword,
                    label: Text('Password'),
                  ),
                  ButtonSegment(
                    value: APIProtectionType.xpubKey,
                    label: Text('XPub'),
                  ),
                ],
                selected: {_protection},
                onSelectionChanged: (v) =>
                    setState(() => _protection = v.first),
              ),
              if (_protection == APIProtectionType.userPassword) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Backup password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (_protection != APIProtectionType.userPassword) {
                      return null;
                    }
                    if (v == null || v.isEmpty) return 'Password required';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (_protection != APIProtectionType.userPassword) {
                      return null;
                    }
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              Text('Anti-brute-force level', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<APISecurityLevel>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: APISecurityLevel.standard,
                    label: Text('Standard'),
                  ),
                  ButtonSegment(
                    value: APISecurityLevel.high,
                    label: Text('High'),
                  ),
                  ButtonSegment(
                    value: APISecurityLevel.extreme,
                    label: Text('Extreme'),
                  ),
                ],
                selected: {_level},
                onSelectionChanged: (v) => setState(() => _level = v.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Export'),
        ),
      ],
    );
  }
}
