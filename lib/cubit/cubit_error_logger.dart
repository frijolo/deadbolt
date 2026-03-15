import 'package:flutter/foundation.dart';

/// Mixin that provides a structured error logger for Cubits.
mixin CubitErrorLogger {
  void logError(String context, Object error, StackTrace stackTrace) {
    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('ERROR in $context:');
    debugPrint('$error');
    debugPrint('Stack trace:');
    debugPrint('$stackTrace');
    debugPrint('════════════════════════════════════════════════════════════');
  }
}
