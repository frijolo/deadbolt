import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/l10n/l10n.dart';
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

  String _protectionLabel(AppLocalizations l10n, APIProtectionType type) =>
      switch (type) {
        APIProtectionType.deviceKey => l10n.protectionUnprotected,
        APIProtectionType.userPassword => l10n.protectionPassword,
        APIProtectionType.xpubKey => l10n.protectionXpub,
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
      final l10n = context.l10n;
      Navigator.of(context).pop();
      showSuccessToast(context,
          l10n.protectionChangedToast(_protectionLabel(l10n, _selected)));
    } else {
      setState(() => _isChanging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.changeProtectionTitle),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          dragStartBehavior: DragStartBehavior.down,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.changeProtectionCurrent(
                    _protectionLabel(l10n, widget.currentProtection)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.protectionLabel, style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<APIProtectionType>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: APIProtectionType.deviceKey,
                    label: Text(l10n.protectionNone),
                  ),
                  ButtonSegment(
                    value: APIProtectionType.userPassword,
                    label: Text(l10n.protectionPassword),
                  ),
                  ButtonSegment(
                    value: APIProtectionType.xpubKey,
                    label: Text(l10n.protectionXpub),
                  ),
                ],
                selected: {_selected},
                onSelectionChanged: _isChanging
                    ? null
                    : (v) => setState(() => _selected = v.first),
              ),
              if (_selected != APIProtectionType.deviceKey) ...[
                const SizedBox(height: 16),
                Text(l10n.securityLevelLabel,
                    style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                SegmentedButton<APISecurityLevel>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: APISecurityLevel.standard,
                      label: Text(l10n.securityLevelStandard),
                    ),
                    ButtonSegment(
                      value: APISecurityLevel.high,
                      label: Text(l10n.securityLevelHigh),
                    ),
                    ButtonSegment(
                      value: APISecurityLevel.extreme,
                      label: Text(l10n.securityLevelExtreme),
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
                    labelText: l10n.newPasswordLabel,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (_selected != APIProtectionType.userPassword) return null;
                    if (v == null || v.isEmpty) return l10n.validatorPasswordEmpty;
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  enabled: !_isChanging,
                  decoration: InputDecoration(
                    labelText: l10n.confirmPasswordLabel,
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
                    if (v != _passwordCtrl.text) return l10n.validatorPasswordsNoMatch;
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
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _isChanging || !_hasChanges ? null : () => _confirm(context),
          child: _isChanging
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.changeButton),
        ),
      ],
    );
  }
}
