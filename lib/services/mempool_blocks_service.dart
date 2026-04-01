import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks.dart';

/// Fee data for one projected mempool block (not yet mined).
/// index 0 = next block to be mined, index 1 = the one after, etc.
class ProjectedBlock {
  /// Minimum fee rate (sat/vB) — feeRange[0].
  final double minFee;

  /// Median fee rate (sat/vB).
  final double medianFee;

  /// ~75th-percentile fee rate (sat/vB) — feeRange[75% index].
  final double p75Fee;

  const ProjectedBlock({
    required this.minFee,
    required this.medianFee,
    required this.p75Fee,
  });
}

/// Snapshot of projected mempool blocks from /api/v1/fees/mempool-blocks.
/// Up to [MempoolBlocksService.maxBlocks] entries, index 0 = next block.
class MempoolBlocksSnapshot {
  final List<ProjectedBlock> blocks;

  const MempoolBlocksSnapshot({required this.blocks});

  /// Min fee of the next block to be mined, or null when unknown.
  double? get nextBlockMinFee =>
      blocks.isNotEmpty ? blocks.first.minFee : null;
}

class MempoolBlocksService {
  static const maxBlocks = 6;
  static const _cacheTtl = Duration(seconds: 5);

  static final Map<String, ({MempoolBlocksSnapshot snapshot, DateTime cachedAt})>
      _cache = {};

  /// Fetches projected mempool blocks from [explorerBaseUrl]/api/v1/fees/mempool-blocks.
  /// Returns up to [maxBlocks] entries ordered next → further.
  /// Pass [torSocksAddr] (e.g. "127.0.0.1:9150") to route via SOCKS5 when Tor is active.
  /// Returns null on any error or empty response.
  static Future<MempoolBlocksSnapshot?> getSnapshot(
    String explorerBaseUrl, {
    String? torSocksAddr,
  }) async {
    if (explorerBaseUrl.isEmpty) return null;

    final cached = _cache[explorerBaseUrl];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _cacheTtl) {
      return cached.snapshot;
    }

    try {
      final client = _buildClient(torSocksAddr);
      try {
        final uri = Uri.parse('$explorerBaseUrl/api/v1/fees/mempool-blocks');
        final resp =
            await client.get(uri).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) return null;

        final list = jsonDecode(resp.body);
        if (list is! List || list.isEmpty) return null;

        final blocks = <ProjectedBlock>[];
        for (final item in list.take(maxBlocks)) {
          final feeRange = item['feeRange'] as List<dynamic>?;
          final median = (item['medianFee'] as num?)?.toDouble();
          final min =
              (feeRange?.isNotEmpty == true ? feeRange![0] as num? : null)
                  ?.toDouble();
          double? p75;
          if (feeRange != null && feeRange.isNotEmpty) {
            final idx = ((feeRange.length - 1) * 0.75).round();
            p75 = (feeRange[idx] as num?)?.toDouble();
          }
          if (median == null) continue;
          blocks.add(ProjectedBlock(
            minFee: min ?? median,
            medianFee: median,
            p75Fee: p75 ?? median,
          ));
        }

        if (blocks.isEmpty) return null;
        final snapshot = MempoolBlocksSnapshot(blocks: blocks);
        _cache[explorerBaseUrl] =
            (snapshot: snapshot, cachedAt: DateTime.now());
        return snapshot;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  static http.Client _buildClient(String? socksAddr) {
    if (socksAddr == null) return http.Client();
    final parts = socksAddr.split(':');
    if (parts.length != 2) return http.Client();
    final host = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null) return http.Client();

    final httpClient = HttpClient();
    SocksTCPClient.assignToHttpClient(httpClient, [
      ProxySettings(InternetAddress(host), port),
    ]);
    return IOClient(httpClient);
  }
}
