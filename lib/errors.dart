import 'dart:convert';

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
  if (errorStr.contains('Electrum server error:')) {
    errorStr = _extractElectrumMessage(errorStr) ?? errorStr;
  }
  return errorStr.trim();
}

// Extracts the human-readable message from an Electrum JSON error payload.
// Example input: 'Electrum server error: {"code":1,"message":"bad-txns-inputs-missingorspent"}'
// The message value may itself contain escaped JSON (e.g. sendrawtransaction errors), so
// we parse the full JSON object rather than using a regex on the raw string.
String? _extractElectrumMessage(String error) {
  final jsonStart = error.indexOf('{');
  if (jsonStart == -1) return null;
  try {
    final prefix = error.substring(0, jsonStart).trim();
    final parsed = json.decode(error.substring(jsonStart)) as Map<String, dynamic>;
    final message = (parsed['message'] as String?)?.trim();
    if (message == null) return null;
    return prefix.isEmpty ? message : '$prefix $message';
  } catch (_) {
    return null;
  }
}
