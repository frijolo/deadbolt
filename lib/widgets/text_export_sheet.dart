import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bc_ur/bc_ur.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/toast_helper.dart';

// Characters above this threshold trigger animated UR instead of a single
// plain-text QR.  QR version 40 byte mode holds ~2953 bytes; we leave margin.
const int _kMaxPlainQrChars = 2800;

// Density slider: maps 0.0–1.0 to fragment sizes (bytes of CBOR payload per
// UR fragment).  Smaller → more frames, each individually easier to scan.
const double _kDensityDefault = 0.25;
const int _kFragmentMin = 100;
const int _kFragmentMax = 600;

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
              _showQrDialog(context, text);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.saveToDownloads),
            onTap: () async {
              Navigator.pop(ctx);
              await _saveToDownloads(context, text, fileName);
            },
          ),
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

void _showQrDialog(BuildContext context, String data) {
  showDialog<void>(
    context: context,
    builder: (ctx) => _QrDialog(data: data),
  );
}

Future<void> _saveToDownloads(
  BuildContext context,
  String text,
  String fileName,
) async {
  final l10n = context.l10n;
  try {
    final dir =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.txt');
    await file.writeAsString(text);
    if (context.mounted) showSuccessToast(context, l10n.savedToDownloads);
  } catch (e) {
    if (context.mounted) showErrorToast(context, l10n.exportFailed(e.toString()));
  }
}

int _fragmentBytes(double density) =>
    (_kFragmentMin + density * (_kFragmentMax - _kFragmentMin)).round();

int _errorCorrectionLevel(double density) {
  if (density < 0.33) return QrErrorCorrectLevel.L;
  if (density < 0.67) return QrErrorCorrectLevel.M;
  if (density < 0.90) return QrErrorCorrectLevel.Q;
  return QrErrorCorrectLevel.H;
}

// ---------------------------------------------------------------------------
// QR dialog
//
// Short content  (≤ _kMaxPlainQrChars): single plain-text QR.
//   Density slider → QR error-correction level (L / M / Q / H).
//
// Long content   (> _kMaxPlainQrChars): animated UR (ur:bytes), BC-UR
//   fountain codes — dominant multi-part QR standard in Bitcoin ecosystem.
//   Density slider → fragment size (fewer small frames ↔ more large frames).
// ---------------------------------------------------------------------------

class _QrDialog extends StatefulWidget {
  final String data;
  const _QrDialog({required this.data});

  @override
  State<_QrDialog> createState() => _QrDialogState();
}

class _QrDialogState extends State<_QrDialog> {
  BCURFountainEncoder? _encoder;
  String _currentFrame = '';
  int _seqIndex = 0;
  int _seqTotal = 1;
  Timer? _timer;

  double _density = _kDensityDefault;

  bool get _isAnimated => widget.data.length > _kMaxPlainQrChars;

  @override
  void initState() {
    super.initState();
    if (_isAnimated) {
      _startEncoder();
    } else {
      _currentFrame = widget.data;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startEncoder() {
    _timer?.cancel();
    final bytes = Uint8List.fromList(utf8.encode(widget.data));
    final bcur = BCUR.fromData('bytes', bytes);
    _encoder =
        BCURFountainEncoder(bcur, maxFragmentLength: _fragmentBytes(_density));

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

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.qrDialogTitle)),
          if (_isAnimated)
            Text(
              l10n.qrPart(_seqIndex + 1, _seqTotal),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.orange),
            ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 260,
            height: 260,
            child: QrImageView(
              data: _currentFrame,
              version: QrVersions.auto,
              errorCorrectionLevel: _isAnimated
                  ? QrErrorCorrectLevel.L
                  : _errorCorrectionLevel(_density),
              backgroundColor: Colors.white,
            ),
          ),

          if (_isAnimated) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_seqIndex + 1) / _seqTotal,
              backgroundColor: Colors.white12,
              color: Colors.orange,
            ),
          ],

          // Density slider
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                l10n.qrDensityLabel,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              Expanded(
                child: Slider(
                  value: _density,
                  min: 0,
                  max: 1,
                  divisions: 8,
                  onChanged: (v) => setState(() => _density = v),
                  onChangeEnd: (_) {
                    if (_isAnimated) _startEncoder();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
