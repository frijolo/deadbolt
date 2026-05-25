// Banner that nudges Android users to exclude Deadbolt from battery
// optimization. Shown above the TxPlanningScreen body while a plan is
// actively running (auto-broadcast pending). Hidden on:
//   - non-Android platforms,
//   - devices that already exempt the app,
//   - explicit per-session dismissal.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/battery_optimization_service.dart';

class BatteryOptimizationBanner extends StatefulWidget {
  const BatteryOptimizationBanner({super.key});

  @override
  State<BatteryOptimizationBanner> createState() =>
      _BatteryOptimizationBannerState();
}

class _BatteryOptimizationBannerState extends State<BatteryOptimizationBanner>
    with WidgetsBindingObserver {
  final _service = BatteryOptimizationService();
  bool? _exempt;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
      _refresh();
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final ok = await _service.isIgnored();
    if (!mounted) return;
    setState(() => _exempt = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    if (_exempt == null || _exempt!) return const SizedBox.shrink();
    if (_dismissed) return const SizedBox.shrink();

    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.battery_saver, color: cs.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.batteryOptBannerTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.batteryOptBannerBody,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _dismissed = true),
                child: Text(l10n.batteryOptBannerDismiss),
              ),
              const SizedBox(width: 4),
              FilledButton.tonal(
                onPressed: () async {
                  await _service.openSettings();
                  // Lifecycle observer will re-check on resume.
                },
                child: Text(l10n.batteryOptBannerAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
