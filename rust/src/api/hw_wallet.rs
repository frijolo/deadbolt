/// FFI-exposed hardware wallet API.
///
/// Supports BitBox02 via USB HID on Linux/desktop (via async-hwi + bitbox-api)
/// and on Android (via custom Noise XX + BTC protocol using tokio channels for I/O).
///
/// # Pairing flow (Linux)
/// 1. `list_hw_devices()` → choose a device path
/// 2. `connect_hw_device(device_path, noise_dir)` → `(session_id, pairing_code?)`
/// 3. If `pairing_code` is Some: show code in UI, then `wait_hw_pairing(session_id)`
/// 4. Use `hw_sign_psbt`, `hw_get_xpub`, or `hw_register_descriptor`
/// 5. `hw_disconnect(session_id)` when done
///
/// # Pairing flow (Android)
/// 1. `AndroidHwChannel.listDevices()` (Kotlin) → choose a deviceName
/// 2. Start dispatch loop (Dart side) polling `android_hw_poll_write_packet` and
///    delivering USB reads via `android_hw_deliver_read_packet`
/// 3. Call `connect_hw_device_android(deviceName, noiseDir, productString)`
/// 4. If `pairing_code` is Some: show code in UI, then `wait_hw_pairing_android(sessionId)`
/// 5. Use `hw_sign_psbt_android`, `hw_get_xpub_android`, or `hw_register_descriptor_android`
/// 6. `hw_disconnect(session_id)` when done
use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIHwConnectResult, APIHwDevice, APIHwSessionInfo, APIKeychain, APINetwork,
};
use crate::core::hw;

// ── Shared sync-FFI runtime ───────────────────────────────────────────────────

/// Single-threaded tokio runtime reused by all `#[frb(sync)]` functions.
///
/// `Handle::try_current()` succeeds only when called from inside a tokio task.
/// The `#[frb(sync)]` functions run on the Dart main thread (outside tokio), so
/// they always hit the `Err` branch. Building a new runtime on every call is
/// expensive; this lazily-initialized one is created once and reused.
fn sync_rt() -> &'static tokio::runtime::Runtime {
    static RT: std::sync::OnceLock<tokio::runtime::Runtime> = std::sync::OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .expect("sync HW runtime init failed")
    })
}

// ── Session guard macro ───────────────────────────────────────────────────────

/// Acquires the connected-session lock, asserts that a session is active, and
/// checks that its ID matches `$session_id`. On success, binds:
///   - `$guard`: the `MutexGuard` (must stay alive to keep `$session` valid).
///   - `$session`: `&mut ConnectedSession`.
///
/// Returns an `Err` early if no device is connected or the ID is wrong.
macro_rules! session_guard {
    ($guard:ident, $session:ident, $session_id:expr) => {
        let mut $guard = hw::connected_lock().lock().await;
        let $session = $guard
            .as_mut()
            .ok_or_else(|| anyhow!("No HW device connected"))?;
        if $session.session_id != $session_id {
            return Err(anyhow!("Session not found: {}", $session_id));
        }
    };
}

// ── Device enumeration ────────────────────────────────────────────────────────

/// Returns all BitBox02 devices currently connected via USB HID.
/// Always empty on Android — enumerate via the `deadbolt/hw_wallet` channel.
#[frb(sync)]
pub fn list_hw_devices() -> Vec<APIHwDevice> {
    hw::list_bitbox02_devices()
        .into_iter()
        .map(|(device_path, product_string, serial_number)| APIHwDevice {
            device_path,
            product_string,
            serial_number,
        })
        .collect()
}

// ── Session info ──────────────────────────────────────────────────────────────

/// Returns the product string and root fingerprint for an active session.
/// Used by the Dart layer after a successful connect/confirm.
#[frb(sync)]
pub fn get_hw_session_info(session_id: String) -> Result<APIHwSessionInfo> {
    async fn inner(session_id: String) -> Result<APIHwSessionInfo> {
        let lock = hw::connected_lock().lock().await;
        match lock.as_ref() {
            Some(s) if s.session_id == session_id => Ok(session_info_from(s)),
            _ => Err(anyhow!("Session not found: {session_id}")),
        }
    }
    match tokio::runtime::Handle::try_current() {
        Ok(handle) => handle.block_on(inner(session_id)),
        Err(_) => sync_rt().block_on(inner(session_id)),
    }
}

