/// Core hardware wallet session management.
///
/// Both platforms produce a `PairedBitBox` via their respective transport:
///   - Desktop:  USB HID via `bitbox-api` + `hidapi` (`start_pairing`).
///   - Android:  Dart channel dispatch loop (`android.rs`).
///
/// `finish_connection` wraps the `PairedBitBox` in `async_hwi::bitbox::BitBox02<T>`,
/// giving a single, platform-agnostic object for all BTC operations.
use std::sync::OnceLock;

use anyhow::{anyhow, Result};
use tokio::sync::Mutex as TokioMutex;

/// Privacy-sensitive HW diagnostics (xpubs, fingerprints, derivation paths).
/// Stripped from release builds; only emitted when `debug_assertions` is on.
macro_rules! hw_debug {
    ($($arg:tt)*) => {{
        #[cfg(debug_assertions)]
        eprintln!($($arg)*);
    }};
}

// ── Platform modules ──────────────────────────────────────────────────────────

#[cfg(target_os = "android")]
pub mod android;

// ── Types ─────────────────────────────────────────────────────────────────────

type BB02Runtime = bitbox_api::runtime::TokioRuntime;
type BB02Device = async_hwi::bitbox::BitBox02<BB02Runtime>;

/// Intermediate state while waiting for the user to confirm the pairing code (desktop).
#[cfg(not(target_os = "android"))]
struct PairingSession {
    session_id: String,
    device_path: String,
    product_string: String,
    pairing: bitbox_api::PairingBitBox<BB02Runtime>,
}

/// A fully paired, ready-to-use device session (all platforms).
pub struct ConnectedSession {
    pub session_id: String,
    pub device_path: String,
    pub product_string: String,
    /// Root fingerprint (lowercase hex, 8 chars), e.g. "aabbccdd".
    pub root_fingerprint: String,
    /// async-hwi BitBox02 wrapper — same type on all platforms.
    pub(crate) device: BB02Device,
}

// ── Global session storage ────────────────────────────────────────────────────

#[cfg(not(target_os = "android"))]
static PAIRING: OnceLock<TokioMutex<Option<PairingSession>>> = OnceLock::new();

static CONNECTED: OnceLock<TokioMutex<Option<ConnectedSession>>> = OnceLock::new();

#[cfg(not(target_os = "android"))]
fn pairing_lock() -> &'static TokioMutex<Option<PairingSession>> {
    PAIRING.get_or_init(|| TokioMutex::new(None))
}

pub fn connected_lock() -> &'static TokioMutex<Option<ConnectedSession>> {
    CONNECTED.get_or_init(|| TokioMutex::new(None))
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Generates a short random session ID (16-char lowercase hex).
pub fn new_session_id() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 8];
    rand::rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Creates a device-scoped NoiseConfig directory and returns the config.
///
/// Derives `safe_key` from `device_identifier` via hex encoding, creates
/// `{noise_dir}/{safe_key}`, and constructs a [`bitbox_api::PersistedNoiseConfig`]
/// backed by that directory.
///
/// Shared by desktop [`start_pairing`] and Android [`android::connect`].
pub fn create_noise_config(
    device_identifier: &str,
    noise_dir: &str,
) -> Result<Box<bitbox_api::PersistedNoiseConfig>> {
    let safe_key = hex::encode(device_identifier.as_bytes());
    let device_noise_dir = format!("{noise_dir}/{safe_key}");
    std::fs::create_dir_all(&device_noise_dir)?;
    Ok(Box::new(bitbox_api::PersistedNoiseConfig::new(
        &device_noise_dir,
    )))
}

// ── Device enumeration ────────────────────────────────────────────────────────

/// Returns info for every BitBox02 currently reachable via USB HID.
/// Always empty on Android (handled by the Kotlin platform channel).
pub fn list_bitbox02_devices() -> Vec<(String, String, String)> {
    #[cfg(not(target_os = "android"))]
    {
        let api = match hidapi::HidApi::new() {
            Ok(a) => a,
            Err(_) => return vec![],
        };
        api.device_list()
            .filter(|d| bitbox_api::usb::is_bitbox02(d))
            .map(|d| {
                let path = d.path().to_string_lossy().to_string();
                let product = d.product_string().unwrap_or("BitBox02").to_string();
                let serial = d.serial_number().unwrap_or("").to_string();
                (path, product, serial)
            })
            .collect()
    }
    #[cfg(target_os = "android")]
    {
        vec![]
    }
}

// ── Pairing flow (desktop) ────────────────────────────────────────────────────

