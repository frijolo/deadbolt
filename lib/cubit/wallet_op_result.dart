import 'package:deadbolt/errors.dart' show formatRustError;

/// Outcome of a wallet operation that crosses the [WalletOpener] / [LoadedWallet]
/// seam. Replaces the older pattern of `Result` classes with nullable
/// `errorMessage` fields. Callers pattern-match exhaustively.
sealed class WalletOpResult<T> {
  const WalletOpResult();
}

class Ok<T> extends WalletOpResult<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends WalletOpResult<T> {
  final String message;
  const Err(this.message);
}

/// Run [body], wrapping any thrown error into [Err] with a message produced by
/// [formatRustError]. The optional [tag] is prepended to the message to aid
/// log correlation.
Future<WalletOpResult<T>> guardAsync<T>(
  Future<T> Function() body, {
  String? tag,
}) async {
  try {
    return Ok(await body());
  } catch (e) {
    final msg = formatRustError(e);
    return Err(tag != null ? '$tag: $msg' : msg);
  }
}

/// Synchronous variant of [guardAsync].
WalletOpResult<T> guardSync<T>(
  T Function() body, {
  String? tag,
}) {
  try {
    return Ok(body());
  } catch (e) {
    final msg = formatRustError(e);
    return Err(tag != null ? '$tag: $msg' : msg);
  }
}
