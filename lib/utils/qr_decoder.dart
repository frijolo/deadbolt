import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Decodes a QR code from a raw RGB888 frame.
///
/// Returns the decoded text, or `null` if no QR code is found in the frame.
String? decodeQrFromRgbFrame(int width, int height, Uint8List rgbBytes) {
  final rawImage = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgbBytes.buffer,
    order: img.ChannelOrder.rgb,
    numChannels: 3,
  );
  final source = RGBLuminanceSource(
    width,
    height,
    rawImage
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.abgr)
        .buffer
        .asInt32List(),
  );
  try {
    return QRCodeReader()
        .decode(BinaryBitmap(GlobalHistogramBinarizer(source)))
        .text;
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

  final bytes = result.files.first.bytes;
  if (bytes == null) return null;

  final image = img.decodeImage(bytes);
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
  return qrResult.text;
}