/// Starts the USB connection + Noise handshake.
///
/// Returns `(session_id, pairing_code)`:
/// - `pairing_code = None`    → device already trusted, immediately ready.
/// - `pairing_code = Some(c)` → show `c` to the user, call [`wait_pairing_confirm`].
#[cfg(not(target_os = "android"))]
pub async fn start_pairing(
    device_path: &str,
    noise_dir: &str,
    product_string: String,
) -> Result<(String, Option<String>)> {
    let api = hidapi::HidApi::new().map_err(|e| anyhow!("HID init failed: {e}"))?;
    let hid_device = api
        .open_path(std::ffi::CString::new(device_path)?.as_c_str())
        .map_err(|e| anyhow!("Cannot open device at {device_path}: {e}"))?;

    let noise_config = create_noise_config(device_path, noise_dir)?;

    let bitbox = bitbox_api::BitBox::<BB02Runtime>::from_hid_device(hid_device, noise_config)
        .await
        .map_err(|e| anyhow!("BitBox02 handshake failed: {e}"))?;

    let pairing = bitbox
        .unlock_and_pair()
        .await
        .map_err(|e| anyhow!("BitBox02 unlock failed: {e}"))?;

    let pairing_code = pairing.get_pairing_code().clone();
    let session_id = new_session_id();

    if pairing_code.is_none() {
        let paired = pairing
            .wait_confirm()
            .await
            .map_err(|e| anyhow!("BitBox02 confirm failed: {e}"))?;
        finish_connection(
            session_id.clone(),
            device_path.to_string(),
            product_string,
            paired,
        )
        .await?;
    } else {
        let mut lock = pairing_lock().lock().await;
        *lock = Some(PairingSession {
            session_id: session_id.clone(),
            device_path: device_path.to_string(),
            product_string,
            pairing,
        });
    }

    Ok((session_id, pairing_code))
}

/// Waits for device confirmation of the pairing code (desktop).
#[cfg(not(target_os = "android"))]
pub async fn wait_pairing_confirm(session_id: &str) -> Result<()> {
    let pending = {
        let mut lock = pairing_lock().lock().await;
        match lock.take() {
            Some(p) if p.session_id == session_id => p,
            other => {
                *lock = other;
                return Err(anyhow!("No pending pairing for session {session_id}"));
            }
        }
    };

    let paired = pending
        .pairing
        .wait_confirm()
        .await
        .map_err(|e| anyhow!("BitBox02 pairing rejected: {e}"))?;

    finish_connection(
        session_id.to_string(),
        pending.device_path,
        pending.product_string,
        paired,
    )
    .await
}

/// Wraps a freshly-paired device, reads the root fingerprint, and stores the session.
///
/// Called by both the desktop HID path and the Android channel path — the only
/// platform difference is how `paired` was obtained.
pub async fn finish_connection(
    session_id: String,
    device_path: String,
    product_string: String,
    paired: bitbox_api::PairedBitBox<BB02Runtime>,
) -> Result<()> {
    let root_fingerprint = paired
        .root_fingerprint()
        .await
        .map_err(|e| anyhow!("Cannot read fingerprint: {e}"))?;

    let device = async_hwi::bitbox::BitBox02::from(paired);

    let mut lock = connected_lock().lock().await;
    *lock = Some(ConnectedSession {
        session_id,
        device_path,
        product_string,
        root_fingerprint,
        device,
    });

    Ok(())
}

/// Disconnects and removes the active session.
pub async fn disconnect(session_id: &str) -> Result<()> {
    {
        let mut lock = connected_lock().lock().await;
        if matches!(lock.as_ref(), Some(s) if s.session_id == session_id) {
            *lock = None;
        }
    }
    #[cfg(not(target_os = "android"))]
    {
        let mut lock = pairing_lock().lock().await;
        if matches!(lock.as_ref(), Some(p) if p.session_id == session_id) {
            *lock = None;
        }
    }
    #[cfg(target_os = "android")]
    {
        android::clear_pending_pairing(Some(session_id)).await;
    }
    Ok(())
}

/// Drops the active session and any in-flight pairing state without sending
/// anything to the device.
///
/// Use this when the transport is known to be gone (USB cable unplugged,
/// device powered off, OS revoked permission). Unlike [`disconnect`], this:
/// - does not require a `session_id` (the caller often doesn't have one
///   at the point a detach event is observed);
/// - does not attempt any I/O on the device.
pub async fn invalidate_active_session() {
    // Wake any in-flight protocol task FIRST so it unwinds, drops its
    // `session_guard!` MutexGuard on `connected_lock`, and releases the
    // `read_rx` mutex. Otherwise the `connected_lock().lock().await` below
    // would deadlock against an in-flight operation (e.g. xpub fetch) that
    // is holding the guard while parked on `read_rx.recv()` — which is
    // exactly what a detach mid-operation triggers.
    #[cfg(target_os = "android")]
    android::cancel_inflight_session();

    *connected_lock().lock().await = None;
    #[cfg(not(target_os = "android"))]
    {
        *pairing_lock().lock().await = None;
    }
    #[cfg(target_os = "android")]
    {
        android::clear_pending_pairing(None).await;
    }
}

// ── Shared BTC operations (all platforms) ────────────────────────────────────
//
// All operations use async_hwi::bitbox::BitBox02<T> — identical code on Android
// (ChannelTransport) and desktop (HID). Platform differences live only in the
// transport layer (android.rs vs start_pairing), not here.

