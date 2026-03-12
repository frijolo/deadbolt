import 'package:flutter/material.dart';

import 'colored_address_text.dart';

/// Displays a Bitcoin outpoint (txid:vout) or bare txid using the same
/// alternating-color 4-char group style as [ColoredAddressText].
/// The `:vout` suffix is shown in faint color and always kept visible.
/// Truncation (middle) is applied to the txid portion.
class OutpointText extends StatelessWidget {
  final String txid;
  final int? vout;
  final double? fontSize;
  final bool truncate;

  const OutpointText({
    super.key,
    required this.txid,
    this.vout,
    this.fontSize,
    this.truncate = true,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredAddressText(
      address: txid,
      suffix: vout != null ? ':$vout' : '',
      fontSize: fontSize,
      truncate: truncate,
    );
  }
}
