/// Sanitises a string for safe use as a file name base.
///
/// - Strips leading/trailing dots and whitespace.
/// - Replaces any character that is NOT `[A-Za-z0-9_-]` with `_`.
/// - Collapses consecutive underscores into one.
/// - Ensures the result does not start with `_` or `-`.
///
/// This unifies the divergent regex patterns found in [export_flow.dart]
/// (`[^\w\-]` vs `[^a-zA-Z0-9_-]`) that produced inconsistent file names
/// for wallets with non-ASCII characters in their names.
String safeFileBase(String name) {
  var s = name.trim();
  s = s.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  s = s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  s = s.replaceAll(RegExp(r'^[_-]'), '');
  return s;
}