use crate::api::model::APINetwork;

/// Counts the number of distinct xpubs/tpubs in a descriptor.
/// Used to detect single-key wallets that the BitBox02 handles natively
/// and therefore cannot (and need not) be registered as policy wallets.
fn count_unique_xpubs(descriptor: &str) -> usize {
    use regex::Regex;
    use std::collections::HashSet;
    use std::sync::OnceLock;
    // Same pattern as async_hwi::bitbox::extract_script_config_policy
    static RE: OnceLock<Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        Regex::new(r"(\[.+?\])?[xyYzZtuUvV]pub[1-9A-HJ-NP-Za-km-z]{79,108}").expect("static regex")
    });
    re.find_iter(descriptor)
        .map(|m| m.as_str())
        .collect::<HashSet<_>>()
        .len()
}

/// Diagnostic: mirror `async_hwi::bitbox::extract_script_config_policy`'s regex
/// extraction and print the resulting wallet-policy template plus the ordered
/// `@N` → key-info mapping. Use to verify that the policy registered on the
/// device matches the policy used at signing time when debugging
/// "Could not find our key in an input" / mismatched policy errors.
///
/// Body compiled out in release builds — prints sensitive xpubs/derivations.
#[cfg(debug_assertions)]
fn debug_log_policy(descriptor: &str, source: &str) {
    use regex::Regex;
    use std::sync::OnceLock;
    static RE: OnceLock<Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        Regex::new(r"((\[.+?\])?[xyYzZtuUvV]pub[1-9A-HJ-NP-Za-km-z]{79,108})")
            .expect("static regex")
    });
    let mut pubkeys: Vec<&str> = Vec::new();
    for capture in re.find_iter(descriptor) {
        let s = capture.as_str();
        if !pubkeys.contains(&s) {
            pubkeys.push(s);
        }
    }
    let mut template = descriptor.to_string();
    for (i, k) in pubkeys.iter().enumerate() {
        template = template.replace(k, &format!("@{}", i));
    }
    let template = template
        .rsplit_once('#')
        .map(|(t, _)| t.to_string())
        .unwrap_or(template);
    eprintln!("[HW policy/{source}] template = {template}");
    for (i, k) in pubkeys.iter().enumerate() {
        eprintln!("[HW policy/{source}]   @{i} = {k}");
    }
    eprintln!(
        "[HW policy/{source}] {} key(s), {} occurrences of '@'",
        pubkeys.len(),
        template.matches('@').count()
    );
}

#[cfg(not(debug_assertions))]
fn debug_log_policy(_descriptor: &str, _source: &str) {}

fn api_network_to_btc_network(network: APINetwork) -> bdk_wallet::bitcoin::Network {
    match network {
        APINetwork::Bitcoin => bdk_wallet::bitcoin::Network::Bitcoin,
        APINetwork::Testnet | APINetwork::Testnet4 => bdk_wallet::bitcoin::Network::Testnet,
        APINetwork::Signet => bdk_wallet::bitcoin::Network::Signet,
        APINetwork::Regtest => bdk_wallet::bitcoin::Network::Regtest,
    }
}

pub async fn btc_get_xpub(
    session: &mut ConnectedSession,
    derivation_path: &str,
    network: APINetwork,
) -> Result<String> {
    use async_hwi::HWI as _;
    use bdk_wallet::bitcoin::bip32::DerivationPath;
    use std::str::FromStr;

    session.device.network = api_network_to_btc_network(network);

    let path = DerivationPath::from_str(derivation_path)
        .map_err(|e| anyhow!("Invalid derivation path '{derivation_path}': {e}"))?;

    let xpub = session
        .device
        .get_extended_pubkey(&path)
        .await
        .map_err(|e| anyhow!("get_xpub failed: {e}"))?;

    let descriptor_path = derivation_path
        .strip_prefix("m/")
        .unwrap_or(derivation_path);

    Ok(format!(
        "[{}/{}]{}",
        session.root_fingerprint, descriptor_path, xpub
    ))
}

