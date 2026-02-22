import 'package:flutter/material.dart';

/// A colored badge displaying a master fingerprint or custom key label.
class MfpBadge extends StatelessWidget {
  final String label;
  final Color color;
  /// Use 0.5 for raw MFP labels (hex chars), 0.0 for custom names.
  final double letterSpacing;

  const MfpBadge({
    super.key,
    required this.label,
    required this.color,
    this.letterSpacing = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(64), width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(210),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }
}
