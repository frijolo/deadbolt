String formatRustError(Object e) {
  String errorStr = e.toString();
  errorStr = errorStr.replaceFirst('AnyhowException(', '');
  if (errorStr.contains('Stack backtrace:')) {
    errorStr = errorStr.split('Stack backtrace:')[0];
  }
  return errorStr.trim();
}