pub async fn btc_sign_psbt(
    session: &mut ConnectedSession,
    psbt_base64: &str,
    network: APINetwork,
    descriptor: Option<&str>,
    signer_chain_indices: Option<Vec<u32>>,
) -> Result<String> {
    use async_hwi::HWI as _;
    use base64::engine::general_purpose::STANDARD as B64;
    use base64::Engine as _;
    use bdk_wallet::bitcoin::bip32::ChildNumber;
    use bdk_wallet::bitcoin::psbt::Psbt;
    use bdk_wallet::bitcoin::secp256k1::XOnlyPublicKey;
    use bdk_wallet::bitcoin::taproot::TapLeafHash;
    use std::collections::BTreeMap;
    type SavedTapOrigins =
        BTreeMap<XOnlyPublicKey, (Vec<TapLeafHash>, bdk_wallet::bitcoin::bip32::KeySource)>;

    session.device.network = api_network_to_btc_network(network);
    // Only extract a wallet-policy for descriptors that the BitBox treats as
    // policies (miniscript wsh, taproot script-path, wsh(pk(...)), …). Native
    // single-key types (P2WPKH, P2PKH, P2SH-P2WPKH, single-key P2TR) and plain
    // BIP48 sortedmulti must keep policy=None — the firmware rejects those
    // with InvalidInput when sent through the wallet-policies path.
    hw_debug!(
        "[HW policy/sign] session.root_fingerprint = {}",
        session.root_fingerprint
    );
    // Fresh fingerprint from the device, exactly as bitbox_api::btc_sign_psbt
    // will read it internally to compare against PSBT tap_key_origins. If the
    // user toggled passphrase / restarted into a different seed after pairing,
    // this will differ from session.root_fingerprint.
    //
    // Skip the device round-trip in release: no logging, no wasted USB I/O.
    #[cfg(debug_assertions)]
    match session.device.client.root_fingerprint().await {
        Ok(fp) => eprintln!("[HW policy/sign] live device root_fingerprint = {fp}"),
        Err(e) => eprintln!("[HW policy/sign] live device root_fingerprint query failed: {e}"),
    }
    session.device.policy = descriptor
        .filter(|d| {
            let s = d.trim();
            let is_native_tr =
                s.starts_with("tr(") && !s.contains(',') && count_unique_xpubs(s) == 1;
            let is_native = s.starts_with("wpkh(")
                || s.starts_with("pkh(")
                || s.starts_with("sh(wpkh(")
                || is_native_tr;
            let is_bip48_multisig =
                s.starts_with("wsh(sortedmulti(") || s.starts_with("sh(wsh(sortedmulti(");
            !is_native && !is_bip48_multisig
        })
        .inspect(|d| debug_log_policy(d, "sign"))
        .map(async_hwi::bitbox::extract_script_config_policy)
        .transpose()
        .map_err(|e| anyhow!("Invalid descriptor policy: {e}"))?;

    let psbt_bytes = B64
        .decode(psbt_base64)
        .map_err(|e| anyhow!("Invalid PSBT base64: {e}"))?;
    let mut psbt = Psbt::deserialize(&psbt_bytes).map_err(|e| anyhow!("Invalid PSBT: {e}"))?;

    // Diagnostic dump: what does bitbox-api's find_our_key() actually see?
    // It walks tap_key_origins per input and matches by fingerprint bytes against
    // the device's root_fingerprint. KeyNotFound = nothing matched here.
    //
    // Replicate EXACTLY: bitbox-api uses `&fingerprint[..] == our_root_fingerprint`,
    // where `our_root_fingerprint = hex::decode(self.root_fingerprint().await?)`.
    // Compare raw bytes side by side to catch any endianness / serialization gotcha.
    //
    // The live query is diagnostic-only — a transient I/O error (USB suspend on
    // Android, brief disconnect) must NOT abort signing. Fall back to the
    // fingerprint cached at session-open time; the real signing call below has
    // its own fingerprint handling.
    //
    // Entire block is dead in release builds (sensitive xpubs/fingerprints/paths).
    #[cfg(debug_assertions)]
    {
        let live_fp = match session.device.client.root_fingerprint().await {
            Ok(fp) => fp,
            Err(e) => {
                eprintln!(
                    "[HW psbt/sign] live root_fingerprint query failed: {e} — falling back to cached {}",
                    session.root_fingerprint
                );
                session.root_fingerprint.clone()
            }
        };
        let our_root_fingerprint: Vec<u8> = match hex::decode(&live_fp) {
            Ok(b) => b,
            Err(e) => {
                eprintln!("[HW psbt/sign] hex::decode({live_fp}) failed: {e}");
                Vec::new()
            }
        };
        eprintln!(
            "[HW psbt/sign] our_root_fingerprint raw bytes = {:02x?} (hex={live_fp})",
            our_root_fingerprint
        );
        for (idx, input) in psbt.inputs.iter().enumerate() {
            eprintln!(
                "[HW psbt/sign] input #{idx}: tap_key_origins.len() = {}, bip32_derivation.len() = {}",
                input.tap_key_origins.len(),
                input.bip32_derivation.len()
            );
            let mut matches_by_bytes = 0;
            let mut matches_by_string = 0;
            for (xonly, (leaves, (fp, path))) in input.tap_key_origins.iter() {
                let fp_bytes: &[u8] = &fp[..];
                let fp_hex = fp.to_string().to_lowercase();
                let by_string = fp_hex == live_fp;
                let by_bytes = fp_bytes == our_root_fingerprint.as_slice();
                if by_string {
                    matches_by_string += 1;
                }
                if by_bytes {
                    matches_by_bytes += 1;
                }
                let mark = match (by_bytes, by_string) {
                    (true, true) => "  <-- OURS (bytes+string)",
                    (true, false) => "  <-- OURS (bytes only!)",
                    (false, true) => "  <-- mismatch (string only — endianness!)",
                    (false, false) => "",
                };
                eprintln!(
                    "[HW psbt/sign]   tap xonly={}… fp_bytes={:02x?} fp_str={} path={} leaves={}{}",
                    &xonly.to_string()[..16],
                    fp_bytes,
                    fp_hex,
                    path,
                    leaves.len(),
                    mark
                );
            }
            eprintln!(
                "[HW psbt/sign]   → matches: {matches_by_bytes} by raw bytes (bitbox-api path), {matches_by_string} by string"
            );
        }
    }

    // BIP48 sortedmulti: bypass async_hwi.sign_tx and call bitbox-api directly
    // with force_script_config=Multisig. The high-level sign_tx panics in
    // bitbox-api's `script_config_from_utxo` because plain multisig configs
    // are not inferable from PSBT inputs.
    if let Some(ms_desc) = descriptor {
        if let Some(ms) = parse_bip48_sortedmulti(ms_desc, &session.root_fingerprint) {
            use bitbox_api::pb;
            let coin = if network == APINetwork::Bitcoin {
                pb::BtcCoin::Btc
            } else {
                pb::BtcCoin::Tbtc
            };
            let multisig_config = bitbox_api::btc::make_script_config_multisig(
                ms.threshold,
                &ms.xpubs,
                ms.our_index,
                ms.script_type,
            );
            let force = pb::BtcScriptConfigWithKeypath {
                script_config: Some(multisig_config),
                keypath: bitbox_api::Keypath::from(&ms.keypath_account).to_vec(),
            };
            session
                .device
                .client
                .btc_sign_psbt(
                    coin,
                    &mut psbt,
                    Some(force),
                    pb::btc_sign_init_request::FormatUnit::Default,
                )
                .await
                .map_err(|e| anyhow!("BitBox02 signing failed: {e}"))?;
            return Ok(B64.encode(psbt.serialize()));
        }
    }

    // BB02 signs the first tap_key_origin entry matching its master fingerprint
    // (firmware/protocol limitation). For multi-leaf tr descriptors we prune the
    // entries whose derivation lane does not belong to the spend path the user
    // selected, then restore them after the device signs so the returned PSBT
    // remains structurally complete for downstream finalization.
    //
    // `signer_chain_indices` carries EVERY lane the signer's key contributes in
    // this spend path — typically two values (receive + change) for multipath
    // keys like `<0;1>/*` or `<8;9>/*`. We keep the entry if its second-to-last
    // path component (the lane) is in that set, so a change UTXO derived via
    // the non-canonical change lane of `<8;9>` (i.e. 9) is recognised.
    let signer_fp = session.root_fingerprint.clone();
    let mut saved_origins: Vec<SavedTapOrigins> = Vec::new();
    if let Some(chain_lanes) = signer_chain_indices.as_ref() {
        for input in psbt.inputs.iter_mut() {
            let to_remove: Vec<XOnlyPublicKey> = input
                .tap_key_origins
                .iter()
                .filter_map(|(xonly, (_, (fp, path)))| {
                    if fp.to_string() != signer_fp {
                        return None;
                    }
                    let matches_chain = matches!(
                        path.as_ref().iter().rev().nth(1),
                        Some(ChildNumber::Normal { index }) if chain_lanes.contains(index)
                    );
                    if matches_chain {
                        None
                    } else {
                        Some(*xonly)
                    }
                })
                .collect();
            let mut saved: SavedTapOrigins = BTreeMap::new();
            for xonly in to_remove {
                if let Some(value) = input.tap_key_origins.remove(&xonly) {
                    saved.insert(xonly, value);
                }
            }
            saved_origins.push(saved);
        }
    }

    let sign_result = session.device.sign_tx(&mut psbt).await;

    if !saved_origins.is_empty() {
        for (input, saved) in psbt.inputs.iter_mut().zip(saved_origins) {
            for (xonly, value) in saved {
                input.tap_key_origins.insert(xonly, value);
            }
        }
    }

    sign_result.map_err(|e| anyhow!("BitBox02 signing failed: {e}"))?;

    Ok(B64.encode(psbt.serialize()))
}

