import 'package:shared_preferences/shared_preferences.dart';

import 'package:deadbolt/src/rust/api/wallet/nostr_backup.dart' as rust_nostr;

/// Persists the list of Nostr relay URLs and connection parameters used for
/// descriptor backups.
///
/// Relay URLs are stored in SharedPreferences under a single string-list key.
/// When no relays have been configured, a set of well-known public relays is
/// returned as defaults.
///
/// Connection parameters (timeout, max attempts) are also stored here and
/// applied to Rust via [applyToRust], which must be called once on app start
/// and after every settings change.
class NostrRelaySettings {
  static const _kRelaysKey = 'nostrRelayUrls';
  static const _kTimeoutKey = 'nostrTimeoutSecs';
  static const _kMaxAttemptsKey = 'nostrMaxAttempts';

  static const defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
  ];

  static const defaultTimeoutSecs = 15;
  static const defaultMaxAttempts = 3;

  // ── Relay URLs ─────────────────────────────────────────────────────────────

  Future<List<String>> loadRelays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kRelaysKey) ?? defaultRelays;
  }

  Future<void> saveRelays(List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRelaysKey, urls);
  }

  Future<void> addRelay(String url) async {
    final current = await loadRelays();
    if (!current.contains(url)) {
      await saveRelays([...current, url]);
    }
  }

  Future<void> removeRelay(String url) async {
    final current = await loadRelays();
    await saveRelays(current.where((u) => u != url).toList());
  }

  // ── Connection parameters ──────────────────────────────────────────────────

  Future<int> loadTimeoutSecs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kTimeoutKey) ?? defaultTimeoutSecs;
  }

  Future<void> saveTimeoutSecs(int secs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTimeoutKey, secs.clamp(5, 120));
  }

  Future<int> loadMaxAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kMaxAttemptsKey) ?? defaultMaxAttempts;
  }

  Future<void> saveMaxAttempts(int n) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxAttemptsKey, n.clamp(1, 10));
  }

  /// Read timeout and max-attempts from storage and push them to Rust.
  ///
  /// Call once on app start and after any change to these settings.
  Future<void> applyToRust() async {
    final timeout = await loadTimeoutSecs();
    final maxAttempts = await loadMaxAttempts();
    await rust_nostr.setNostrRelayConfig(
      timeoutSecs: BigInt.from(timeout),
      maxAttempts: maxAttempts,
    );
  }
}
