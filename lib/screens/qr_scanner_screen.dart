import 'dart:convert';

import 'package:bc_ur/bc_ur.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:deadbolt/l10n/l10n.dart';

/// Full-screen QR code scanner.
///
/// Handles both plain-text QR codes and animated ur:bytes (BC-UR fountain codes).
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
  BCURFountainDecoder? _urDecoder;
  double _progress = 0;
  bool _isAnimated = false;
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;

    if (value.toLowerCase().startsWith('ur:')) {
      // Animated BC-UR — accumulate parts until complete.
      _urDecoder ??= BCURFountainDecoder();
      _urDecoder!.receivePart(value);
      final p = _urDecoder!.progress;
      setState(() {
        _isAnimated = true;
        _progress = p;
      });
      if (_urDecoder!.isComplete) {
        _done = true;
        final bcur = _urDecoder!.getResult()!;
        final data = bcur.decodeData() as List<int>;
        final text = utf8.decode(data);
        Navigator.pop(context, text);
      }
    } else {
      // Plain-text QR — return immediately.
      _done = true;
      Navigator.pop(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanQrCode)),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
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
      ),
    );
  }
}
