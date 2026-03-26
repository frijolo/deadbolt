import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bc_ur/bc_ur.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show stripPsbtForHw;
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/toast_helper.dart';

/// True on Android and iOS — platforms where [share_plus] is the right way to
/// export a file (via the native share sheet → "Save to Files" / "Drive" …).
/// On desktop, [FilePicker.platform.saveFile] shows a native save dialog instead.
bool get _isMobileExport =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

// Content byte length above which the animated switch defaults to ON.
const int _kMaxPlainQrChars = 2800;

// QR version 40 at M error-correction holds 2331 bytes.
// Above this the data cannot fit in a static QR code at the M level we use.
const int _kQrHardMax = 2331;

// Density levels for animated BC-UR mode.
// Fragment sizes are chosen so that the encoded QR string (prefix + bytewords)
// fits within the byte-mode L-ECC capacity of the target QR version:
//   string_len ≈ 61 + 2 × fragment_bytes
//   v6=134, v8=192, v10=271, v12=367 bytes capacity
({String label, int fragBytes, int qrVersion}) _densityLevel(int idx) =>
    const [
      (label: 'Low',      fragBytes: 36,  qrVersion: 6),
      (label: 'Mid',      fragBytes: 65,  qrVersion: 8),
      (label: 'High',     fragBytes: 105, qrVersion: 10),
      (label: 'VeryHigh', fragBytes: 153, qrVersion: 12),
    ][idx];
const int _kDensityCount = 4;
const int _kDensityDefault = 0;

// Speed levels: milliseconds between BC-UR frames.
({String label, int intervalMs}) _speedLevel(int idx) => const [
      (label: 'Slow',     intervalMs: 1000),
      (label: 'Mid',      intervalMs: 600),
      (label: 'Fast',     intervalMs: 300),
      (label: 'VeryFast', intervalMs: 150),
    ][idx];
const int _kSpeedCount = 4;
const int _kSpeedDefault = 1; // Mid

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows a bottom sheet with four export options for any text content:
/// copy to clipboard, QR, save to Downloads, share.
void showTextExportSheet(
  BuildContext context, {
  required String text,
  required String fileName,
  required String copiedMessage,
  String fileExtension = 'txt',
  bool bigText = false,
}) {
  final l10n = context.l10n;
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!bigText) ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.copyToClipboard),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: text));
              showSuccessToast(context, copiedMessage);
            },
          ),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: Text(l10n.showQrCode),
            onTap: () {
              Navigator.pop(ctx);
              showQrDialog(context, text);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.saveAs),
            onTap: () async {
              Navigator.pop(ctx);
              await _saveWithFilePicker(context, utf8.encode(text), fileName, fileExtension);
            },
          ),
          if (_isMobileExport || bigText)
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.shareText),
              onTap: () {
                Navigator.pop(ctx);
                _shareAsFile(
                  context,
                  bytes: utf8.encode(text),
                  fileName: '$fileName.$fileExtension',
                );
              },
            ),
          if (!bigText) ListTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: Text(l10n.showAsText),
            onTap: () {
              Navigator.pop(ctx);
              _showAsTextDialog(context, text);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void showPsbtExportSheet(
  BuildContext context, {
  required String psbtBase64,
  String fileName = 'transaction',
}) {
  final l10n = context.l10n;
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: Text(l10n.showQrCode),
            onTap: () async {
              Navigator.pop(ctx);
              final strippedBase64 = await stripPsbtForHw(
                psbtBase64: psbtBase64,
              ).catchError((_) => psbtBase64);
              if (!context.mounted) return;
              showQrDialog(
                context,
                strippedBase64,
                urBytes: base64Decode(strippedBase64),
                urType: 'crypto-psbt',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.copyToClipboard),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: psbtBase64));
              showSuccessToast(context, l10n.psbtExportedCopied);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.saveAs),
            onTap: () async {
              Navigator.pop(ctx);
              await _saveWithFilePicker(context, base64Decode(psbtBase64), fileName, 'psbt');
            },
          ),
          if (_isMobileExport)
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.shareText),
              onTap: () {
                Navigator.pop(ctx);
                _shareAsFile(
                  context,
                  bytes: base64Decode(psbtBase64),
                  fileName: '$fileName.psbt',
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}


Future<void> _shareAsFile(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  } catch (e) {
    if (context.mounted) {
      final l10n = context.l10n;
      showErrorToast(context, l10n.exportFailed(e.toString()));
    }
  }
}

