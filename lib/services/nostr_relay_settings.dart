import 'package:shared_preferences/shared_preferences.dart';

/// Persists the list of Nostr relay URLs used for descriptor backups.
///
/// Relays are stored in SharedPreferences under a single string-list key.
/// When no relays have been configured, a set of well-known public relays is
/// returned as defaults.
class NostrRelaySettings {
  static const _kKey = 'nostrRelayUrls';

  static const defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
  ];

  Future<List<String>> loadRelays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kKey) ?? defaultRelays;
  }

  Future<void> saveRelays(List<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kKey, urls);
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
}
