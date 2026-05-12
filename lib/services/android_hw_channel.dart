import 'package:flutter/services.dart';

/// USB lifecycle events emitted by the Android platform channel.
sealed class HwUsbEvent {
  const HwUsbEvent();
}

/// A BitBox02 USB device was physically detached.
///
/// [deviceName] is the Android USB device name (e.g. "/dev/bus/usb/001/003").
/// [wasOpen] is true if the detached device matches the one currently open in
/// the plugin; in that case the plugin has already released the connection.
class HwUsbDetached extends HwUsbEvent {
  final String deviceName;
  final bool wasOpen;
  const HwUsbDetached({required this.deviceName, required this.wasOpen});
}

/// Dart client for the Android USB hardware wallet platform channel.
///
/// Only available on Android; calls are no-ops or throw on other platforms.
/// The BitBox02 protocol itself is implemented in Rust (android.rs); this class
/// provides the low-level USB HID I/O that Rust calls via DartFnFuture callbacks.
class AndroidHwChannel {
  static const _channel = MethodChannel('deadbolt/hw_wallet');
  static const _events = EventChannel('deadbolt/hw_wallet/events');

  /// Broadcast stream of USB lifecycle events (detach, etc.) for the BitBox02
  /// vendor. Only emits on Android; on other platforms the stream is inert.
  static Stream<HwUsbEvent> get events =>
      _events.receiveBroadcastStream().map(_parseEvent).where((e) => e != null).cast<HwUsbEvent>();

  static HwUsbEvent? _parseEvent(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.cast<Object?, Object?>();
    switch (map['type']) {
      case 'detached':
        return HwUsbDetached(
          deviceName: (map['deviceName'] as String?) ?? '',
          wasOpen: (map['wasOpen'] as bool?) ?? false,
        );
      default:
        return null;
    }
  }

  /// Returns a list of connected BitBox02 devices.
  /// Each map has keys: 'deviceName', 'productName', 'serialNumber'.
  static Future<List<Map<String, String>>> listDevices() async {
    final raw = await _channel.invokeListMethod<Map>('listDevices') ?? [];
    return raw.map((m) => m.cast<String, String>()).toList();
  }

  /// Requests USB permission for the device identified by [deviceName].
  ///
  /// Awaits the system permission broadcast on the Kotlin side and returns
  /// the final decision: `true` if granted (or already granted), `false` if
  /// denied or if the 60 s plugin-side timeout elapses without a response.
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

  /// Returns true only if the Kotlin plugin still has an open USB connection
  /// AND the originally opened device path is still present in the system
  /// device list AND we still hold USB permission. Used to detect stale
  /// sessions after a backgrounded detach/retach.
  static Future<bool> isSessionAlive() async {
    return await _channel.invokeMethod<bool>('isSessionAlive') ?? false;
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
