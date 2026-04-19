import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show validateMnemonic;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/screens/qr_scanner_screen.dart';
import 'package:deadbolt/utils/seed_qr.dart'
    show encodeSeedQrStandard, encodeSeedQrCompact;
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/mfp_badge.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Full-screen mnemonic export: words, Standard/Compact SeedQR, and a
/// segment-by-segment paper transcription guide.
///
/// [mfp] is the stored master fingerprint (derived from mnemonic+passphrase).
/// [network] is used to derive the no-passphrase fingerprint for comparison.
class SeedExportScreen extends StatefulWidget {
  final String mnemonic;
  final String mfp;
  final APINetwork network;

  const SeedExportScreen({
    super.key,
    required this.mnemonic,
    required this.mfp,
    required this.network,
  });

  @override
  State<SeedExportScreen> createState() => _SeedExportScreenState();
}

class _SeedExportScreenState extends State<SeedExportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _hasPassphrase = false;
  String _mfpNoPassphrase = '';
  late final ValueNotifier<_QrFormat> _formatNotifier;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _formatNotifier = ValueNotifier(_QrFormat.compact);
    _detectPassphrase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _formatNotifier.dispose();
    super.dispose();
  }

  Future<void> _detectPassphrase() async {
    try {
      final info = await validateMnemonic(
        mnemonic: widget.mnemonic,
        passphrase: '',
        network: widget.network,
      );
      if (!mounted) return;
      setState(() {
        _mfpNoPassphrase = info.mfp;
        _hasPassphrase = info.mfp != widget.mfp;
      });
    } catch (_) {
      // Passphrase info is advisory only — ignore errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.seedExportTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.seedExportTabWords),
            Tab(text: l10n.seedExportTabQr),
            Tab(text: l10n.seedExportTabGuide),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            _WordsTab(
              mnemonic: widget.mnemonic,
              mfp: widget.mfp,
              hasPassphrase: _hasPassphrase,
              mfpNoPassphrase: _mfpNoPassphrase,
            ),
            _QrTab(
              mnemonic: widget.mnemonic,
              hasPassphrase: _hasPassphrase,
              formatNotifier: _formatNotifier,
            ),
            _GuideTab(
              mnemonic: widget.mnemonic,
              formatNotifier: _formatNotifier,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 0 — Words
// ---------------------------------------------------------------------------

class _WordsTab extends StatelessWidget {
  final String mnemonic;
  final String mfp;
  final bool hasPassphrase;
  final String mfpNoPassphrase;

  const _WordsTab({
    required this.mnemonic,
    required this.mfp,
    required this.hasPassphrase,
    required this.mfpNoPassphrase,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final words = mnemonic.trim().split(' ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WordGrid(words: words),
          const SizedBox(height: 16),

          if (hasPassphrase) ...[
            _PassphraseWarningCard(
              mfpNoPassphrase: mfpNoPassphrase,
              mfpWithPassphrase: mfp,
            ),
            const SizedBox(height: 16),
          ],

          OutlinedButton.icon(
            onPressed: () => copySecretAndScheduleClear(
              mnemonic,
              successMessage: l10n.seedPhraseCopied,
            ),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(l10n.copyToClipboard),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordGrid extends StatelessWidget {
  final List<String> words;
  const _WordGrid({required this.words});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 3.2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: words.length,
      itemBuilder: (context, i) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withAlpha(AppAlpha.secondary),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  words[i],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PassphraseWarningCard extends StatelessWidget {
  final String mfpNoPassphrase;
  final String mfpWithPassphrase;

  const _PassphraseWarningCard({
    required this.mfpNoPassphrase,
    required this.mfpWithPassphrase,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer.withAlpha(AppAlpha.dim),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    size: 16, color: cs.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.seedPassphraseWarning,
                    style: TextStyle(fontSize: 12, color: cs.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MfpRow(
              label: l10n.seedMfpSeedOnly,
              mfp: mfpNoPassphrase,
              color: cs.secondary,
            ),
            const SizedBox(height: 6),
            _MfpRow(
              label: l10n.seedMfpWithPassphrase,
              mfp: mfpWithPassphrase,
              color: cs.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MfpRow extends StatelessWidget {
  final String label;
  final String mfp;
  final Color color;

  const _MfpRow({
    required this.label,
    required this.mfp,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withAlpha(AppAlpha.secondary),
          ),
        ),
        MfpBadge(label: mfp.toUpperCase(), color: color),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — QR
// ---------------------------------------------------------------------------

enum _QrFormat { standard, compact }

class _QrFormatSelector extends StatelessWidget {
  final _QrFormat selected;
  final ValueNotifier<_QrFormat> formatNotifier;

  const _QrFormatSelector({
    required this.selected,
    required this.formatNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<_QrFormat>(
      segments: [
        ButtonSegment(value: _QrFormat.standard, label: Text(l10n.seedQrStandard)),
        ButtonSegment(value: _QrFormat.compact, label: Text(l10n.seedQrCompact)),
      ],
      selected: {selected},
      onSelectionChanged: (s) => formatNotifier.value = s.first,
    );
  }
}

/// Builds a [QrCode] for [format] and [mnemonic].
///
/// Standard uses numeric mode (EC level L), version 2–4 by string length.
/// Compact uses binary mode (EC level L); always succeeds for valid mnemonics.
QrCode _buildQrForFormat(_QrFormat format, String mnemonic) {
  if (format == _QrFormat.standard) {
    final data = encodeSeedQrStandard(mnemonic);
    final v = data.length <= 77 ? 2 : data.length <= 127 ? 3 : 4;
    return QrCode(v, QrErrorCorrectLevel.L)..addNumeric(data);
  }
  return QrCode.fromUint8List(
    data: encodeSeedQrCompact(mnemonic),
    errorCorrectLevel: QrErrorCorrectLevel.L,
  );
}

class _QrTab extends StatefulWidget {
  final String mnemonic;
  final bool hasPassphrase;
  final ValueNotifier<_QrFormat> formatNotifier;

  const _QrTab({
    required this.mnemonic,
    required this.hasPassphrase,
    required this.formatNotifier,
  });

  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  late QrCode _qr;

  @override
  void initState() {
    super.initState();
    _qr = _buildQrForFormat(widget.formatNotifier.value, widget.mnemonic);
    widget.formatNotifier.addListener(_onFormatChange);
  }

  @override
  void dispose() {
    widget.formatNotifier.removeListener(_onFormatChange);
    super.dispose();
  }

  void _onFormatChange() {
    setState(() {
      _qr = _buildQrForFormat(widget.formatNotifier.value, widget.mnemonic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final format = widget.formatNotifier.value;
    final formatName =
        format == _QrFormat.standard ? l10n.seedQrStandard : l10n.seedQrCompact;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _QrFormatSelector(selected: format, formatNotifier: widget.formatNotifier),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView.withQr(
              qr: _qr,
              size: 260,
            ),
          ),
          const SizedBox(height: 12),

          Text(
            l10n.seedQrSize(formatName, _qr.moduleCount),
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withAlpha(AppAlpha.secondary),
              ),
            ),

          if (widget.hasPassphrase) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: cs.onSurface.withAlpha(AppAlpha.muted)),
                const SizedBox(width: 4),
                Text(
                  l10n.seedPassphraseNotIncluded,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withAlpha(AppAlpha.muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Paper guide (segment-by-segment)
// ---------------------------------------------------------------------------

/// Normalizes a mnemonic string for comparison: trimmed, lowercased, single spaces.
String _normalizeMnemonic(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

// Segment sizes per QR module count, matching krux/seedsigner paper templates:
//   21×21 → 7-module segments  (3×3 grid, 9 cells)
//   25×25 → 5-module segments  (5×5 grid, 25 cells)
//   29×29 → 5-module segments  (6×6 grid, last cell = 4 modules)
//   33×33 → 5-module segments  (7×7 grid, last cell = 3 modules)
int _segmentSizeFor(int moduleCount) => moduleCount <= 21 ? 7 : 5;

class _GuideTab extends StatefulWidget {
  final String mnemonic;
  final ValueNotifier<_QrFormat> formatNotifier;
  const _GuideTab({required this.mnemonic, required this.formatNotifier});

  @override
  State<_GuideTab> createState() => _GuideTabState();
}

class _GuideTabState extends State<_GuideTab> {
  late QrImage _qrImage;
  late int _moduleCount;
  late int _segSize;      // modules per segment side
  late int _segGridCount; // segments per row/column (ceil(moduleCount/segSize))

  int _currentSegment = 0;

  @override
  void initState() {
    super.initState();
    widget.formatNotifier.addListener(_onFormatChange);
    _buildQr();
  }

  @override
  void dispose() {
    widget.formatNotifier.removeListener(_onFormatChange);
    super.dispose();
  }

  void _onFormatChange() {
    setState(() {
      _currentSegment = 0;
      _buildQr();
    });
  }

  void _buildQr() {
    final qr = _buildQrForFormat(widget.formatNotifier.value, widget.mnemonic);
    _qrImage = QrImage(qr);
    _moduleCount = qr.moduleCount;
    _segSize = _segmentSizeFor(_moduleCount);
    _segGridCount = (_moduleCount / _segSize).ceil();
  }

  int get _totalSegments => _segGridCount * _segGridCount;

  String _segmentLabel(int idx) {
    final row = idx ~/ _segGridCount;
    final col = idx % _segGridCount;
    return '${String.fromCharCode(65 + row)}${col + 1}';
  }

  (int, int, int, int) _segmentBounds(int idx) {
    final row = idx ~/ _segGridCount;
    final col = idx % _segGridCount;
    final r0 = row * _segSize;
    final c0 = col * _segSize;
    final r1 = (r0 + _segSize).clamp(0, _moduleCount);
    final c1 = (c0 + _segSize).clamp(0, _moduleCount);
    return (r0, c0, r1, c1);
  }

  void _prev() {
    if (_currentSegment > 0) {
      setState(() => _currentSegment--);
    }
  }

  void _restart() {
    setState(() => _currentSegment = 0);
  }

  void _next() {
    if (_currentSegment < _totalSegments) {
      setState(() => _currentSegment++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    if (_currentSegment >= _totalSegments) {
      return _DoneView(onRestart: _restart, mnemonic: widget.mnemonic);
    }

    final (r0, c0, r1, c1) = _segmentBounds(_currentSegment);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _QrFormatSelector(
            selected: widget.formatNotifier.value,
            formatNotifier: widget.formatNotifier,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.seedGuideInstructions,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withAlpha(AppAlpha.secondary),
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_currentSegment + 1) / _totalSegments,
            backgroundColor: cs.surfaceContainerHigh,
            minHeight: 4,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.seedGuideSegmentLabel(
              _segmentLabel(_currentSegment),
              _totalSegments,
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: GestureDetector(
              onTap: _next,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final qrSize = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Center(
                    child: _QrWithHighlight(
                      qrImage: _qrImage,
                      moduleCount: _moduleCount,
                      segSize: _segSize,
                      segGridCount: _segGridCount,
                      r0: r0,
                      c0: c0,
                      r1: r1,
                      c1: c1,
                      size: qrSize,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            l10n.seedGuideTapToAdvance,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withAlpha(AppAlpha.muted),
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _currentSegment > 0 ? _prev : null,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l10n.previous),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _next,
                  icon: Icon(
                    _currentSegment < _totalSegments - 1
                        ? Icons.arrow_forward
                        : Icons.check,
                    size: 18,
                  ),
                  label: Text(
                    _currentSegment < _totalSegments - 1
                        ? l10n.next
                        : l10n.done,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full QR with segment grid overlay, dim overlay, and highlight.
// ---------------------------------------------------------------------------

class _QrWithHighlight extends StatelessWidget {
  final QrImage qrImage;
  final int moduleCount;
  final int segSize;
  final int segGridCount;
  final int r0, c0, r1, c1;
  final double size;

  const _QrWithHighlight({
    required this.qrImage,
    required this.moduleCount,
    required this.segSize,
    required this.segGridCount,
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: cs.outline.withAlpha(AppAlpha.border),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _QrHighlightPainter(
            qrImage: qrImage,
            moduleCount: moduleCount,
            segSize: segSize,
            segGridCount: segGridCount,
            r0: r0,
            c0: c0,
            r1: r1,
            c1: c1,
            highlightColor: cs.primary,
          ),
        ),
      ),
    );
  }
}

class _QrHighlightPainter extends CustomPainter {
  final QrImage qrImage;
  final int moduleCount;
  final int segSize;
  final int segGridCount;
  final int r0, c0, r1, c1;
  final Color highlightColor;

  const _QrHighlightPainter({
    required this.qrImage,
    required this.moduleCount,
    required this.segSize,
    required this.segGridCount,
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / moduleCount;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    final darkPaint = Paint()..color = Colors.black;
    for (int r = 0; r < moduleCount; r++) {
      for (int c = 0; c < moduleCount; c++) {
        if (qrImage.isDark(r, c)) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
            darkPaint,
          );
        }
      }
    }

    // Dim overlay with punch-out for current segment.
    final segRect = Rect.fromLTRB(
      c0 * cellSize,
      r0 * cellSize,
      c1 * cellSize,
      r1 * cellSize,
    );
    final dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(segRect);
    dimPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, Paint()..color = Colors.black.withAlpha(150));

    // Segment boundary grid — drawn after dim so lines are visible everywhere.
    final segGridPaint = Paint()
      ..color = highlightColor.withAlpha(160)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 1; i < segGridCount; i++) {
      final pos = i * segSize * cellSize;
      canvas.drawLine(Offset(pos, 0), Offset(pos, size.height), segGridPaint);
      canvas.drawLine(Offset(0, pos), Offset(size.width, pos), segGridPaint);
    }

    // Module-level sub-grid inside active segment only.
    final subGridPaint = Paint()
      ..color = Colors.grey.withAlpha(130)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.save();
    canvas.clipRect(segRect);
    for (int c = c0 + 1; c < c1; c++) {
      final x = c * cellSize;
      canvas.drawLine(
          Offset(x, r0 * cellSize), Offset(x, r1 * cellSize), subGridPaint);
    }
    for (int r = r0 + 1; r < r1; r++) {
      final y = r * cellSize;
      canvas.drawLine(
          Offset(c0 * cellSize, y), Offset(c1 * cellSize, y), subGridPaint);
    }
    canvas.restore();

    // Highlight border around current segment.
    canvas.drawRect(
      segRect,
      Paint()
        ..color = highlightColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(_QrHighlightPainter old) =>
      old.r0 != r0 || old.c0 != c0 || old.r1 != r1 || old.c1 != c1 ||
      old.segGridCount != segGridCount || old.highlightColor != highlightColor;
}

class _DoneView extends StatelessWidget {
  final VoidCallback onRestart;
  final String mnemonic;

  const _DoneView({
    required this.onRestart,
    required this.mnemonic,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 72, color: cs.primary),
          const SizedBox(height: 20),
          Text(
            l10n.seedGuideDoneTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.seedGuideDoneBody,
            style: TextStyle(
              color: cs.onSurface.withAlpha(AppAlpha.secondary),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () async {
              final scanned = await QrScannerScreen.push(context);
              if (scanned == null) return;
              if (_normalizeMnemonic(scanned) == _normalizeMnemonic(mnemonic)) {
                showSuccessToast(l10n.seedGuideVerifySuccess);
              } else {
                showErrorToast(l10n.seedGuideVerifyMismatch);
              }
            },
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: Text(l10n.seedGuideVerifyQr),
            style: FilledButton.styleFrom(
              minimumSize: const Size(200, 44),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text(l10n.seedGuideRestart),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(200, 44),
            ),
          ),
        ],
      ),
    );
  }
}
