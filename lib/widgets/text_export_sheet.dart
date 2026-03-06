import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bc_ur/bc_ur.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:deadbolt/l10n/l10n.dart';
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

// Animated mode: each step is the max CBOR fragment size (raw bytes) passed
// to the BC-UR fountain encoder.  The actual QR frame is ~2× larger after
// bytewords encoding, so the resulting QR version is much higher than the
// label suggests — but hardware wallet cameras handle it fine.
//
// Bitcoin PSBTs for P2WPKH/P2WSH inputs include the full previous transaction
// (non_witness_utxo), making them ~15 KB binary.  At 1000 B/fragment that
// results in ~16 frames, matching what Krux produces for its signed response.
//
//   Step 0 →   86 B  (smallest QR, most frames)
//   Step 1 →  216 B
//   Step 2 →  415 B
//   Step 3 →  669 B
//   Step 4 → 1000 B  (default — ~16 frames for a typical PSBT)
const List<int> _kFragSteps = [86, 216, 415, 669, 1000];
const int _kFragDefaultIdx = 0; // 86 B

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
}) {
  final l10n = context.l10n;
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
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
          if (!_isMobileExport)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(l10n.saveAs),
              onTap: () async {
                Navigator.pop(ctx);
                await _saveWithFilePicker(context, text, fileName);
              },
            ),
          if (_isMobileExport)
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.shareFile),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(text);
              },
            ),
        ],
      ),
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
    builder: (ctx) => _QrDialog(data: data, urBytes: urBytes, urType: urType),
  );
}

Future<void> _saveWithFilePicker(
  BuildContext context,
  String text,
  String fileName,
) async {
  final l10n = context.l10n;
  try {
    final savedPath = await FilePicker.platform.saveFile(
      fileName: '$fileName.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (savedPath == null) return; // user cancelled
    await File(savedPath).writeAsBytes(utf8.encode(text));
    if (context.mounted) showSuccessToast(context, l10n.savedToDownloads);
  } catch (e) {
    if (context.mounted) showErrorToast(context, l10n.exportFailed(e.toString()));
  }
}

// ---------------------------------------------------------------------------
// QR dialog
//
// A Switch lets the user toggle between a static QR code and animated BC-UR
// fountain codes (the dominant multi-part QR standard in Bitcoin).
//
// Static mode  → plain QR at error-correction M (auto-selected, no controls).
//
// Animated mode → Slider controls bytes per BC-UR fragment (capped to the
//                 actual payload size so the value always has meaning).
//
// The switch is permanently disabled (forced ON) when content exceeds the
// physical QR capacity (_kQrHardMax bytes at M correction).
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
  int _fragStepIdx = _kFragDefaultIdx;

  /// Length of the string shown in the static QR (base64 / plain text).
  late final int _dataByteLen = utf8.encode(widget.data).length;

  /// Length of the actual fountain-encoder payload.
  /// For PSBTs this is the raw binary size (urBytes); otherwise UTF-8 of data.
  late final int _urPayloadLen =
      widget.urBytes?.length ?? utf8.encode(widget.data).length;

  /// True when the static QR content exceeds QR v40 capacity at M correction.
  bool get _forceAnimated => _dataByteLen > _kQrHardMax;

  /// Highest step index whose fragment size does not exceed the payload.
  /// Uses the actual UR payload length so the slider is calibrated correctly
  /// for both text (descriptors) and binary (PSBTs) payloads.
  int get _maxStepIdx {
    for (int i = _kFragSteps.length - 1; i > 0; i--) {
      if (_kFragSteps[i] <= _urPayloadLen) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _isAnimated = _dataByteLen > _kMaxPlainQrChars || _forceAnimated;
    _fragStepIdx = _fragStepIdx.clamp(0, _maxStepIdx);
    if (_isAnimated) {
      _startEncoder();
    }
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
    final fragSize = _kFragSteps[_fragStepIdx].clamp(1, bytes.length);
    _encoder = BCURFountainEncoder(bcur, maxFragmentLength: fragSize);
    _currentFrame = _encoder!.nextPart();
    final (_, total) = _parseSeqInfo(_currentFrame);
    _seqTotal = total;
    _seqIndex = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final subtitleStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Colors.white54);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(l10n.qrDialogTitle)),
          if (_isAnimated)
            Text(
              l10n.qrPart(_seqIndex + 1, _seqTotal),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppAccent.color),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // QR image
          SizedBox(
            width: 260,
            height: 260,
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

          // BC-UR fountain progress
          if (_isAnimated) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_seqIndex + 1) / _seqTotal,
              backgroundColor: Colors.white12,
              color: AppAccent.color,
            ),
          ],

          const SizedBox(height: 12),

          // Animated switch
          Row(
            children: [
              Expanded(
                child: Text(l10n.qrAnimatedLabel, style: subtitleStyle),
              ),
              Switch(
                value: _isAnimated,
                onChanged: _forceAnimated ? null : _setAnimated,
              ),
            ],
          ),

          // Bytes per frame slider — only shown in animated mode.
          // Each discrete step = QR v(5/10/15/20/25) capacity at M level.
          if (_isAnimated && _maxStepIdx > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(l10n.qrBytesPerFrame, style: subtitleStyle),
                Expanded(
                  child: Slider(
                    value: _fragStepIdx.toDouble(),
                    min: 0,
                    max: _maxStepIdx.toDouble(),
                    divisions: _maxStepIdx,
                    onChanged: (v) =>
                        setState(() => _fragStepIdx = v.round()),
                    onChangeEnd: (_) => _startEncoder(),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${_kFragSteps[_fragStepIdx]}',
                    style: subtitleStyle,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: const [],
    );
  }
}
