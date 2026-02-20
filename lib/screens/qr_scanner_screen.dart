import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bc_ur/bc_ur.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/utils/qr_decoder.dart';
import 'package:deadbolt/utils/toast_helper.dart';

/// Platforms where [mobile_scanner] has a native plugin implementation.
bool get _isCameraSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

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
  double _progress = 0;
  bool _isAnimated = false;
  bool _done = false;

  // -- Desktop camera state --
  FlutterLiteCamera? _camera;
  Timer? _pollTimer;
  ui.Image? _previewImage;
  bool _cameraInitFailed = false;

  @override
  void initState() {
    super.initState();
    if (!_isCameraSupported) {
      _initDesktopCamera();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _camera?.release();
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
      final opened = await camera.open(0);
      if (!opened) throw Exception('Failed to open camera');
      _camera = camera;
      _pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        _pollFrame();
      });
    } catch (_) {
      // No camera / GStreamer not installed — show file fallback.
      if (mounted) setState(() => _cameraInitFailed = true);
    }
  }

  Future<void> _pollFrame() async {
    if (_done || _camera == null) return;
    try {
      final frame = await _camera!.captureFrame();
      if (!frame.containsKey('data')) return;

      final Uint8List rgbBytes = frame['data'] as Uint8List;
      final int w = frame['width'] as int;
      final int h = frame['height'] as int;

      // Decode QR (pure Dart — runs on main isolate, ~50ms per frame).
      final qrValue = decodeQrFromRgbFrame(w, h, rgbBytes);
      if (qrValue != null && mounted) {
        _onQrValue(qrValue);
      }

      // Update preview image.
      final uiImage = await _rgbToUiImage(w, h, rgbBytes);
      if (mounted) {
        setState(() => _previewImage = uiImage);
      }
    } catch (_) {
      // Ignore transient capture errors.
    }
  }

  /// Converts an RGB888 camera buffer to a [ui.Image] for display.
  ///
  /// The native plugin outputs true RGB888 (R, G, B order).  V4L2 / MJPEG
  /// streams are often stored bottom-up, so rows are flipped vertically here
  /// to produce the correct on-screen orientation.
  Future<ui.Image> _rgbToUiImage(int w, int h, Uint8List rgb) async {
    final rgba = Uint8List(w * h * 4);
    for (var row = 0; row < h; row++) {
      final srcRow = h - 1 - row; // vertical flip
      for (var col = 0; col < w; col++) {
        final dst = (row * w + col) * 4;
        final src = (srcRow * w + col) * 3;
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

  /// Called by both MobileScanner and the desktop polling branch.
  void _onQrValue(String value) {
    if (_done) return;
    if (value.toLowerCase().startsWith('ur:')) {
      _urDecoder ??= BCURFountainDecoder();
      _urDecoder!.receivePart(value);
      setState(() {
        _isAnimated = true;
        _progress = _urDecoder!.progress;
      });
      if (_urDecoder!.isComplete) {
        _done = true;
        final data = _urDecoder!.getResult()!.decodeData() as List<int>;
        Navigator.pop(context, utf8.decode(data));
      }
    } else {
      _done = true;
      Navigator.pop(context, value);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _onQrValue(value);
  }

  Future<void> _importFromQrImage() async {
    final l10n = context.l10n;
    try {
      final result = await decodeQrFromImageFile();
      if (result != null && mounted) {
        Navigator.pop(context, result.trim());
      }
    } catch (_) {
      if (mounted) showErrorToast(context, l10n.qrNotFoundInImage);
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
        if (_isAnimated)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.black45,
              color: Colors.orange,
              minHeight: 6,
            ),
          ),
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
            : const Center(child: CircularProgressIndicator()),
        // BC-UR progress bar
        if (_isAnimated)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.black45,
              color: Colors.orange,
              minHeight: 6,
            ),
          ),
      ],
    );
  }

  Widget _buildFileFallback(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, size: 48, color: Colors.white54),
          const SizedBox(height: 12),
          Text(
            l10n.cameraError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: Text(l10n.importFromQrImage),
            onPressed: _importFromQrImage,
          ),
        ],
      ),
    );
  }
}
