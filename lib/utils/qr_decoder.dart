import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'package:deadbolt/utils/seed_qr.dart';

/// Result of decoding a QR code from a camera frame.
class QrDecodeResult {
  final String text;

  /// Raw payload bytes as unsigned bytes — populated for binary-mode QR codes.
  final Uint8List? rawBytes;

  const QrDecodeResult(this.text, {this.rawBytes});
}

/// Decodes a QR code from a raw RGB888 frame.
///
/// Returns the decoded result, or `null` if no QR code is found in the frame.
QrDecodeResult? decodeQrFromRgbFrame(int width, int height, Uint8List rgbBytes) {
  // Build the ARGB Int32List that RGBLuminanceSource expects directly from the
  // RGB888 bytes — avoids creating two full-image intermediate buffers via the
  // img library. RGBLuminanceSource expects each Int32 to encode the pixel as
  // ABGR bytes in little-endian order, i.e. Int32 = R<<24 | G<<16 | B<<8 | A.
  final argb = Int32List(width * height);
  for (int i = 0; i < width * height; i++) {
    final src = i * 3;
    argb[i] = (rgbBytes[src] << 24) |
        (rgbBytes[src + 1] << 16) |
        (rgbBytes[src + 2] << 8) |
        0xFF;
  }
  final source = RGBLuminanceSource(width, height, argb);
  try {
    final result = QRCodeReader()
        .decode(BinaryBitmap(GlobalHistogramBinarizer(source)));
    // zxing2 rawBytes is the full QR bit stream (mode + count + data +
    // terminator), not the bare payload. Extract just the data bytes.
    final rawBytes = _extractQrBytePayload(result.rawBytes);
    return QrDecodeResult(result.text, rawBytes: rawBytes);
  } catch (_) {
    return null; // NotFoundException — no QR in frame
  }
}

/// Prompts the user to select an image file, then attempts to decode a QR code
/// from it using zxing2 (pure Dart — works on all platforms including Linux).
///
/// Returns the decoded text, or `null` if the user cancelled the file picker.
/// Throws if an image was selected but no QR code could be decoded.
Future<String?> decodeQrFromImageFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final fileBytes = result.files.first.bytes;
  if (fileBytes == null) return null;

  final image = img.decodeImage(fileBytes);
  if (image == null) throw Exception('Could not decode image');

  final source = RGBLuminanceSource(
    image.width,
    image.height,
    image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.abgr)
        .buffer
        .asInt32List(),
  );

  final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
  final reader = QRCodeReader();
  // Throws NotFoundException if no QR code is found.
  final qrResult = reader.decode(bitmap);

  // Compact SeedQR: binary QR whose payload is raw entropy bytes.
  final payload = _extractQrBytePayload(qrResult.rawBytes);
  if (payload != null) {
    final mnemonic = decodeSeedQrCompact(payload);
    if (mnemonic != null) return mnemonic;
  }

  return qrResult.text;
}

/// Parses the zxing2 raw QR bit stream and returns the data payload for
/// byte-mode (mode = 0100) QR codes.
///
/// zxing2 rawBytes contains: 4-bit mode indicator + 8-bit character count
/// (for versions 1–9) + data bytes + terminator/padding.
/// This function strips the 12-bit header and returns only the data bytes.
///
/// Returns null if the input is null, not byte-mode, or too short.
Uint8List? _extractQrBytePayload(List<int>? rawBits) {
  if (rawBits == null || rawBits.length < 2) return null;

  final b0 = rawBits[0] & 0xFF;
  final b1 = rawBits[1] & 0xFF;

  // Mode indicator: first 4 bits. Byte mode = 0100 = 4.
  if ((b0 >> 4) != 4) return null;

  // Character count: bits 4–11 (8 bits, covers QR versions 1–9).
  final count = ((b0 & 0xF) << 4) | (b1 >> 4);
  if (count == 0) return null;

  // Verify there are enough bits: 12 header + count * 8 data.
  if (rawBits.length * 8 < 12 + count * 8) return null;

  // Extract 'count' bytes starting at bit offset 12.
  final data = Uint8List(count);
  for (int i = 0; i < count; i++) {
    final bitStart = 12 + i * 8;
    final idx = bitStart >> 3;
    final shift = bitStart & 7;
    final hi = rawBits[idx] & 0xFF;
    final lo = (idx + 1 < rawBits.length) ? (rawBits[idx + 1] & 0xFF) : 0;
    data[i] = shift == 0 ? hi : ((hi << shift) | (lo >> (8 - shift))) & 0xFF;
  }
  return data;
}