// ── Address display ───────────────────────────────────────────────────────────

/// Extracts the full BIP-32 derivation path for the device's key in a
/// descriptor, appending `/{chain}/{index}` for the specific address.
///
/// For example, `[aabbccdd/84'/0'/0']xpub...` with chain=0, index=5 →
/// `m/84'/0'/0'/0/5`.
fn derive_address_path(
    descriptor: &str,
    root_fingerprint: &str,
    chain: u32,
    index: u32,
) -> Result<bdk_wallet::bitcoin::bip32::DerivationPath> {
    use bdk_wallet::bitcoin::bip32::DerivationPath;
    use std::str::FromStr;

    let prefix = format!("[{root_fingerprint}/");
    let key_start = descriptor.find(&prefix).ok_or_else(|| {
        anyhow!("Key for this device ({root_fingerprint}) not found in descriptor")
    })?;
    let path_start = key_start + prefix.len();
    let path_end = descriptor[path_start..]
        .find(']')
        .ok_or_else(|| anyhow!("Malformed key origin in descriptor"))?;
    let path_str = &descriptor[path_start..path_start + path_end];

    let full = format!("m/{path_str}/{chain}/{index}");
    DerivationPath::from_str(&full).map_err(|e| anyhow!("Invalid derivation path '{full}': {e}"))
}

