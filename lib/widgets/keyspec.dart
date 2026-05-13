// Shared keyspec types and parsing utilities.
//
// Kept separate from add_key_dialog.dart so sibling widgets
// (mnemonic_confirm_step.dart, generate_mnemonic_sheet.dart, etc.) can
// depend on these types without importing the consumer dialog.

/// Pattern for parsing keyspec format: [mfp/path]xpub
final kKeyspecPattern = RegExp(r'^\[([0-9a-fA-F]{8})/([^\]]+)\](.+)$');

/// Result returned by the add-key flow.
///
/// [keyspec] is always populated; [mnemonic]/[passphrase]/[xprv] are set only
/// when the user entered the key via seed — allowing callers to store a hot key.
typedef KeyspecResult = ({
  String keyspec,
  String? mnemonic,
  String? passphrase,
  String? xprv,
});

final _kTokenSeparator = RegExp(r'[\s,;]+');
final _kHex8 = RegExp(r'^[0-9a-fA-F]{8}$');
final _kXpubPrefix =
    RegExp(r'^(xpub|tpub|ypub|zpub|upub|vpub|Ypub|Zpub|Upub|Vpub)');
final _kPathLike = RegExp(r"^(m/)?[0-9]+['hH]?(/[0-9]+['hH]?)*$");

/// Loose-token parser for the manual entry dialog.
///
/// Tries the keyspec format first; on miss splits the input by whitespace /
/// commas / semicolons and classifies each of the 3 expected tokens by
/// content: 8-hex (MFP), xpub-prefix (extended key), or path-like.
({String mfp, String path, String xpub})? parseManualKeyspec(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final m = kKeyspecPattern.firstMatch(trimmed);
  if (m != null) {
    return (mfp: m.group(1)!, path: m.group(2)!, xpub: m.group(3)!);
  }

  final tokens = trimmed
      .split(_kTokenSeparator)
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length != 3) return null;

  String? mfp, path, xpub;
  for (final t in tokens) {
    if (_kXpubPrefix.hasMatch(t)) {
      if (xpub != null) return null;
      xpub = t;
    } else if (_kHex8.hasMatch(t)) {
      if (mfp != null) return null;
      mfp = t;
    } else if (_kPathLike.hasMatch(t)) {
      if (path != null) return null;
      path = t;
    } else {
      return null;
    }
  }
  if (mfp == null || path == null || xpub == null) return null;
  return (mfp: mfp, path: path, xpub: xpub);
}
