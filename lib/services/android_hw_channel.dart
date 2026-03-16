import 'package:flutter/services.dart';

/// Dart client for the Android USB hardware wallet platform channel.
///
/// Only available on Android; calls are no-ops or throw on other platforms.
/// The BitBox02 protocol itself is implemented in Rust (android.rs); this class
/// provides the low-level USB HID I/O that Rust calls via DartFnFuture callbacks.
class AndroidHwChannel {
  static const _channel = MethodChannel('deadbolt/hw_wallet');

  /// Returns a list of connected BitBox02 devices.
  /// Each map has keys: 'deviceName', 'productName', 'serialNumber'.
  static Future<List<Map<String, String>>> listDevices() async {
    final raw = await _channel.invokeListMethod<Map>('listDevices') ?? [];
    return raw.map((m) => m.cast<String, String>()).toList();
  }

  /// Requests USB permission for the device identified by [deviceName].
  /// Returns true when permission is already granted, false when the
  /// permission dialog has been shown (call again after the user grants it).
  static Future<bool> requestPermission(String deviceName) async {
    final granted = await _channel.invokeMethod<bool>(
          'requestPermission',
          {'deviceName': deviceName},
        ) ??
        false;
    return granted;
  }

  /// Opens the USB device and claims the HID interface.
  ///
  /// Must be called before [writePacket] / [readPacket].
  /// The connection stays open until [closeDevice] is called.
  static Future<void> openDevice(String deviceName) async {
    await _channel.invokeMethod<void>('openDevice', {'deviceName': deviceName});
  }

  /// Closes the previously opened USB device connection.
  static Future<void> closeDevice() async {
    await _channel.invokeMethod<void>('closeDevice');
  }

  /// Drains any stale USB HID packets buffered from a previous session.
  /// Call this after [openDevice] before starting a new protocol handshake.
  static Future<void> drainUsbBuffer() async {
    await _channel.invokeMethod<void>('drainUsbBuffer');
  }

  /// Writes a 64-byte HID packet to the device.
  ///
  /// [packet] must be exactly 64 bytes. Shorter buffers are zero-padded by
  /// the Kotlin layer; longer buffers are truncated.
  static Future<void> writePacket(Uint8List packet) async {
    await _channel.invokeMethod<void>('writeHid', {'data': packet});
  }

  /// Reads a 64-byte HID packet from the device.
  ///
  /// Blocks (with a 5-second timeout on the Kotlin side) until a packet
  /// arrives. Throws [PlatformException] on error.
  static Future<Uint8List> readPacket() async {
    final data = await _channel.invokeMethod<Uint8List>('readHid');
    if (data == null) throw PlatformException(code: 'READ_FAILED', message: 'No data returned');
    return data;
  }
}
