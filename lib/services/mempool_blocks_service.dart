import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:deadbolt/errors.dart' show sanitizeForLog;
import 'package:deadbolt/services/tor_http_client.dart';
import 'package:http/http.dart' as http;

class FeePresets {
  final double economy; // hourFee — ~1 hora
  final double normal; // halfHourFee — ~30 min
  final double priority; // fastestFee — ~10 min

  const FeePresets({
    required this.economy,
    required this.normal,
    required this.priority,
  });
}

/// Fee data for one projected mempool block (not yet mined).
/// index 0 = next block to be mined, index 1 = the one after, etc.
class ProjectedBlock {
  /// Minimum fee rate (sat/vB) — feeRange[0].
  final double minFee;

  /// Median fee rate (sat/vB).
  final double medianFee;

  /// ~25th-percentile fee rate (sat/vB).
  final double p25Fee;

  /// ~75th-percentile fee rate (sat/vB) — feeRange[75% index].
  final double p75Fee;

  const ProjectedBlock({
    required this.minFee,
    required this.medianFee,
    required this.p25Fee,
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

  /// Derives fee presets from block data using:
  ///   priority = median of block 0 (next)
  ///   normal   = median of block 1 (next+1)
  ///   economy  = median of block 2 (next+2)
  /// [minFee] is used as a floor for all values and as fallback when
  /// a block is unavailable.
  FeePresets presetsFromSnapshot(double minFee) {
    double floor(double v) => max(v, minFee);

    final b0 = blocks.isNotEmpty ? blocks[0] : null;
    final b1 = blocks.length > 1 ? blocks[1] : null;
    final b2 = blocks.length > 2 ? blocks[2] : null;

    final priority = floor(b0?.medianFee ?? minFee);
    final normal = floor(b1?.medianFee ?? b0?.medianFee ?? minFee);
    final economy = floor(b2?.medianFee ?? b1?.medianFee ?? minFee);

    return FeePresets(economy: economy, normal: normal, priority: priority);
  }
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
          double? p25;
          double? p75;
          if (feeRange != null && feeRange.isNotEmpty) {
            final p25idx = ((feeRange.length - 1) * 0.25).round();
            p25 = (feeRange[p25idx] as num?)?.toDouble();
            final p75idx = ((feeRange.length - 1) * 0.75).round();
            p75 = (feeRange[p75idx] as num?)?.toDouble();
          }
          if (median == null) continue;
          blocks.add(ProjectedBlock(
            minFee: min ?? median,
            medianFee: median,
            p25Fee: p25 ?? median,
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
    } catch (e, st) {
      debugPrint('ERROR in MempoolBlocksService.getMempoolSnapshot: ${sanitizeForLog(e.toString())}\n${sanitizeForLog(st.toString())}');
      return null;
    }
  }

  static http.Client _buildClient(String? socksAddr) =>
      buildTorAwareClient(socksAddr);
}
