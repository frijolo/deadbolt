import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bc_ur/bc_ur.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/qr_decoder.dart';
import 'package:deadbolt/utils/seed_qr.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/widgets/loading_indicator.dart';

/// Platforms where [mobile_scanner] has a native plugin implementation.
bool get _isCameraSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Visual state of the last decoded frame.
enum _ScanState {
  /// No frame processed yet.
  idle,
  /// Frame captured but no QR found.
  noQr,
  /// QR decoded but was a BC-UR part already received (duplicate).
  duplicate,
  /// QR decoded and it contributed a new BC-UR part.
  newPart,
}

/// Full-screen QR code scanner.
///
/// On platforms supported by mobile_scanner (Android, iOS, macOS, Web) this
/// opens the device camera and handles both plain-text QR codes and animated
/// BC-UR fountain codes.
///
/// On Linux and Windows this uses flutter_lite_camera to capture live frames
/// (~3 fps) decoded by zxing2. If the camera is unavailable (no GStreamer, no
/// webcam) it falls back to importing a QR image file.
///
/// Returns the decoded text via [Navigator.pop], or null if the user cancels.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  /// Push the scanner and await the decoded text.
  static Future<String?> push(BuildContext context) {
    return Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => const QrScannerScreen(),
      ),
    );
  }

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  // -- Shared BC-UR state --
  BCURFountainDecoder? _urDecoder;
  bool _isAnimated = false;
  bool _done = false;
  int _receivedCount = 0;
  int _expectedCount = 0;

  // -- Scan indicator state --
  _ScanState _scanState = _ScanState.idle;
  int? _lastSeenSeqNum;

  // -- Mobile scanner controller --
  MobileScannerController? _scannerController;

  // -- Desktop camera state --
  FlutterLiteCamera? _camera;
  ui.Image? _previewImage;
  bool _cameraInitFailed = false;

  double get _progress =>
      _expectedCount > 0 ? _receivedCount / _expectedCount : 0.0;

  @override
  void initState() {
    super.initState();
    if (_isCameraSupported) {
      _scannerController = MobileScannerController();
    } else {
      _initDesktopCamera();
    }
  }

  @override
  void dispose() {
    _camera?.release();
    _scannerController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Desktop camera (Linux / Windows)
  // ---------------------------------------------------------------------------

  Future<void> _initDesktopCamera() async {
    final camera = FlutterLiteCamera();
    try {
      final devices = await camera.getDeviceList();
      if (devices.isEmpty) throw Exception('No camera devices found');
      // Some drivers (e.g. ipu6 on Intel laptops) expose several video nodes
      // where the low-numbered ones are metadata-only and fail to open.
      // Try each index in order and use the first one that opens successfully.
      bool opened = false;
      for (int i = 0; i < devices.length; i++) {
        opened = await camera.open(i);
        if (opened) break;
      }
      if (!opened) throw Exception('Failed to open camera');
      _camera = camera;
      _startCameraLoop();
    } catch (e) {
      if (mounted) setState(() => _cameraInitFailed = true);
    }
  }

  Future<void> _startCameraLoop() async {
    while (!_done && mounted && _camera != null) {
      await _pollFrame();
    }
  }

  Future<void> _pollFrame() async {
    try {
      final frame = await _camera!.captureFrame();
      if (!frame.containsKey('data')) return;

      final Uint8List rgbBytes = frame['data'] as Uint8List;
      final int w = frame['width'] as int;
      final int h = frame['height'] as int;

      final qrResult = decodeQrFromRgbFrame(w, h, rgbBytes);
      final uiImage  = await _rgbToUiImage(w, h, rgbBytes);

      if (qrResult != null) {
        // Compact SeedQR: try raw bytes before falling back to text.
        final rawBytes = qrResult.rawBytes;
        if (rawBytes != null && rawBytes.isNotEmpty) {
          final mnemonic = decodeSeedQrCompact(rawBytes);
          if (mnemonic != null) {
            _finishScan(mnemonic);
          }
        }
        if (!_done && mounted) _onQrValue(qrResult.text);
      } else {
        if (mounted) setState(() => _scanState = _ScanState.noQr);
      }

      if (mounted) {
        setState(() => _previewImage = uiImage);
      }
    } catch (_) {
      // Transient frame capture error — skip frame and continue polling.
    }
  }

  /// Converts an RGB888 camera buffer to a [ui.Image] for display.
  ///
  /// The native plugin outputs true RGB888 (R, G, B order), top-down.
  Future<ui.Image> _rgbToUiImage(int w, int h, Uint8List rgb) async {
    final rgba = Uint8List(w * h * 4);
    for (var row = 0; row < h; row++) {
      for (var col = 0; col < w; col++) {
        final dst = (row * w + col) * 4;
        final src = (row * w + col) * 3;
        rgba[dst] = rgb[src]; // R
        rgba[dst + 1] = rgb[src + 1]; // G
        rgba[dst + 2] = rgb[src + 2]; // B
        rgba[dst + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Shared QR handling
  // ---------------------------------------------------------------------------

  /// Extracts the seqNum from a BC-UR part string, e.g. "UR:CRYPTO-PSBT/88-121/..." → 88.
  static int? _parseSeqNum(String value) {
    final parts = value.split('/');
    if (parts.length < 2) return null;
    return int.tryParse(parts[1].split('-')[0]);
  }

  /// Stops the camera and pops with [result]. No-op if already done.
  void _finishScan(String result) {
    if (_done) return;
    _done = true;
    _scannerController?.stop();
    if (mounted) Navigator.pop(context, result);
  }

  /// Called by both MobileScanner and the desktop polling branch.
  void _onQrValue(String value) {
    if (_done) return;

    // Standard SeedQR: digit-only string (e.g. "0001000200030004...")
    final mnemonic = decodeSeedQrText(value);
    if (mnemonic != null) {
      _finishScan(mnemonic);
      return;
    }

    // Compact SeedQR fallback: binary-mode QR decoded as UTF-8 string when
    // rawDecodedBytes is unavailable (ML Kit uses UTF-8 for rawValue).
    // Re-encoding the string as UTF-8 recovers the original bytes exactly,
    // because UTF-8 encode/decode is the inverse of itself for valid content.
    final rawBytes = Uint8List.fromList(utf8.encode(value));
    final compactMnemonic = decodeSeedQrCompact(rawBytes);
    if (compactMnemonic != null) {
      _finishScan(compactMnemonic);
      return;
    }

    if (value.toLowerCase().startsWith('ur:')) {
      _urDecoder ??= BCURFountainDecoder();

      // Extract seqNum from header to detect physical frame changes.
      final seqNum = _parseSeqNum(value);
      final isNewFrame = seqNum != _lastSeenSeqNum;
      _lastSeenSeqNum = seqNum;

      final beforeCount = _urDecoder!.receivedCount;
      try {
        _urDecoder!.receivePart(value.toLowerCase());
      } catch (_) {
        return;
      }
      final afterCount = _urDecoder!.receivedCount;
      final isNew = afterCount > beforeCount;

      setState(() {
        _isAnimated = true;
        _receivedCount = afterCount;
        _expectedCount = _urDecoder!.expectedCount;
        // Only update the dot when the physical QR frame has changed.
        if (isNewFrame) {
          _scanState = isNew ? _ScanState.newPart : _ScanState.duplicate;
        }
      });

      if (_urDecoder!.isComplete) {
        final bcur = _urDecoder!.getResult();
        if (bcur == null) {
          // Decode error (checksum mismatch or density changed mid-scan).
          // Reset and continue scanning from scratch.
          _urDecoder!.reset();
          setState(() {
            _receivedCount = 0;
            _expectedCount = 0;
            _lastSeenSeqNum = null;
          });
          return;
        }
        final data = bcur.decodeData() as List<int>;
        // Try UTF-8 first (ur:bytes with text payload, e.g. descriptors).
        // For binary payloads like ur:crypto-psbt, fall back to base64 —
        // the PSBT import flow accepts base64 strings.
        String result;
        try {
          result = utf8.decode(data);
        } catch (_) {
          result = base64Encode(data);
        }
        _finishScan(result);
      }
    } else {
      _finishScan(value);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;

    // Compact SeedQR: binary-mode QR code with raw 11-bit packed word indices.
    // Same pattern as BC-UR PSBT: read raw bytes, decode to a usable string.
    final decoded = barcode.rawDecodedBytes;
    if (decoded != null) {
      final bytes = switch (decoded) {
        DecodedBarcodeBytes(:final bytes) => bytes,
        DecodedVisionBarcodeBytes(:final bytes) => bytes,
      };
      if (bytes != null && bytes.isNotEmpty) {
        final mnemonic = decodeSeedQrCompact(bytes);
        if (mnemonic != null) {
          _finishScan(mnemonic);
          return;
        }
      }
    }

    final value = barcode.rawValue;
    if (value == null || value.isEmpty) return;
    _onQrValue(value);
  }

  Future<void> _importFromQrImage() async {
    final l10n = context.l10n;
    try {
      final result = await decodeQrFromImageFile();
      if (result != null) {
        _finishScan(result.trim());
      }
    } catch (_) {
      if (mounted) showErrorToast(l10n.qrNotFoundInImage);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget body;
    if (_isCameraSupported) {
      body = _buildMobileScanner(l10n);
    } else if (_cameraInitFailed) {
      body = _buildFileFallback(l10n);
    } else {
      body = _buildDesktopCamera(l10n);
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanQrCode)),
      body: body,
    );
  }

  Widget _buildMobileScanner(AppLocalizations l10n) {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 48),
                const SizedBox(height: 12),
                Text(l10n.cameraError, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        if (_isAnimated) _buildUrOverlay(),
      ],
    );
  }

  Widget _buildDesktopCamera(AppLocalizations l10n) {
    return Stack(
      children: [
        // Camera preview
        _previewImage != null
            ? SizedBox.expand(
                child: RawImage(
                  image: _previewImage,
                  fit: BoxFit.cover,
                ),
              )
            : LoadingIndicator(message: context.l10n.initializingCamera),
        // BC-UR overlay
        if (_isAnimated) _buildUrOverlay(),
      ],
    );
  }

  /// Progress bar + parts counter shown during BC-UR scanning.
  Widget _buildUrOverlay() {
    final dotColor = switch (_scanState) {
      _ScanState.newPart   => Colors.green,
      _ScanState.duplicate => Colors.blue,
      _ScanState.noQr      => Colors.red,
      _ScanState.idle      => Colors.transparent,
    };
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: Colors.black45,
            color: AppAccent.color,
            minHeight: 6,
          ),
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(vertical: 4),
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$_receivedCount / $_expectedCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppAccent.color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileFallback(AppLocalizations l10n) {
    return SafeArea(
      top: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 48,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(138)),
            const SizedBox(height: 12),
            Text(
              l10n.cameraError,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(138)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.image_outlined),
              label: Text(l10n.importFromQrImage),
              onPressed: _importFromQrImage,
            ),
          ],
        ),
      ),
    );
  }
}
