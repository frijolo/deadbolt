import 'package:flutter/material.dart';

/// Displays a Bitcoin outpoint (txid:vout) or bare txid in monospace, with
/// dynamic middle truncation based on available width.
///
/// The `:vout` suffix is always kept visible when [vout] is provided.
/// Truncation only happens in the txid portion.
class OutpointText extends StatelessWidget {
  final String txid;
  final int? vout;
  final double fontSize;

  const OutpointText({
    super.key,
    required this.txid,
    this.vout,
    this.fontSize = 11,
  });

  TextStyle get _style =>
      TextStyle(fontFamily: 'monospace', fontSize: fontSize);

  double _measure(String text) {
    final p = TextPainter(
      text: TextSpan(text: text, style: _style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    return p.width;
  }

  @override
  Widget build(BuildContext context) {
    final suffix = vout != null ? ':$vout' : '';
    final full = '$txid$suffix';

    return LayoutBuilder(builder: (_, constraints) {
      final maxWidth = constraints.maxWidth;

      if (_measure(full) <= maxWidth) {
        return Text(full, style: _style);
      }

      // Width budget for the txid (excluding suffix and ellipsis)
      final ellipsisW = _measure('…');
      final suffixW = suffix.isNotEmpty ? _measure(suffix) : 0.0;
      final budget = maxWidth - ellipsisW - suffixW;

      if (budget <= 0) {
        return Text('…$suffix', style: _style);
      }

      // Monospace: measure one representative char to avoid O(n) layouts.
      final charW = _measure('a');
      if (charW <= 0) return Text(full, style: _style);

      final totalChars = txid.length;
      final fitChars = (budget / charW).floor().clamp(2, totalChars);
      final frontChars = (fitChars / 2).ceil();
      final backChars = fitChars - frontChars;

      final truncated =
          '${txid.substring(0, frontChars)}…'
          '${txid.substring(totalChars - backChars)}$suffix';

      return Text(truncated, style: _style);
    });
  }
}