/// Displays an address on the BitBox02 screen for user verification.
///
/// `chain`: 0 = receive (external), 1 = change (internal).
/// `index`: the address index within that chain.
///
/// Supports P2WPKH, P2SH-P2WPKH, single-key P2TR, and policy wallets
/// (WSH multisig, taproot script-path, miniscript).
pub async fn btc_display_address(
    session: &mut ConnectedSession,
    descriptor: &str,
    network: APINetwork,
    chain: u32,
    index: u32,
) -> Result<()> {
    use async_hwi::{AddressScript, HWI as _};

    session.device.network = api_network_to_btc_network(network);

    // Strip checksum so prefix checks work cleanly.
    let desc = descriptor.split('#').next().unwrap_or(descriptor);

    // Fast path: BIP48 plain sortedmulti — must use the Multisig variant.
    // The wallet-policies path returns "invalid input" from the firmware.
    if let Some(ms) = parse_bip48_sortedmulti(desc, &session.root_fingerprint) {
        use bdk_wallet::bitcoin::bip32::ChildNumber;
        use bitbox_api::pb;
        let coin = if network == APINetwork::Bitcoin {
            pb::BtcCoin::Btc
        } else {
            pb::BtcCoin::Tbtc
        };
        let multisig_config = bitbox_api::btc::make_script_config_multisig(
            ms.threshold,
            &ms.xpubs,
            ms.our_index,
            ms.script_type,
        );
        // Address path = keypath_account + chain + index.
        let full_path = ms
            .keypath_account
            .child(ChildNumber::from_normal_idx(chain).map_err(|e| anyhow!("{e}"))?)
            .child(ChildNumber::from_normal_idx(index).map_err(|e| anyhow!("{e}"))?);
        let keypath = bitbox_api::Keypath::from(&full_path);
        return session
            .device
            .client
            .btc_address(coin, &keypath, &multisig_config, true)
            .await
            .map(|_| ())
            .map_err(|e| anyhow!("Cannot display address: {e}"));
    }

    if count_unique_xpubs(desc) >= 2 {
        // Policy wallet: taproot script-path or miniscript wsh.
        // Set the policy on the device so display_address can find the right key.
        session.device.policy = Some(
            async_hwi::bitbox::extract_script_config_policy(descriptor)
                .map_err(|e| anyhow!("Cannot parse descriptor policy: {e}"))?,
        );
        session
            .device
            .display_address(&AddressScript::Miniscript {
                index,
                change: chain == 1,
            })
            .await
            .map_err(|e| anyhow!("Cannot display address: {e}"))
    } else if desc.starts_with("tr(") {
        // Single-key P2TR.
        let path = derive_address_path(descriptor, &session.root_fingerprint, chain, index)?;
        session
            .device
            .display_address(&AddressScript::P2TR(path))
            .await
            .map_err(|e| anyhow!("Cannot display address: {e}"))
    } else {
        // Simple segwit: P2WPKH or P2SH-P2WPKH.
        use bitbox_api::{btc::make_script_config_simple, pb};
        let simple_type = if desc.starts_with("sh(") {
            pb::btc_script_config::SimpleType::P2wpkhP2sh
        } else if desc.contains("wpkh(") {
            pb::btc_script_config::SimpleType::P2wpkh
        } else {
            return Err(anyhow!(
                "Address verification is not supported for this wallet type."
            ));
        };
        let coin = if network == APINetwork::Bitcoin {
            pb::BtcCoin::Btc
        } else {
            pb::BtcCoin::Tbtc
        };
        let path = derive_address_path(descriptor, &session.root_fingerprint, chain, index)?;
        session
            .device
            .client
            .btc_address(
                coin,
                &bitbox_api::Keypath::from(&path),
                &make_script_config_simple(simple_type),
                true,
            )
            .await
            .map(|_| ())
            .map_err(|e| anyhow!("Cannot display address: {e}"))
    }
}

/// Parsed representation of a BIP48 plain multisig descriptor that the BitBox02
/// firmware accepts via the dedicated `Multisig` script_config variant
/// (NOT the wallet-policies variant). Returns None for any descriptor that is
/// not a flat `wsh(sortedmulti(...))` or `sh(wsh(sortedmulti(...)))` — those
/// must keep going through `extract_script_config_policy`.
struct Bip48Multisig {
    threshold: u32,
    xpubs: Vec<bdk_wallet::bitcoin::bip32::Xpub>,
    our_index: u32,
    script_type: bitbox_api::pb::btc_script_config::multisig::ScriptType,
    keypath_account: bdk_wallet::bitcoin::bip32::DerivationPath,
}

