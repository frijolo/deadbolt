import 'package:flutter/material.dart';
import 'package:deadbolt/services/fee_estimation_service.dart';

/// Shared fee-preset segmented button used by create-tx and sweep-WIF screens.
Widget buildFeePresetsSegments(
  FeePresets? presets,
  int? selectedIndex,
  void Function(int) onSelect,
) {
  if (presets == null) return const SizedBox.shrink();
  final selected = selectedIndex != null ? {selectedIndex} : <int>{};
  return SegmentedButton<int>(
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    showSelectedIcon: false,
    segments: [
      ButtonSegment(
        value: 0,
        icon: const Icon(Icons.hourglass_bottom, size: 14),
        label: Text('${presets.economy.toStringAsFixed(0)} sat/vB'),
      ),
      ButtonSegment(
        value: 1,
        icon: const Icon(Icons.schedule, size: 14),
        label: Text('${presets.normal.toStringAsFixed(0)} sat/vB'),
      ),
      ButtonSegment(
        value: 2,
        icon: const Icon(Icons.bolt, size: 14),
        label: Text('${presets.priority.toStringAsFixed(0)} sat/vB'),
      ),
    ],
    selected: selected,
    emptySelectionAllowed: true,
    onSelectionChanged: (Set<int> s) {
      if (s.isNotEmpty) onSelect(s.first);
    },
  );
}