/// Returns session info for the currently active hardware wallet session,
/// or `None` if no device is connected. Does not require a session ID.
///
/// Use this to check connection status and pre-populate session state
/// without holding a prior session ID (e.g. when the app restores state).
#[frb(sync)]
pub fn hw_active_session() -> Option<APIHwSessionInfo> {
    async fn inner() -> Option<APIHwSessionInfo> {
        hw::connected_lock()
            .lock()
            .await
            .as_ref()
            .map(session_info_from)
    }
    match tokio::runtime::Handle::try_current() {
        Ok(handle) => handle.block_on(inner()),
        Err(_) => sync_rt().block_on(inner()),
    }
}

fn session_info_from(s: &hw::ConnectedSession) -> APIHwSessionInfo {
    APIHwSessionInfo {
        session_id: s.session_id.clone(),
        product_string: s.product_string.clone(),
        root_fingerprint: s.root_fingerprint.clone(),
    }
}

// ── Connection & pairing (desktop) ────────────────────────────────────────────

/// Opens a USB connection to the device at `device_path` and starts the Noise
/// pairing handshake.
///
/// `noise_dir` is the directory for persisting pairing data
/// (`<appSupportDir>/hw_pairing`). Created if absent.
///
/// Returns `APIHwConnectResult`:
/// - `pairing_code = None`  → already paired, ready immediately.
/// - `pairing_code = Some(c)` → show `c`, call `wait_hw_pairing`.
pub async fn connect_hw_device(
    device_path: String,
    noise_dir: String,
) -> Result<APIHwConnectResult> {
    #[cfg(not(target_os = "android"))]
    {
        // Drop any existing session so the HID connection is released before
        // we try to open the device again (otherwise open_path returns "busy").
        *hw::connected_lock().lock().await = None;

        let product_string = hw::list_bitbox02_devices()
            .into_iter()
            .find(|(p, _, _)| p == &device_path)
            .map(|(_, prod, _)| prod)
            .unwrap_or_else(|| "BitBox02".to_string());

        let (session_id, pairing_code) =
            hw::start_pairing(&device_path, &noise_dir, product_string).await?;

        Ok(APIHwConnectResult {
            session_id,
            pairing_code,
        })
    }
    #[cfg(target_os = "android")]
    {
        let _ = (device_path, noise_dir);
        Err(anyhow!("Use connectHwDeviceAndroid on Android"))
    }
}

/// Waits for the user to confirm the pairing code on the device (desktop).
/// Only needed when `connect_hw_device` returned `pairing_code = Some(...)`.
pub async fn wait_hw_pairing(session_id: String) -> Result<()> {
    #[cfg(not(target_os = "android"))]
    {
        hw::wait_pairing_confirm(&session_id).await
    }
    #[cfg(target_os = "android")]
    {
        let _ = session_id;
        Err(anyhow!("Use waitHwPairingAndroid on Android"))
    }
}

// ── Android USB I/O dispatch ──────────────────────────────────────────────────

/// Android: deliver a USB HID packet received from the device to Rust.
///
/// Dart calls this after reading each 64-byte HID packet from USB, as part of
/// the dispatch loop that drives the Rust protocol state machine.
pub async fn android_hw_deliver_read_packet(data: Vec<u8>) -> Result<()> {
    #[cfg(target_os = "android")]
    {
        hw::android::deliver_read_packet(data).await
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = data;
        Err(anyhow!("androidHwDeliverReadPacket is Android-only"))
    }
}

/// Android: retrieve the next USB HID packet Rust wants to write.
///
/// Returns:
/// - `Some(packet)` — Dart must write this 64-byte packet to USB.
/// - `None` — no packet ready yet; Dart should call this again after a short delay.
///
/// Dart drives this in a loop while a protocol operation is in progress.
pub async fn android_hw_poll_write_packet() -> Option<Vec<u8>> {
    #[cfg(target_os = "android")]
    {
        hw::android::poll_write_packet().await
    }
    #[cfg(not(target_os = "android"))]
    {
        None
    }
}

// ── Connection & pairing (Android) ───────────────────────────────────────────