fn parse_bip48_sortedmulti(descriptor: &str, our_mfp: &str) -> Option<Bip48Multisig> {
    use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpub};
    use bitbox_api::pb;
    use std::str::FromStr;

    // Strip checksum and whitespace.
    let d = descriptor.split('#').next().unwrap_or(descriptor).trim();

    // Match prefix and capture inner args. Outer wrapper determines script type.
    let (script_type, inner) = if let Some(s) = d
        .strip_prefix("wsh(sortedmulti(")
        .and_then(|s| s.strip_suffix("))"))
    {
        (pb::btc_script_config::multisig::ScriptType::P2wsh, s)
    } else if let Some(s) = d
        .strip_prefix("sh(wsh(sortedmulti(")
        .and_then(|s| s.strip_suffix(")))"))
    {
        (pb::btc_script_config::multisig::ScriptType::P2wshP2sh, s)
    } else {
        return None;
    };

    // inner = "<threshold>,<keyspec>,<keyspec>..."
    let mut split = inner.splitn(2, ',');
    let threshold: u32 = split.next()?.trim().parse().ok()?;
    let keys_str = split.next()?;

    // Each keyspec: [mfp/path]xpub[/<0;1>/*]?
    let re = regex::Regex::new(
        r"\[([0-9a-fA-F]{8})/([^\]]+)\]([xyYzZtuUvV]pub[1-9A-HJ-NP-Za-km-z]{79,108})",
    )
    .ok()?;

    let mut xpubs = Vec::new();
    let mut our_index: Option<u32> = None;
    let mut keypath_account: Option<DerivationPath> = None;
    for (i, cap) in re.captures_iter(keys_str).enumerate() {
        let mfp = cap.get(1)?.as_str();
        let path = cap.get(2)?.as_str();
        let xpub_str = cap.get(3)?.as_str();
        let xpub = Xpub::from_str(xpub_str).ok()?;
        xpubs.push(xpub);
        if mfp.eq_ignore_ascii_case(our_mfp) {
            our_index = Some(i as u32);
            // Derivation path inside [] is in BIP48 form like "48'/1'/0'/2'" — no leading m/.
            keypath_account = Some(DerivationPath::from_str(&format!("m/{}", path)).ok()?);
        }
    }

    if xpubs.len() < 2 || threshold == 0 || threshold as usize > xpubs.len() {
        return None;
    }

    Some(Bip48Multisig {
        threshold,
        xpubs,
        our_index: our_index?,
        script_type,
        keypath_account: keypath_account?,
    })
}

pub async fn btc_check_registration(
    session: &mut ConnectedSession,
    descriptor: &str,
    network: APINetwork,
) -> Result<bool> {
    session.device.network = api_network_to_btc_network(network);

    // Fast path: plain BIP48 wsh(sortedmulti(...)) is registered as the Multisig
    // variant, not as a wallet policy. The firmware rejects the policy variant
    // for these with "invalid input".
    if let Some(ms) = parse_bip48_sortedmulti(descriptor, &session.root_fingerprint) {
        use bitbox_api::pb;
        let pb_coin = if network == APINetwork::Bitcoin {
            pb::BtcCoin::Btc
        } else {
            pb::BtcCoin::Tbtc
        };
        let multisig_config = bitbox_api::btc::make_script_config_multisig(
            ms.threshold,
            &ms.xpubs,
            ms.our_index,
            ms.script_type,
        );
        return session
            .device
            .client
            .btc_is_script_config_registered(
                pb_coin,
                &multisig_config,
                Some(&bitbox_api::Keypath::from(&ms.keypath_account)),
            )
            .await
            .map_err(|e| anyhow!("Registration check failed: {e}"));
    }

    hw_debug!(
        "[HW policy/check] connected device root_fingerprint = {}",
        session.root_fingerprint
    );
    debug_log_policy(descriptor, "check");
    let registered = session
        .device
        .is_policy_registered(descriptor)
        .await
        .map_err(|e| anyhow!("Registration check failed: {e}"))?;
    hw_debug!("[HW policy/check] is_policy_registered → {registered}");
    Ok(registered)
}

