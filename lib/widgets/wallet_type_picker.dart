import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/enum_formatters.dart';

/// Two-axis wallet type selector: policy (SingleSig / Miniscript) ×
/// address format (Legacy / SegWit / Nested / Taproot).
///
/// Shows the resolved [APIWalletType] as an italic hint below the selectors.
class WalletTypePicker extends StatelessWidget {
  final WalletPolicy policy;
  final WalletAddressFormat addressFormat;
  final ValueChanged<WalletPolicy> onPolicyChanged;
  final ValueChanged<WalletAddressFormat> onFormatChanged;

  const WalletTypePicker({
    super.key,
    required this.policy,
    required this.addressFormat,
    required this.onPolicyChanged,
    required this.onFormatChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final resultType = walletTypeFromAxes(policy, addressFormat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<WalletPolicy>(
          segments: [
            ButtonSegment(
              value: WalletPolicy.singleSig,
              label: Text(l10n.walletPolicySingleSig),
              icon: const Icon(Icons.key_outlined, size: 14),
            ),
            ButtonSegment(
              value: WalletPolicy.miniscript,
              label: Text(l10n.walletPolicyMiniscript),
              icon: const Icon(Icons.account_tree_outlined, size: 14),
            ),
          ],
          selected: {policy},
          onSelectionChanged: (s) => onPolicyChanged(s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<WalletAddressFormat>(
          segments: [
            ButtonSegment(
              value: WalletAddressFormat.legacy,
              label: Text(l10n.walletAddressLegacy),
            ),
            ButtonSegment(
              value: WalletAddressFormat.segwit,
              label: Text(l10n.walletAddressSegwit),
            ),
            ButtonSegment(
              value: WalletAddressFormat.nestedSegwit,
              label: Text(l10n.walletAddressNested),
            ),
            ButtonSegment(
              value: WalletAddressFormat.taproot,
              label: Text(l10n.walletAddressTaproot),
            ),
          ],
          selected: {addressFormat},
          onSelectionChanged: (s) => onFormatChanged(s.first),
        ),
        const SizedBox(height: 6),
        Text(
          '→ ${localizedWalletTypeName(context, resultType)}',
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withAlpha(AppAlpha.secondary),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
