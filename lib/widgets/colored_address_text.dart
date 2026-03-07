import 'package:flutter/material.dart';

/// Renders a Bitcoin address with groups of 4 characters alternating between
/// the theme's primary color and a dim foreground, for easy visual verification.
/// Uses the app's default font (no monospace override).
///
/// When [truncate] is true, the address is cut from the middle keeping complete
/// 4-character groups on both sides (responsive to available width).
class ColoredAddressText extends StatelessWidget {
  final String address;
  final double? fontSize;
  final bool truncate;

  const ColoredAddressText({
    super.key,
    required this.address,
    this.fontSize,
    this.truncate = false,
  });

  TextStyle _baseStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
    return fontSize != null ? base.copyWith(fontSize: fontSize) : base;
  }

  /// Splits [address] into complete 4-character groups.
  List<String> _groups() {
    final result = <String>[];
    for (var i = 0; i < address.length; i += 4) {
      result.add(address.substring(i, (i + 4).clamp(0, address.length)));
    }
    return result;
  }

  double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dim = theme.colorScheme.onSurface.withAlpha(180);
    final groups = _groups();

    return RichText(
      text: TextSpan(
        style: _baseStyle(context),
        children: [
          for (var i = 0; i < groups.length; i++)
            TextSpan(
              text: groups[i],
              style: TextStyle(color: i.isEven ? dim : primary),
            ),
        ],
      ),
    );
  }

  Widget _buildMiddleTruncated(BuildContext context, double maxWidth) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dim = theme.colorScheme.onSurface.withAlpha(180);
    final style = _baseStyle(context);
    final groups = _groups();

    if (groups.length <= 2) return _buildFull(context);

    // Precompute widths for each group and for the ellipsis.
    final widths = groups.map((g) => _measure(g, style)).toList();
    final ellipsisW = _measure('…', style);

    // If the full address fits, show it without truncation.
    final totalW = widths.fold(0.0, (a, b) => a + b);
    if (totalW <= maxWidth) return _buildFull(context);

    // Precompute prefix and suffix cumulative widths.
    final prefixW = List<double>.filled(groups.length, 0);
    final suffixW = List<double>.filled(groups.length, 0);
    for (var i = 0; i < groups.length; i++) {
      prefixW[i] = (i == 0 ? 0 : prefixW[i - 1]) + widths[i];
    }
    for (var i = groups.length - 1; i >= 0; i--) {
      suffixW[i] = (i == groups.length - 1 ? 0 : suffixW[i + 1]) + widths[i];
    }

    // Find the maximum number of groups (front + back, with ellipsis) that fit,
    // favouring an equal split (ceil on the front side).
    var bestFront = 1;
    var bestBack = 1;
    for (var total = groups.length - 1; total >= 2; total--) {
      final front = (total / 2).ceil();
      final back = total - front;
      final w = prefixW[front - 1] + ellipsisW + suffixW[groups.length - back];
      if (w <= maxWidth) {
        bestFront = front;
        bestBack = back;
        break;
      }
    }

    final frontGroups = groups.sublist(0, bestFront);
    final backStart = groups.length - bestBack;
    final backGroups = groups.sublist(backStart);

    return RichText(
      text: TextSpan(
        style: style,
        children: [
          for (var i = 0; i < frontGroups.length; i++)
            TextSpan(
              text: frontGroups[i],
              style: TextStyle(color: i.isEven ? dim : primary),
            ),
          TextSpan(
            text: '…',
            style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120)),
          ),
          for (var i = 0; i < backGroups.length; i++)
            TextSpan(
              text: backGroups[i],
              // preserve colour parity from original group index
              style: TextStyle(
                color: (backStart + i).isEven ? dim : primary,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!truncate) return _buildFull(context);
    return LayoutBuilder(
      builder: (ctx, constraints) =>
          _buildMiddleTruncated(ctx, constraints.maxWidth),
    );
  }
}
