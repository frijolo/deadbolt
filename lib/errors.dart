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
    errorStr = _extractElectrumMessage(errorStr);
  }
  return errorStr.trim();
}

// Extracts the human-readable message from an Electrum JSON error payload.
// Example input: 'Electrum server error: {"code":1,"message":"bad-txns-inputs-missingorspent"}'
String _extractElectrumMessage(String error) {
  final jsonMatch = RegExp(r'\{[^}]*"message"\s*:\s*"([^"]+)"[^}]*\}').firstMatch(error);
  if (jsonMatch == null) return error;
  final prefix = error.substring(0, jsonMatch.start).trim();
  final rawMessage = jsonMatch.group(1)!;
  final message = (json.decode('"$rawMessage"') as String).trim();
  return prefix.isEmpty ? message : '$prefix $message';
}
