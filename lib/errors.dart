import 'dart:convert';

// Patterns that may carry key material in error messages from Rust.
final _sensitivePatterns = [
  // Extended keys: xpub/xprv/ypub/yprv/zpub/zprv and BIP32 test-net variants.
  RegExp(r'[xyztuvXYZTUV]p(?:ub|rv)[a-km-zA-HJ-NP-Z1-9]{100,115}'),
  // Bech32 / Bech32m addresses (mainnet, testnet, regtest).
  RegExp(r'(?:bc1|tb1|bcrt1)[a-z0-9]{25,90}'),
];

/// Redacts key material (extended keys, bech32 addresses) from [s] so the
/// result is safe to pass to [debugPrint].
String sanitizeForLog(String s) {
  var result = s;
  for (final pattern in _sensitivePatterns) {
    result = result.replaceAll(pattern, '[REDACTED]');
  }
  return result;
}

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