/// Android: connect to a BitBox02 via USB HID and run the Noise XX handshake.
///
/// USB I/O is handled via the dispatch loop: Dart polls
/// `android_hw_poll_write_packet` for packets to write, and delivers received
/// packets via `android_hw_deliver_read_packet`.
///
/// `device_name` is the Android USB device name (e.g. "/dev/bus/usb/001/003").
/// `noise_dir` is the directory for persisting pairing data.
/// `product_string` is the human-readable device name shown to the user.
///
/// Returns `APIHwConnectResult`:
/// - `pairing_code = None`   → already paired, device ready immediately.
/// - `pairing_code = Some(c)` → show code, call `wait_hw_pairing_android`.
pub async fn connect_hw_device_android(
    device_name: String,
    noise_dir: String,
    product_string: String,
) -> Result<APIHwConnectResult> {
    #[cfg(target_os = "android")]
    {
        // Drop any existing Rust session before establishing a new one.
        *hw::connected_lock().lock().await = None;

        let (session_id, pairing_code) =
            hw::android::connect(device_name, noise_dir, product_string).await?;
        Ok(APIHwConnectResult {
            session_id,
            pairing_code,
        })
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = (device_name, noise_dir, product_string);
        Err(anyhow!("connectHwDeviceAndroid is Android-only"))
    }
}

/// Android: wait for the user to confirm the pairing code on the device.
/// Only needed when `connectHwDeviceAndroid` returned `pairing_code = Some(...)`.
pub async fn wait_hw_pairing_android(session_id: String) -> Result<()> {
    #[cfg(target_os = "android")]
    {
        hw::android::wait_confirm(&session_id).await
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = session_id;
        Err(anyhow!("waitHwPairingAndroid is Android-only"))
    }
}

// ── Disconnect ────────────────────────────────────────────────────────────────

/// Disconnects the hardware wallet session and releases all resources.
#[frb(sync)]
pub fn hw_disconnect(session_id: String) -> Result<()> {
    match tokio::runtime::Handle::try_current() {
        Ok(handle) => handle.block_on(hw::disconnect(&session_id))?,
        Err(_) => sync_rt().block_on(hw::disconnect(&session_id))?,
    }
    Ok(())
}

// ── xpub export ───────────────────────────────────────────────────────────────

/// Exports the extended public key at `derivation_path` from the connected device (desktop).
///
/// Returns a descriptor-ready key, e.g. `[aabbccdd/48'/0'/0'/2']xpubXXX...`.
/// `derivation_path` must be a standard BIP-32 path like `"m/48'/0'/0'/2'"`.
pub async fn hw_get_xpub(
    session_id: String,
    derivation_path: String,
    network: APINetwork,
) -> Result<String> {
    session_guard!(guard, session, session_id);
    hw::btc_get_xpub(session, &derivation_path, network).await
}

// ── Descriptor registration ───────────────────────────────────────────────────

/// Registers a descriptor/policy with the connected BitBox02.
///
/// Returns `true` if newly registered, `false` if already registered.
pub async fn hw_register_descriptor(
    session_id: String,
    wallet_name: String,
    policy: String,
    network: APINetwork,
) -> Result<bool> {
    session_guard!(guard, session, session_id);
    hw::btc_register_descriptor(session, &wallet_name, &policy, network).await
}

// ── Registration check ────────────────────────────────────────────────────────

/// Checks whether a descriptor/policy is already registered on the device.
/// Returns `true` if registered, `false` if not.
pub async fn hw_check_registration(
    session_id: String,
    descriptor: String,
    network: APINetwork,
) -> Result<bool> {
    session_guard!(guard, session, session_id);
    hw::btc_check_registration(session, &descriptor, network).await
}

// ── PSBT signing ──────────────────────────────────────────────────────────────

/// Signs a PSBT with the connected BitBox02.
///
/// `descriptor` — the wallet descriptor for policy wallets (multisig, taproot
/// script-path). Required so the firmware can identify the registered policy.
/// Pass `None` for simple single-key wallets.
pub async fn hw_sign_psbt(
    session_id: String,
    psbt_base64: String,
    network: APINetwork,
    descriptor: Option<String>,
) -> Result<String> {
    session_guard!(guard, session, session_id);
    hw::btc_sign_psbt(session, &psbt_base64, network, descriptor.as_deref()).await
}

// ── Address display ────────────────────────────────────────────────────────────

/// Shows an address on the BitBox02 screen so the user can verify it matches
/// the address displayed in the app.
///
/// `keychain`: External (receive) or Internal (change).
/// `index`: the address index within the chain.
///
/// Supports P2WPKH, P2SH-P2WPKH, single-key P2TR, and policy wallets.
/// The device firmware will display the address and wait for the user to
/// confirm or reject it.
pub async fn hw_display_address(
    session_id: String,
    descriptor: String,
    network: APINetwork,
    keychain: APIKeychain,
    index: u32,
) -> Result<()> {
    session_guard!(guard, session, session_id);
    let chain = match keychain {
        APIKeychain::External => 0,
        APIKeychain::Internal => 1,
    };
    hw::btc_display_address(session, &descriptor, network, chain, index).await
}
