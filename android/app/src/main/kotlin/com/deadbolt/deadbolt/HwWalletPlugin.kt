package com.deadbolt.deadbolt

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMethodCodec

/**
 * Android platform channel for hardware wallet USB access.
 *
 * Channel name: "deadbolt/hw_wallet"
 *
 * Methods:
 *   listDevices()                     → List<Map> with keys: deviceName, productName, serialNumber
 *   requestPermission(deviceName)     → Boolean
 *   openDevice(deviceName)            → void  (opens USB HID connection)
 *   closeDevice()                     → void
 *   writeHid(data: ByteArray)         → void  (write 64-byte HID packet)
 *   readHid()                         → ByteArray (read 64-byte HID packet)
 *
 * Actual BitBox02 protocol (U2F HID framing, Noise XX, BTC operations) is
 * implemented in Rust (rust/src/core/hw/android.rs) using the above as I/O.
 */
class HwWalletPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        // BitBox02 Vendor ID (Atmel Corp., used by ShiftCrypto)
        private const val BITBOX02_VENDOR_ID = 0x03eb
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // Active USB connection state
    private var usbConnection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var endpointIn: UsbEndpoint? = null
    private var endpointOut: UsbEndpoint? = null

    // Pre-allocated read buffer — reads are serialized by the Dart dispatch loop
    // so this single buffer is never accessed concurrently.
    private val readBuf = ByteArray(64)

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        // Use a background task queue so blocking USB operations (bulkTransfer)
        // don't run on the main thread and freeze the UI.
        val taskQueue = binding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(
            binding.binaryMessenger,
            "deadbolt/hw_wallet",
            StandardMethodCodec.INSTANCE,
            taskQueue
        )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        closeActiveConnection()
    }

    // ── MethodCallHandler ─────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "listDevices" -> listDevices(result)
            "requestPermission" -> {
                val deviceName = call.argument<String>("deviceName")
                if (deviceName == null) {
                    result.error("INVALID_ARG", "deviceName is required", null)
                } else {
                    requestPermission(deviceName, result)
                }
            }
            "openDevice" -> {
                val deviceName = call.argument<String>("deviceName")
                if (deviceName == null) {
                    result.error("INVALID_ARG", "deviceName required", null)
                } else {
                    openDevice(deviceName, result)
                }
            }
            "closeDevice" -> {
                closeActiveConnection()
                result.success(null)
            }
            "drainUsbBuffer" -> {
                drainUsbBuffer()
                result.success(null)
            }
            "writeHid" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.error("INVALID_ARG", "data required", null)
                } else {
                    writeHid(data, result)
                }
            }
            "readHid" -> readHid(result)
            else -> result.notImplemented()
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun usbManager(): UsbManager =
        context.getSystemService(Context.USB_SERVICE) as UsbManager

    private fun bitboxDevices(): List<UsbDevice> =
        usbManager().deviceList.values.filter { it.vendorId == BITBOX02_VENDOR_ID }

    private fun closeActiveConnection() {
        usbInterface?.let { usbConnection?.releaseInterface(it) }
        usbConnection?.close()
        usbConnection = null
        usbInterface = null
        endpointIn = null
        endpointOut = null
    }

    // ── Methods ───────────────────────────────────────────────────────────────

    private fun listDevices(result: Result) {
        val manager = usbManager()
        val devices = bitboxDevices().map { d ->
            // serialNumber requires USB permission on API 29+; skip gracefully if not yet granted.
            val serial = if (manager.hasPermission(d)) {
                try { d.serialNumber ?: "" } catch (_: SecurityException) { "" }
            } else ""
            mapOf(
                "deviceName" to d.deviceName,
                "productName" to (d.productName ?: "BitBox02"),
                "serialNumber" to serial
            )
        }
        result.success(devices)
    }

    private fun requestPermission(deviceName: String, result: Result) {
        val manager = usbManager()
        val device = manager.deviceList[deviceName]
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device $deviceName not found", null)
            return
        }
        if (manager.hasPermission(device)) {
            result.success(true)
            return
        }
        // Request permission — result is delivered via broadcast.
        // Return false; the caller should re-try after granting permission.
        val intent = PendingIntent.getBroadcast(
            context,
            0,
            Intent("com.deadbolt.USB_PERMISSION"),
            PendingIntent.FLAG_IMMUTABLE
        )
        manager.requestPermission(device, intent)
        result.success(false)
    }

    private fun openDevice(deviceName: String, result: Result) {
        // Close any previously opened connection first
        closeActiveConnection()

        val manager = usbManager()
        val device = manager.deviceList[deviceName]
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device $deviceName not found", null)
            return
        }
        if (!manager.hasPermission(device)) {
            result.error("NO_PERMISSION", "USB permission not granted for $deviceName", null)
            return
        }

        // Find the HID interface with an interrupt IN endpoint
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == UsbConstants.USB_CLASS_HID) {
                var inEp: UsbEndpoint? = null
                var outEp: UsbEndpoint? = null
                for (j in 0 until intf.endpointCount) {
                    val ep = intf.getEndpoint(j)
                    if (ep.type == UsbConstants.USB_ENDPOINT_XFER_INT) {
                        if (ep.direction == UsbConstants.USB_DIR_IN) {
                            inEp = ep
                        } else {
                            outEp = ep
                        }
                    }
                }
                if (inEp != null) {
                    val conn = manager.openDevice(device)
                    if (conn == null) {
                        result.error("OPEN_FAILED", "Cannot open USB device $deviceName", null)
                        return
                    }
                    if (!conn.claimInterface(intf, true)) {
                        conn.close()
                        result.error("CLAIM_FAILED", "Cannot claim HID interface", null)
                        return
                    }
                    usbConnection = conn
                    usbInterface = intf
                    endpointIn = inEp
                    endpointOut = outEp
                    result.success(null)
                    return
                }
            }
        }
        result.error("NO_HID_INTERFACE", "No HID interface with interrupt endpoint found", null)
    }

    private fun writeHid(data: ByteArray, result: Result) {
        val conn = usbConnection
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open — call openDevice first", null)
            return
        }

        // Pad or truncate to exactly 64 bytes
        val packet = ByteArray(64)
        data.copyInto(packet, 0, 0, minOf(data.size, 64))

        val ep = endpointOut
        val transferred: Int
        if (ep != null) {
            // Use bulk transfer on the OUT endpoint (interrupt endpoints use bulkTransfer in Android API)
            transferred = conn.bulkTransfer(ep, packet, packet.size, 1000)
        } else {
            // Fallback: HID SET_REPORT control transfer (prepend report ID 0x00)
            val buf = ByteArray(65)
            buf[0] = 0x00 // report ID
            packet.copyInto(buf, 1, 0, 64)
            transferred = conn.controlTransfer(
                0x21,   // bmRequestType: host-to-device, class, interface
                0x09,   // bRequest: SET_REPORT
                0x0200, // wValue: report type 2 (Output), report ID 0
                0,      // wIndex: interface 0
                buf, buf.size, 1000
            )
        }

        if (transferred < 0) {
            result.error("WRITE_FAILED", "USB write failed (transferred=$transferred)", null)
            return
        }
        result.success(null)
    }

    private fun drainUsbBuffer() {
        val conn = usbConnection ?: return
        val ep = endpointIn ?: return
        // Read with a short timeout until no more stale packets remain (bulkTransfer returns < 0).
        while (conn.bulkTransfer(ep, readBuf, readBuf.size, 10) >= 0) { }
    }

    private fun readHid(result: Result) {
        val conn = usbConnection
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open — call openDevice first", null)
            return
        }
        val ep = endpointIn
        if (ep == null) {
            result.error("NO_ENDPOINT", "No interrupt IN endpoint available", null)
            return
        }

        val transferred = conn.bulkTransfer(ep, readBuf, readBuf.size, 5000)
        if (transferred < 0) {
            result.error("READ_FAILED", "USB read failed: $transferred", null)
            return
        }
        result.success(readBuf.copyOf(transferred))
    }
}
