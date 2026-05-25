// Thin wrapper around the `deadbolt/battery` MethodChannel (Android-only).
// Used by the TxPlanningScreen banner to nudge the user into excluding
// Deadbolt from battery optimization, which materially improves the
// reliability of the background auto-broadcast scheduler.

import 'dart:io';

import 'package:flutter/services.dart';

class BatteryOptimizationService {
  static const _channel = MethodChannel('deadbolt/battery');

  /// True when Android already exempts Deadbolt from battery optimizations.
  /// Always `true` on non-Android platforms (no-op).
  Future<bool> isIgnored() async {
    if (!Platform.isAndroid) return true;
    try {
      final res =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system battery-optimization settings screen. Returns `true`
  /// if an intent was launched, `false` if neither the dedicated screen nor
  /// the fallback app-details screen was available.
  Future<bool> openSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final res =
          await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }
}