void _showAsTextDialog(BuildContext context, String text) {
  final l10n = context.l10n;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.showAsText),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Show a QR dialog for [data].
///
/// For Bitcoin PSBTs, pass [urBytes] (raw binary PSBT bytes decoded from
/// base64) and [urType] = `'crypto-psbt'`.  The animated BC-UR encoder will
/// then emit `ur:crypto-psbt` frames that hardware wallets (Krux, Coldcard…)
/// understand.  The static QR still shows [data] as-is (plain base64).
void showQrDialog(
  BuildContext context,
  String data, {
  Uint8List? urBytes,
  String urType = 'bytes',
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      child: _QrDialog(data: data, urBytes: urBytes, urType: urType),
    ),
  );
}

Future<void> _saveWithFilePicker(
  BuildContext context,
  Uint8List bytes,
  String fileName,
  String ext,
) async {
  final l10n = context.l10n;
  try {
    final savedPath = await FilePicker.platform.saveFile(
      fileName: '$fileName.$ext',
      type: FileType.custom,
      allowedExtensions: [ext],
      bytes: bytes,
    );
    if (savedPath == null) return;
    // On desktop, FilePicker may not write the bytes itself.
    if (!File(savedPath).existsSync()) {
      await File(savedPath).writeAsBytes(bytes);
    }
    if (context.mounted) showSuccessToast(context, l10n.savedToDownloads);
  } catch (e) {
    if (context.mounted) showErrorToast(context, l10n.exportFailed(e.toString()));
  }
}

// ---------------------------------------------------------------------------
// QR dialog (full-screen)
// ---------------------------------------------------------------------------

class _QrDialog extends StatefulWidget {
  final String data;
  final Uint8List? urBytes;
  final String urType;

  const _QrDialog({
    required this.data,
    this.urBytes,
    this.urType = 'bytes',
  });

  @override
  State<_QrDialog> createState() => _QrDialogState();
}

class _QrDialogState extends State<_QrDialog> {
  // BC-UR encoder state
  BCURFountainEncoder? _encoder;
  String _currentFrame = '';
  int _seqIndex = 0;
  int _seqTotal = 1;
  Timer? _timer;

  // User-controlled mode
  late bool _isAnimated;
  int _densityIdx = _kDensityDefault;
  int _speedIdx = _kSpeedDefault;

  /// Length of the string shown in the static QR (base64 / plain text).
  late final int _dataByteLen = utf8.encode(widget.data).length;

  /// True when the static QR content exceeds QR v40 capacity at M correction.
  bool get _forceAnimated => _dataByteLen > _kQrHardMax;

