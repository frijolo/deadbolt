package com.deadbolt.deadbolt

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMethodCodec
import java.util.concurrent.atomic.AtomicBoolean

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
        private const val ACTION_USB_PERMISSION = "com.deadbolt.USB_PERMISSION"
        private const val PERMISSION_TIMEOUT_MS = 60_000L
    }

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private val mainHandler = Handler(Looper.getMainLooper())

    // Event sink for USB lifecycle notifications (attach/detach).
    // Always touched on the main thread.
    private var eventSink: EventChannel.EventSink? = null

    // Last detach event seen while no listener was attached. Replayed on the
    // next onListen so a detach that happened while Flutter was backgrounded
    // (and the EventChannel had no sink) is not silently lost.
    private var pendingDetachEvent: Map<String, Any>? = null

    // Active USB connection state. Guarded by [usbLock] for mutation; reads
    // happen from both the Flutter task queue (USB ops) and the main thread
    // (detach receiver), so the lock is needed even on what looks like a
    // simple field read sequence.
    private val usbLock = Any()
    private var usbConnection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var endpointIn: UsbEndpoint? = null
    private var endpointOut: UsbEndpoint? = null
    // Name of the device currently open (or last opened). Used to decide
    // whether a detach event affects "our" device.
    private var openDeviceName: String? = null

    // Cooperative cancellation flag for the [readHid] poll loop. Tripped by
    // [closeActiveConnection] (detach handler, explicit close, or open of a
    // new device) so the in-flight read returns READ_CANCELED quickly even
    // though each [bulkTransfer] call uses a short timeout.
    private val readCanceled = AtomicBoolean(false)

    // Pre-allocated read buffer — reads are serialized by the single-threaded
    // Flutter task queue so this single buffer is never accessed concurrently.
    private val readBuf = ByteArray(64)

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_DETACHED -> handleDetach(intent)
                ACTION_USB_PERMISSION -> handlePermissionBroadcast(intent)
            }
        }
    }

    /// Pending permission requests keyed by USB device name. Access via
    /// [pendingPermLock]. Each entry also has a main-thread timeout runnable
    /// queued on [mainHandler] so the caller is never left hanging.
    private val pendingPermLock = Any()
    private val pendingPermissions = HashMap<String, PendingPermission>()

    private class PendingPermission(
        val result: Result,
        val timeout: Runnable,
    )

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

        eventChannel = EventChannel(binding.binaryMessenger, "deadbolt/hw_wallet/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // Replay a detach observed while no listener was attached so
                // backgrounded detach/retach cycles don't strand Dart with a
                // stale session.
                val pending = pendingDetachEvent
                if (pending != null && events != null) {
                    pendingDetachEvent = null
                    mainHandler.post { events.success(pending) }
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_USB_PERMISSION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.registerReceiver(
                context, usbReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(usbReceiver, filter)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        try {
            context.unregisterReceiver(usbReceiver)
        } catch (_: IllegalArgumentException) {
            // Already unregistered — ignore.
        }
        // Drain any in-flight permission requests so callers don't hang.
        val pending: List<PendingPermission>
        synchronized(pendingPermLock) {
            pending = pendingPermissions.values.toList()
            pendingPermissions.clear()
        }
        for (p in pending) {
            mainHandler.removeCallbacks(p.timeout)
            mainHandler.post { p.result.success(false) }
        }
        eventSink = null
        closeActiveConnection()
    }

    // ── USB lifecycle events ──────────────────────────────────────────────────

    private fun handleDetach(intent: Intent) {
        val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
        if (device == null || device.vendorId != BITBOX02_VENDOR_ID) return

        val wasOurs = openDeviceName != null && openDeviceName == device.deviceName
        if (wasOurs) {
            closeActiveConnection()
        }

        val payload = mapOf(
            "type" to "detached",
            "deviceName" to device.deviceName,
            "vendorId" to device.vendorId,
            "wasOpen" to wasOurs,
        )
        mainHandler.post {
            val sink = eventSink
            if (sink != null) {
                sink.success(payload)
            } else {
                pendingDetachEvent = payload
            }
        }
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
            "isSessionAlive" -> result.success(isSessionAlive())
            else -> result.notImplemented()
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun usbManager(): UsbManager =
        context.getSystemService(Context.USB_SERVICE) as UsbManager

    private fun bitboxDevices(): List<UsbDevice> =
        usbManager().deviceList.values.filter { it.vendorId == BITBOX02_VENDOR_ID }

    /// Liveness probe for the cached session.
    ///
    /// Returns true only when every component of the session is still valid:
    /// the connection is open, the original USB device path is still in the
    /// device list (a detach/retach gives a new path even for the same
    /// physical device), and we still hold USB permission. Used on app
    /// foreground resume to detect backgrounded detach/retach cycles that
    /// would otherwise leave Dart with a stale session.
    private fun isSessionAlive(): Boolean = synchronized(usbLock) {
        val name = openDeviceName ?: return@synchronized false
        if (usbConnection == null) return@synchronized false
        val device = usbManager().deviceList[name] ?: return@synchronized false
        usbManager().hasPermission(device)
    }

    /// Tears down the active USB connection.
    ///
    /// Trips [readCanceled] *before* taking [usbLock] so a `readHid` blocked on
    /// `bulkTransfer` will see the flag at its next iteration and return
    /// READ_CANCELED — without this, close would serialise behind an in-flight
    /// read and we'd have to wait for the full 250 ms timeout.
    private fun closeActiveConnection() {
        readCanceled.set(true)
        synchronized(usbLock) {
            usbInterface?.let { usbConnection?.releaseInterface(it) }
            usbConnection?.close()
            usbConnection = null
            usbInterface = null
            endpointIn = null
            endpointOut = null
            openDeviceName = null
        }
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

        // Replace any prior pending request for the same device with this one.
        val previous: PendingPermission?
        val timeoutRunnable = Runnable {
            val expired: PendingPermission?
            synchronized(pendingPermLock) {
                expired = pendingPermissions.remove(deviceName)
            }
            if (expired != null) {
                expired.result.success(false)
            }
        }
        synchronized(pendingPermLock) {
            previous = pendingPermissions.put(
                deviceName,
                PendingPermission(result, timeoutRunnable),
            )
        }
        if (previous != null) {
            mainHandler.removeCallbacks(previous.timeout)
            mainHandler.post { previous.result.success(false) }
        }
        mainHandler.postDelayed(timeoutRunnable, PERMISSION_TIMEOUT_MS)

        // Explicit, package-scoped broadcast so Android 14+ delivers it back to us.
        val intent = Intent(ACTION_USB_PERMISSION).setPackage(context.packageName)
        val pi = PendingIntent.getBroadcast(
            context,
            deviceName.hashCode(),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        manager.requestPermission(device, pi)
        // Result is delivered asynchronously from handlePermissionBroadcast.
    }

    private fun handlePermissionBroadcast(intent: Intent) {
        val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
        val deviceName = device?.deviceName ?: return
        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)

        val pending: PendingPermission?
        synchronized(pendingPermLock) {
            pending = pendingPermissions.remove(deviceName)
        }
        if (pending != null) {
            mainHandler.removeCallbacks(pending.timeout)
            pending.result.success(granted)
        }
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
                    synchronized(usbLock) {
                        usbConnection = conn
                        usbInterface = intf
                        endpointIn = inEp
                        endpointOut = outEp
                        openDeviceName = deviceName
                    }
                    // Fresh session — clear any stale cancellation from a prior open.
                    readCanceled.set(false)
                    result.success(null)
                    return
                }
            }
        }
        result.error("NO_HID_INTERFACE", "No HID interface with interrupt endpoint found", null)
    }

    private fun writeHid(data: ByteArray, result: Result) {
        val conn: UsbDeviceConnection
        val ep: UsbEndpoint?
        synchronized(usbLock) {
            val c = usbConnection
            if (c == null) {
                result.error("NOT_OPEN", "Device not open — call openDevice first", null)
                return
            }
            conn = c
            ep = endpointOut
        }

        // Pad or truncate to exactly 64 bytes
        val packet = ByteArray(64)
        data.copyInto(packet, 0, 0, minOf(data.size, 64))

        val transferred: Int = if (ep != null) {
            // Use bulk transfer on the OUT endpoint (interrupt endpoints use bulkTransfer in Android API)
            conn.bulkTransfer(ep, packet, packet.size, 1000)
        } else {
            // Fallback: HID SET_REPORT control transfer (prepend report ID 0x00)
            val buf = ByteArray(65)
            buf[0] = 0x00 // report ID
            packet.copyInto(buf, 1, 0, 64)
            conn.controlTransfer(
                0x21,   // bmRequestType: host-to-device, class, interface
                0x09,   // bRequest: SET_REPORT
                0x0200, // wValue: report type 2 (Output), report ID 0
                0,      // wIndex: interface 0
                buf, buf.size, 1000
            )
        }

        if (transferred < 0) {
            // Distinguish detach (connection was nulled by the receiver) from a
            // generic write failure so Dart can drop the session cleanly.
            val stillOpen = synchronized(usbLock) { usbConnection != null }
            if (!stillOpen) {
                result.error("DEVICE_DETACHED", "Hardware wallet disconnected", null)
            } else {
                result.error("WRITE_FAILED", "USB write failed (transferred=$transferred)", null)
            }
            return
        }
        result.success(null)
    }

    private fun drainUsbBuffer() {
        val conn: UsbDeviceConnection
        val ep: UsbEndpoint
        synchronized(usbLock) {
            conn = usbConnection ?: return
            ep = endpointIn ?: return
        }
        // Read with a short timeout until no more stale packets remain (bulkTransfer returns < 0).
        while (conn.bulkTransfer(ep, readBuf, readBuf.size, 10) >= 0) { }
    }

    /// Reads one 64-byte HID packet, polling in short bursts so detach /
    /// explicit cancellation surfaces within ~250 ms.
    ///
    /// The BitBox02 firmware can take 30+ seconds to respond to `wait_confirm`
    /// (button press on the device). A single long `bulkTransfer` would block
    /// the worker thread for that whole window, so detach mid-operation would
    /// be invisible to Dart until the timeout expired. Instead we loop on
    /// short reads and check three exit conditions each iteration:
    ///   - data arrived             → return the bytes
    ///   - [readCanceled] tripped   → return READ_CANCELED
    ///   - connection went away     → return DEVICE_DETACHED
    private fun readHid(result: Result) {
        val conn: UsbDeviceConnection
        val ep: UsbEndpoint
        synchronized(usbLock) {
            val c = usbConnection
            if (c == null) {
                result.error("NOT_OPEN", "Device not open — call openDevice first", null)
                return
            }
            val e = endpointIn
            if (e == null) {
                result.error("NO_ENDPOINT", "No interrupt IN endpoint available", null)
                return
            }
            conn = c
            ep = e
        }

        while (true) {
            if (readCanceled.get()) {
                result.error("READ_CANCELED", "USB read canceled", null)
                return
            }
            // The connection may have been closed by the detach receiver in
            // between iterations. `bulkTransfer` on a closed fd returns -1, so
            // we'd otherwise loop forever; this short-circuits earlier.
            val stillOpen = synchronized(usbLock) { usbConnection != null }
            if (!stillOpen) {
                result.error("DEVICE_DETACHED", "Hardware wallet disconnected", null)
                return
            }

            val transferred = conn.bulkTransfer(ep, readBuf, readBuf.size, 250)
            if (transferred > 0) {
                result.success(readBuf.copyOf(transferred))
                return
            }
            // transferred <= 0: either timeout (loop) or transport error (loop
            // and let the cancel/detach checks above handle it on the next pass).
        }
    }
}
