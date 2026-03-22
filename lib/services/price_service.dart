import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

enum PriceProviderType { coinGecko, mempoolSpace }

// ---------------------------------------------------------------------------
// Supported fiat currencies
// ---------------------------------------------------------------------------

/// Fiat currencies supported by CoinGecko (USD/EUR first, rest alphabetical).
const kCoinGeckoCurrencies = [
  'usd', 'eur',
  'aed', 'ars', 'aud', 'bdt', 'bhd', 'bmd', 'brl', 'cad', 'chf',
  'clp', 'cny', 'czk', 'dkk', 'gbp', 'gel', 'hkd', 'huf', 'idr',
  'ils', 'inr', 'jpy', 'krw', 'kwd', 'lkr', 'mmk', 'mxn', 'myr',
  'ngn', 'nok', 'nzd', 'php', 'pkr', 'pln', 'rub', 'sar', 'sek',
  'sgd', 'thb', 'try', 'twd', 'uah', 'vnd', 'zar',
];

/// Fiat currencies supported by Mempool.space (USD/EUR first, rest alphabetical).
const kMempoolCurrencies = ['usd', 'eur', 'aud', 'cad', 'chf', 'gbp', 'jpy'];

List<String> currenciesForProvider(PriceProviderType provider) =>
    provider == PriceProviderType.coinGecko
        ? kCoinGeckoCurrencies
        : kMempoolCurrencies;

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

abstract class PriceProvider {
  PriceProviderType get type;

  /// Return the BTC price in [currency] at [time].
  /// Returns null when the provider doesn't have data for that time/currency.
  Future<double?> getBtcPrice(String currency, DateTime time);
}

// ---------------------------------------------------------------------------
// CoinGecko implementation
// ---------------------------------------------------------------------------

class CoinGeckoPriceProvider implements PriceProvider {
  static const _base = 'https://api.coingecko.com/api/v3';
  static const _currentThreshold = Duration(hours: 1);
  static const _maxCacheEntries = 365;
  static final _dateFormat = DateFormat('dd-MM-yyyy');

  // Cache: "dd-MM-yyyy" -> currency -> price (capped at _maxCacheEntries)
  final Map<String, Map<String, double>> _dailyCache = {};

  // Current price cache (refreshed at most every 5 minutes)
  Map<String, double>? _currentCache;
  DateTime? _currentCachedAt;

  @override
  PriceProviderType get type => PriceProviderType.coinGecko;

  @override
  Future<double?> getBtcPrice(String currency, DateTime time) async {
    final age = DateTime.now().difference(time);
    return age < _currentThreshold
        ? _fetchCurrent(currency)
        : _fetchDaily(currency, time);
  }

  Future<double?> _fetchCurrent(String currency) async {
    final cur = currency.toLowerCase();
    final cacheAge = _currentCachedAt != null
        ? DateTime.now().difference(_currentCachedAt!)
        : null;
    if (cacheAge != null &&
        cacheAge < const Duration(minutes: 5) &&
        _currentCache != null &&
        _currentCache!.containsKey(cur)) {
      return _currentCache![cur];
    }
    final uri = Uri.parse('$_base/simple/price').replace(queryParameters: {
      'ids': 'bitcoin',
      'vs_currencies': cur,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final price = (data['bitcoin']?[cur] as num?)?.toDouble();
    if (price != null) {
      _currentCache ??= {};
      _currentCache![cur] = price;
      _currentCachedAt = DateTime.now();
    }
    return price;
  }

  Future<double?> _fetchDaily(String currency, DateTime date) async {
    final cur = currency.toLowerCase();
    final dateKey = _dateFormat.format(date.toUtc());
    if (_dailyCache[dateKey]?[cur] != null) return _dailyCache[dateKey]![cur];
    final uri =
        Uri.parse('$_base/coins/bitcoin/history').replace(queryParameters: {
      'date': dateKey,
      'localization': 'false',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final prices =
        (data['market_data']?['current_price'] as Map<String, dynamic>?);
    final price = (prices?[cur] as num?)?.toDouble();
    if (price != null) {
      if (_dailyCache.length >= _maxCacheEntries) {
        _dailyCache.remove(_dailyCache.keys.first);
      }
      _dailyCache[dateKey] ??= {};
      _dailyCache[dateKey]![cur] = price;
    }
    return price;
  }
}

// ---------------------------------------------------------------------------
// Mempool.space implementation
// ---------------------------------------------------------------------------

class MempoolSpacePriceProvider implements PriceProvider {
  static const _base = 'https://mempool.space/api/v1';

  @override
  PriceProviderType get type => PriceProviderType.mempoolSpace;

  @override
  Future<double?> getBtcPrice(String currency, DateTime time) async {
    final cur = currency.toUpperCase();
    final ts = (time.millisecondsSinceEpoch / 1000).truncate();
    final uri =
        Uri.parse('$_base/historical-price').replace(queryParameters: {
      'currency': cur,
      'timestamp': ts.toString(),
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final prices = data['prices'] as List<dynamic>?;
    if (prices == null || prices.isEmpty) return null;
    return (prices.last[cur] as num?)?.toDouble();
  }
}

// ---------------------------------------------------------------------------
// PriceService facade
// ---------------------------------------------------------------------------

class PriceService {
  PriceProvider _provider;

  PriceService(PriceProviderType type) : _provider = _makeProvider(type);

  PriceProviderType get providerType => _provider.type;

  static PriceProvider _makeProvider(PriceProviderType type) => switch (type) {
        PriceProviderType.coinGecko => CoinGeckoPriceProvider(),
        PriceProviderType.mempoolSpace => MempoolSpacePriceProvider(),
      };

  void setProvider(PriceProviderType type) {
    if (_provider.type == type) return;
    _provider = _makeProvider(type);
  }

  Future<double?> getBtcPrice(String currency, DateTime time) =>
      _provider.getBtcPrice(currency, time);
}
