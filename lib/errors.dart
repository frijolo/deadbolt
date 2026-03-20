String formatRustError(Object e) {
  String errorStr = e.toString();
  // Strip AnyhowException(...) wrapper — remove prefix and matching closing paren.
  const prefix = 'AnyhowException(';
  if (errorStr.startsWith(prefix) && errorStr.endsWith(')')) {
    errorStr = errorStr.substring(prefix.length, errorStr.length - 1);
  } else {
    errorStr = errorStr.replaceFirst(prefix, '');
  }
  if (errorStr.contains('Stack backtrace:')) {
    errorStr = errorStr.split('Stack backtrace:')[0];
  }
  return errorStr.trim();
}
