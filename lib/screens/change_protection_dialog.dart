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
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<WalletDetailCubit>(),
      child: _ChangeProtectionDialog(currentProtection: currentProtection),
    ),
  );
}

class _ChangeProtectionDialog extends StatefulWidget {
  final APIProtectionType currentProtection;

  const _ChangeProtectionDialog({required this.currentProtection});

  @override
  State<_ChangeProtectionDialog> createState() =>
      _ChangeProtectionDialogState();
}

class _ChangeProtectionDialogState extends State<_ChangeProtectionDialog> {
  late APIProtectionType _selected;
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
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _protectionLabel(APIProtectionType type) => switch (type) {
        APIProtectionType.deviceKey => 'Device key (automatic)',
        APIProtectionType.userPassword => 'Password',
        APIProtectionType.xpubKey => 'xpub key',
      };

  Future<void> _confirm(BuildContext context) async {
    if (_isChanging) return;
    if (_selected == widget.currentProtection) {
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
    final isSame = _selected == widget.currentProtection;

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
              Text('New protection', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              RadioGroup<APIProtectionType>(
                groupValue: _selected,
                onChanged: _isChanging
                    ? (_) {}
                    : (v) => setState(() => _selected = v!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _radioRow(APIProtectionType.deviceKey,
                        'Device key (automatic)'),
                    _radioRow(APIProtectionType.userPassword, 'Password'),
                    _radioRow(APIProtectionType.xpubKey,
                        'xpub key (any descriptor key unlocks)'),
                  ],
                ),
              ),
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
              if (_selected == APIProtectionType.xpubKey) ...[
                const SizedBox(height: 12),
                _infoBox(
                  context,
                  'All xpubs from the descriptor will be registered as unlock keys. '
                  'Do not share those xpubs with third parties.',
                ),
              ],
              if (_selected == APIProtectionType.deviceKey &&
                  widget.currentProtection != APIProtectionType.deviceKey) ...[
                const SizedBox(height: 12),
                _infoBox(
                  context,
                  'Device key is tied to this device. If you copy the wallet '
                  'file without the device key file, it cannot be opened.',
                ),
              ],
              const SizedBox(height: 8),
              _infoBox(
                context,
                'The wallet database will be re-encrypted with a new key. '
                'Backup files are not affected — they use their own independent encryption.',
              ),
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
          onPressed: _isChanging || isSame ? null : () => _confirm(context),
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

  Widget _radioRow(APIProtectionType value, String label) {
    return Row(
      children: [
        Radio<APIProtectionType>(value: value),
        Expanded(child: Text(label)),
      ],
    );
  }

  Widget _infoBox(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
