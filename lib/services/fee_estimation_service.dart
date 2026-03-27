import 'dart:convert';

import 'package:http/http.dart' as http;

class FeePresets {
  final double economy;   // hourFee       — ~1 hora
  final double normal;    // halfHourFee   — ~30 min
  final double priority;  // fastestFee    — ~10 min

  const FeePresets({
    required this.economy,
    required this.normal,
    required this.priority,
  });
}

class FeeEstimationService {
  static final Map<String, ({FeePresets presets, DateTime cachedAt})> _cache = {};
  static const _cacheTtl = Duration(minutes: 5);

  /// Returns fee presets from [explorerBaseUrl]/api/v1/fees/recommended.
  /// Returns null if the URL is empty, the request fails, or fields are missing.
  static Future<FeePresets?> getPresets(String explorerBaseUrl) async {
    if (explorerBaseUrl.isEmpty) return null;

    final cached = _cache[explorerBaseUrl];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _cacheTtl) {
      return cached.presets;
    }

    try {
      final uri = Uri.parse('$explorerBaseUrl/api/v1/fees/recommended');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final fastest = (data['fastestFee'] as num?)?.toDouble();
      final halfHour = (data['halfHourFee'] as num?)?.toDouble();
      final hour = (data['hourFee'] as num?)?.toDouble();
      if (fastest == null || halfHour == null || hour == null) return null;
      final presets = FeePresets(
        economy: hour,
        normal: halfHour,
        priority: fastest,
      );
      _cache[explorerBaseUrl] = (presets: presets, cachedAt: DateTime.now());
      return presets;
    } catch (_) {
      return null;
    }
  }
}
