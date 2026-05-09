import 'package:flutter/material.dart';
import 'package:deadbolt/config/constants.dart' show kMonospaceFontFamily;
import 'package:deadbolt/theme/app_theme.dart';

/// Renders a Bitcoin address, txid, or xpub with groups of 4 characters alternating
/// between the theme's primary color and a dim foreground, for easy visual
/// verification.
///
/// When [monospace] is true, a monospace font is applied (use for xpubs and key data).
///
/// When [truncate] is true, the text is cut from the middle keeping complete
/// 4-character groups on both sides (responsive to available width).
///
/// [suffix] is appended verbatim in faint color after the main text (e.g. ':0'
/// for outpoints). Its width is reserved before truncation so it is always
/// fully visible.
class ColoredGroupText extends StatelessWidget {
  final String text;
  final double? fontSize;
  final bool truncate;
  final String suffix;
  final bool monospace;

  const ColoredGroupText({
    super.key,
    required this.text,
    this.fontSize,
    this.truncate = false,
    this.suffix = '',
    this.monospace = false,
  });

  TextStyle _baseStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
    final sized = fontSize != null ? base.copyWith(fontSize: fontSize) : base;
    return monospace ? sized.copyWith(fontFamily: kMonospaceFontFamily) : sized;
  }

  List<String> _groups() {
    final result = <String>[];
    for (var i = 0; i < text.length; i += 4) {
      result.add(text.substring(i, (i + 4).clamp(0, text.length)));
    }
    return result;
  }

  double _measure(String s, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dim = theme.colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh);
    final faint = theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive);
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
          if (suffix.isNotEmpty)
            TextSpan(text: suffix, style: TextStyle(color: faint)),
        ],
      ),
    );
  }

  Widget _buildMiddleTruncated(BuildContext context, double maxWidth) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dim = theme.colorScheme.onSurface.withAlpha(AppAlpha.mediumHigh);
    final faint = theme.colorScheme.onSurface.withAlpha(AppAlpha.inactive);
    final style = _baseStyle(context);
    final groups = _groups();

    if (groups.length <= 2) return _buildFull(context);

    // Reserve space for the suffix before computing truncation budget.
    final suffixW = suffix.isNotEmpty ? _measure(suffix, style) : 0.0;
    final budget = maxWidth - suffixW;

    // Precompute widths for each group and for the ellipsis.
    final widths = groups.map((g) => _measure(g, style)).toList();
    final ellipsisW = _measure('…', style);

    // If the full text fits, show it without truncation.
    final totalW = widths.fold(0.0, (a, b) => a + b);
    if (totalW <= budget) return _buildFull(context);

    // Precompute prefix and back-group cumulative widths.
    final prefixW = List<double>.filled(groups.length, 0);
    final backW = List<double>.filled(groups.length, 0);
    for (var i = 0; i < groups.length; i++) {
      prefixW[i] = (i == 0 ? 0 : prefixW[i - 1]) + widths[i];
    }
    for (var i = groups.length - 1; i >= 0; i--) {
      backW[i] = (i == groups.length - 1 ? 0 : backW[i + 1]) + widths[i];
    }

    // Find the maximum number of groups (front + back, with ellipsis) that fit,
    // favouring an equal split (ceil on the front side).
    var bestFront = 1;
    var bestBack = 1;
    for (var total = groups.length - 1; total >= 2; total--) {
      final front = (total / 2).ceil();
      final back = total - front;
      final w = prefixW[front - 1] + ellipsisW + backW[groups.length - back];
      if (w <= budget) {
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
          TextSpan(text: '…', style: TextStyle(color: faint)),
          for (var i = 0; i < backGroups.length; i++)
            TextSpan(
              text: backGroups[i],
              // preserve colour parity from original group index
              style: TextStyle(
                color: (backStart + i).isEven ? dim : primary,
              ),
            ),
          if (suffix.isNotEmpty)
            TextSpan(text: suffix, style: TextStyle(color: faint)),
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
