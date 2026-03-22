import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/toast_helper.dart';

/// Opens a dialog to change the wallet's encryption protection scheme.
/// Calls [WalletDetailCubit.changeProtection] on confirm.
Future<void> showChangeProtectionDialog(
  BuildContext context, {
  required APIProtectionType currentProtection,
  required APISecurityLevel currentSecurityLevel,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<WalletDetailCubit>(),
      child: _ChangeProtectionDialog(
        currentProtection: currentProtection,
        currentSecurityLevel: currentSecurityLevel,
      ),
    ),
  );
}

class _ChangeProtectionDialog extends StatefulWidget {
  final APIProtectionType currentProtection;
  final APISecurityLevel currentSecurityLevel;

  const _ChangeProtectionDialog({
    required this.currentProtection,
    required this.currentSecurityLevel,
  });

  @override
  State<_ChangeProtectionDialog> createState() =>
      _ChangeProtectionDialogState();
}

class _ChangeProtectionDialogState extends State<_ChangeProtectionDialog> {
  late APIProtectionType _selected;
  late APISecurityLevel _level;
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _isChanging = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentProtection;
    _level = widget.currentSecurityLevel;
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _protectionLabel(APIProtectionType type) => switch (type) {
        APIProtectionType.deviceKey => 'Unprotected',
        APIProtectionType.userPassword => 'Password',
        APIProtectionType.xpubKey => 'XPub',
      };

  bool get _hasChanges =>
      _selected != widget.currentProtection ||
      _level != widget.currentSecurityLevel;

  Future<void> _confirm(BuildContext context) async {
    if (_isChanging) return;
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _isChanging = true);
    final cubit = context.read<WalletDetailCubit>();
    final ok = await cubit.changeProtection(
      newProtectionType: _selected,
      newPassword:
          _selected == APIProtectionType.userPassword ? _passwordCtrl.text : null,
      securityLevel: _level,
    );

    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessToast(context,
          'Protection changed to ${_protectionLabel(_selected)}');
    } else {
      setState(() => _isChanging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Change wallet protection'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: ${_protectionLabel(widget.currentProtection)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text('Protection', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<APIProtectionType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: APIProtectionType.deviceKey,
                    label: Text('None'),
                  ),
                  ButtonSegment(
                    value: APIProtectionType.userPassword,
                    label: Text('Password'),
                  ),
                  ButtonSegment(
                    value: APIProtectionType.xpubKey,
                    label: Text('XPub'),
                  ),
                ],
                selected: {_selected},
                onSelectionChanged: _isChanging
                    ? null
                    : (v) => setState(() => _selected = v.first),
              ),
              if (_selected != APIProtectionType.deviceKey) ...[
                const SizedBox(height: 16),
                Text('Anti-brute-force level',
                    style: theme.textTheme.labelMedium),
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
                  onSelectionChanged: _isChanging
                      ? null
                      : (v) => setState(() => _level = v.first),
                ),
              ],
              if (_selected == APIProtectionType.userPassword) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  enabled: !_isChanging,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (_selected != APIProtectionType.userPassword) return null;
                    if (v == null || v.isEmpty) return 'Password cannot be empty';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  enabled: !_isChanging,
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
                    if (_selected != APIProtectionType.userPassword) return null;
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isChanging ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isChanging || !_hasChanges ? null : () => _confirm(context),
          child: _isChanging
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change'),
        ),
      ],
    );
  }
}
