import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';

/// Callback fired whenever protection type or security level changes.
typedef ProtectionChangedCallback = void Function(
  APIProtectionType protectionType,
  APISecurityLevel securityLevel,
);

/// Shared protection section used in wallet creation dialogs.
///
/// Owns obscure-toggle state for password fields. The parent passes in
/// [passwordController] / [passwordConfirmController] (which it owns) so it
/// can read the values during form submission.
class ProtectionSection extends StatefulWidget {
  final TextEditingController passwordController;
  final TextEditingController passwordConfirmController;
  final APIProtectionType initialProtectionType;
  final APISecurityLevel initialSecurityLevel;
  final ProtectionChangedCallback onChanged;

  const ProtectionSection({
    super.key,
    required this.passwordController,
    required this.passwordConfirmController,
    required this.initialProtectionType,
    required this.initialSecurityLevel,
    required this.onChanged,
  });

  @override
  State<ProtectionSection> createState() => _ProtectionSectionState();
}

class _ProtectionSectionState extends State<ProtectionSection> {
  late APIProtectionType _protectionType;
  late APISecurityLevel _securityLevel;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void initState() {
    super.initState();
    _protectionType = widget.initialProtectionType;
    _securityLevel = widget.initialSecurityLevel;
  }

  void _setProtection(APIProtectionType type) {
    setState(() => _protectionType = type);
    widget.onChanged(_protectionType, _securityLevel);
  }

  void _setLevel(APISecurityLevel level) {
    setState(() => _securityLevel = level);
    widget.onChanged(_protectionType, _securityLevel);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.protectionLabel, style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<APIProtectionType>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: APIProtectionType.deviceKey, label: Text(l10n.protectionNone)),
              ButtonSegment(value: APIProtectionType.userPassword, label: Text(l10n.protectionPassword)),
              ButtonSegment(value: APIProtectionType.xpubKey, label: Text(l10n.protectionXpub)),
            ],
            selected: {_protectionType},
            onSelectionChanged: (v) => _setProtection(v.first),
          ),
        ),
        if (_protectionType != APIProtectionType.deviceKey) ...[
          const SizedBox(height: 16),
          Text(l10n.securityLevelLabel, style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<APISecurityLevel>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: APISecurityLevel.standard, label: Text(l10n.securityLevelStandard)),
                ButtonSegment(value: APISecurityLevel.high, label: Text(l10n.securityLevelHigh)),
                ButtonSegment(value: APISecurityLevel.extreme, label: Text(l10n.securityLevelExtreme)),
              ],
              selected: {_securityLevel},
              onSelectionChanged: (v) => _setLevel(v.first),
            ),
          ),
        ],
        if (_protectionType == APIProtectionType.xpubKey) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.protectionXpubInfo,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_protectionType == APIProtectionType.userPassword) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: l10n.newPasswordLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (_protectionType != APIProtectionType.userPassword) return null;
              if (v == null || v.isEmpty) return l10n.validatorPasswordEmpty;
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.passwordConfirmController,
            obscureText: _obscurePasswordConfirm,
            decoration: InputDecoration(
              labelText: l10n.confirmPasswordLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePasswordConfirm
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () => setState(
                    () => _obscurePasswordConfirm = !_obscurePasswordConfirm),
              ),
            ),
            validator: (v) {
              if (_protectionType != APIProtectionType.userPassword) return null;
              if (v != widget.passwordController.text) {
                return l10n.validatorPasswordsNoMatch;
              }
              return null;
            },
          ),
        ],
      ],
    );
  }
}
