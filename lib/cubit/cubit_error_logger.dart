import 'package:flutter/foundation.dart';

import 'package:deadbolt/errors.dart' show sanitizeForLog;

/// Mixin that provides a structured error logger for Cubits.
mixin CubitErrorLogger {
  void logError(String context, Object error, StackTrace stackTrace) {
    debugPrint('════════════════════════════════════════════════════════════');
    debugPrint('ERROR in $context:');
    debugPrint(sanitizeForLog(error.toString()));
    debugPrint('Stack trace:');
    debugPrint(sanitizeForLog(stackTrace.toString()));
    debugPrint('════════════════════════════════════════════════════════════');
  }
}