pub async fn btc_register_descriptor(
    session: &mut ConnectedSession,
    wallet_name: &str,
    descriptor: &str,
    network: APINetwork,
) -> Result<bool> {
    use bitbox_api::pb;

    // Firmware constraint: name must be 1-30 printable ASCII chars, no whitespace
    // other than spaces. Validate early to give a clearer error than "invalid input".
    if wallet_name.is_empty() {
        return Err(anyhow!("Wallet name must not be empty."));
    }
    if wallet_name.len() > 30 {
        return Err(anyhow!(
            "Wallet name '{}' is {} characters — BitBox02 allows at most 30.",
            wallet_name,
            wallet_name.len()
        ));
    }
    if !wallet_name
        .chars()
        .all(|c| c.is_ascii() && (c == ' ' || !c.is_ascii_whitespace()) && !c.is_control())
    {
        return Err(anyhow!(
            "Wallet name contains characters not allowed by the BitBox02 \
             (only printable ASCII and spaces)."
        ));
    }

    // Verify that this descriptor contains a key owned by the connected device,
    // and that the key origin includes a derivation path (not just the fingerprint).
    // The firmware needs the path to derive and verify the xpub.
    let mfp = &session.root_fingerprint;
    let has_key_with_path = descriptor.contains(&format!("[{mfp}/"));
    let has_key_no_path = !has_key_with_path && descriptor.contains(&format!("[{mfp}]"));

    if has_key_no_path {
        return Err(anyhow!(
            "The key for this device ({mfp}) is missing its derivation path. \
             The key origin must include the full path, \
             e.g. [{mfp}/48'/0'/0'/2']xpub…"
        ));
    }
    if !has_key_with_path {
        return Err(anyhow!(
            "This descriptor does not contain a key from the connected device \
             (fingerprint {mfp}). Make sure you are using the correct device."
        ));
    }

    // The BitBox02 handles P2WPKH, P2PKH, P2SH-P2WPKH, and single-key P2TR natively
    // (no policy registration possible or needed). Policy wallets — including wsh(pk(...)),
    // wsh(multi(...)), miniscript wsh(...), and taproot with script paths — must be
    // registered. We detect native types by descriptor prefix / structure rather than
    // xpub count so that single-xpub policy descriptors like `wsh(pk(...))` are allowed.
    {
        let d = descriptor.trim();
        // Single-key taproot has no comma after the key expression (no script tree).
        let is_native_tr = d.starts_with("tr(") && !d.contains(',') && count_unique_xpubs(d) == 1;
        let is_native = d.starts_with("wpkh(")
            || d.starts_with("pkh(")
            || d.starts_with("sh(wpkh(")
            || is_native_tr;
        if is_native {
            return Err(anyhow!(
                "Single-key wallets (P2WPKH, P2PKH, P2SH-P2WPKH, single-key P2TR) do not need \
                 to be registered on the BitBox02 — the device handles them natively."
            ));
        }
    }

    let pb_coin = if network == APINetwork::Bitcoin {
        pb::BtcCoin::Btc
    } else {
        pb::BtcCoin::Tbtc
    };

    // Fast path: plain BIP48 wsh(sortedmulti(...)) / sh(wsh(sortedmulti(...)))
    // is registered as the Multisig variant with `keypath_account = Some(...)`.
    // The firmware rejects the wallet-policies variant for these descriptors
    // with InvalidInput (101).
    if let Some(ms) = parse_bip48_sortedmulti(descriptor, &session.root_fingerprint) {
        let multisig_config = bitbox_api::btc::make_script_config_multisig(
            ms.threshold,
            &ms.xpubs,
            ms.our_index,
            ms.script_type,
        );
        let kp = bitbox_api::Keypath::from(&ms.keypath_account);
        let already = session
            .device
            .client
            .btc_is_script_config_registered(pb_coin, &multisig_config, Some(&kp))
            .await
            .map_err(|e| anyhow!("Cannot check registration status: {e}"))?;
        if already {
            return Ok(false);
        }
        session
            .device
            .client
            .btc_register_script_config(
                pb_coin,
                &multisig_config,
                Some(&kp),
                pb::btc_register_script_config_request::XPubType::AutoXpubTpub,
                Some(wallet_name),
            )
            .await
            .map_err(|e| anyhow!("Registration failed: {e}"))?;
        return Ok(true);
    }

    // Generic policy / miniscript / taproot script-path path.
    // We bypass async-hwi's register_wallet wrapper to get distinct error messages
    // for the two separate firmware calls it makes.
    hw_debug!(
        "[HW policy/register] connected device root_fingerprint = {}, wallet_name = '{}'",
        session.root_fingerprint,
        wallet_name
    );
    debug_log_policy(descriptor, "register");
    let script_config: pb::BtcScriptConfig =
        async_hwi::bitbox::extract_script_config_policy(descriptor)
            .map_err(|e| anyhow!("Cannot parse descriptor as a policy: {e}"))?
            .into();

    // Step 1: check whether already registered.
    let already = session
        .device
        .client
        .btc_is_script_config_registered(pb_coin, &script_config, None)
        .await
        .map_err(|e| anyhow!("Cannot check registration status: {e}"))?;
    hw_debug!("[HW policy/register] btc_is_script_config_registered → {already}");

    if already {
        return Ok(false);
    }
    hw_debug!("[HW policy/register] sending btc_register_script_config to device…");

    // Step 2: register on device (user must confirm on the BitBox02 screen).
    session
        .device
        .client
        .btc_register_script_config(
            pb_coin,
            &script_config,
            None,
            pb::btc_register_script_config_request::XPubType::AutoXpubTpub,
            Some(wallet_name),
        )
        .await
        .map_err(|e| anyhow!("Registration failed: {e}"))?;

    Ok(true)
}