  @override
  void initState() {
    super.initState();
    _isAnimated = _dataByteLen > _kMaxPlainQrChars || _forceAnimated;
    if (_isAnimated) _startEncoder();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startEncoder() {
    _timer?.cancel();
    final bytes = widget.urBytes ?? Uint8List.fromList(utf8.encode(widget.data));
    final bcur = BCUR.fromData(widget.urType, bytes);
    final fragSize = _densityLevel(_densityIdx).fragBytes.clamp(1, bytes.length);
    _encoder = BCURFountainEncoder(bcur, maxFragmentLength: fragSize);
    _currentFrame = _encoder!.nextPart();
    final (_, total) = _parseSeqInfo(_currentFrame);
    _seqTotal = total;
    _seqIndex = 0;
    final intervalMs = _speedLevel(_speedIdx).intervalMs;
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      final frame = _encoder!.nextPart();
      final (seqnum, seqtotal) = _parseSeqInfo(frame);
      setState(() {
        _currentFrame = frame;
        _seqIndex = (seqnum - 1) % seqtotal;
        _seqTotal = seqtotal;
      });
    });
  }

  void _setAnimated(bool value) {
    if (value) {
      _startEncoder();
      setState(() => _isAnimated = true);
    } else {
      _timer?.cancel();
      _timer = null;
      _encoder = null;
      setState(() => _isAnimated = false);
    }
  }

  (int, int) _parseSeqInfo(String fragment) {
    final match = RegExp(r'/(\d+)-(\d+)/').firstMatch(fragment);
    if (match == null) return (1, 1);
    final n = int.tryParse(match.group(1)!) ?? 1;
    final m = int.tryParse(match.group(2)!) ?? 1;
    return (n, m);
  }

  /// Slider with a title on the left and always-visible level labels below the track.
  Widget _buildLabeledSlider({
    required String title,
    required List<String> labels,
    required int value,
    required void Function(int) onChanged,
    required VoidCallback onChangeEnd,
    required TextStyle? dimStyle,
    required TextStyle? labelStyle,
  }) {
    // Fixed width keeps both slider tracks aligned regardless of title length.
    const double titleWidth = 64;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: titleWidth,
          child: Padding(
            // Align vertically with the slider thumb (~20dp top padding inside Slider).
            padding: const EdgeInsets.only(top: 14),
            child: Text(title, style: dimStyle),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: value.toDouble(),
                min: 0,
                max: (labels.length - 1).toDouble(),
                divisions: labels.length - 1,
                onChanged: (v) => onChanged(v.round()),
                onChangeEnd: (_) => onChangeEnd(),
              ),
              // Padding matches the slider's internal horizontal inset.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: labels
                      .map((l) => Text(l, style: labelStyle))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dimStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Colors.white54);
    final labelStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: Colors.white38, fontSize: 10);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.qrDialogTitle),
        actions: [
          if (_isAnimated)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Text(
                l10n.qrPart(_seqIndex + 1, _seqTotal),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppAccent.color),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // QR code — fills all available space above the controls.
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _isAnimated
                      ? QrImageView(
                          data: _currentFrame,
                          version: QrVersions.auto,
                          errorCorrectionLevel: QrErrorCorrectLevel.L,
                          backgroundColor: Colors.white,
                        )
                      : QrImageView(
                          data: widget.data,
                          version: QrVersions.auto,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          backgroundColor: Colors.white,
                        ),
                ),
              ),
            ),
          ),

          // BC-UR progress bar (thin strip).
          if (_isAnimated)
            LinearProgressIndicator(
              value: (_seqIndex + 1) / _seqTotal,
              backgroundColor: Colors.white12,
              color: AppAccent.color,
              minHeight: 3,
            ),

          // Controls.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated switch.
                Row(
                  children: [
                    Expanded(child: Text(l10n.qrAnimatedLabel, style: dimStyle)),
                    Switch(
                      value: _isAnimated,
                      onChanged: _forceAnimated ? null : _setAnimated,
                    ),
                  ],
                ),

                // Density + Speed sliders — only in animated mode.
                if (_isAnimated) ...[
                  _buildLabeledSlider(
                    title: 'Density',
                    labels: List.generate(_kDensityCount, (i) => _densityLevel(i).label),
                    value: _densityIdx,
                    onChanged: (v) => setState(() => _densityIdx = v),
                    onChangeEnd: _startEncoder,
                    dimStyle: dimStyle,
                    labelStyle: labelStyle,
                  ),
                  _buildLabeledSlider(
                    title: 'Speed',
                    labels: List.generate(_kSpeedCount, (i) => _speedLevel(i).label),
                    value: _speedIdx,
                    onChanged: (v) => setState(() => _speedIdx = v),
                    onChangeEnd: _startEncoder,
                    dimStyle: dimStyle,
                    labelStyle: labelStyle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
