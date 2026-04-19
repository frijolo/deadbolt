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

    let safe_key = hex::encode(device_path.as_bytes());
    let device_noise_dir = format!("{noise_dir}/{safe_key}");
    std::fs::create_dir_all(&device_noise_dir)?;
    let noise_config = Box::new(bitbox_api::PersistedNoiseConfig::new(&device_noise_dir));

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
    Ok(())
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
) -> Result<String> {
    use async_hwi::HWI as _;
    use base64::engine::general_purpose::STANDARD as B64;
    use base64::Engine as _;
    use bdk_wallet::bitcoin::psbt::Psbt;

    session.device.network = api_network_to_btc_network(network);
    session.device.policy = descriptor
        .map(async_hwi::bitbox::extract_script_config_policy)
        .transpose()
        .map_err(|e| anyhow!("Invalid descriptor policy: {e}"))?;

    let psbt_bytes = B64
        .decode(psbt_base64)
        .map_err(|e| anyhow!("Invalid PSBT base64: {e}"))?;
    let mut psbt = Psbt::deserialize(&psbt_bytes).map_err(|e| anyhow!("Invalid PSBT: {e}"))?;

    session
        .device
        .sign_tx(&mut psbt)
        .await
        .map_err(|e| anyhow!("BitBox02 signing failed: {e}"))?;

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

    if count_unique_xpubs(desc) >= 2 {
        // Policy wallet: multisig, taproot script-path, or miniscript.
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

pub async fn btc_check_registration(
    session: &mut ConnectedSession,
    descriptor: &str,
    network: APINetwork,
) -> Result<bool> {
    session.device.network = api_network_to_btc_network(network);
    session
        .device
        .is_policy_registered(descriptor)
        .await
        .map_err(|e| anyhow!("Registration check failed: {e}"))
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

    // Parse the descriptor into a BtcScriptConfig::Policy.
    // We bypass async-hwi's register_wallet wrapper to get distinct error messages
    // for the two separate firmware calls it makes.
    let script_config: pb::BtcScriptConfig =
        async_hwi::bitbox::extract_script_config_policy(descriptor)
            .map_err(|e| anyhow!("Cannot parse descriptor as a policy: {e}"))?
            .into();

    let pb_coin = if network == APINetwork::Bitcoin {
        pb::BtcCoin::Btc
    } else {
        pb::BtcCoin::Tbtc
    };

    // Step 1: check whether already registered.
    let already = session
        .device
        .client
        .btc_is_script_config_registered(pb_coin, &script_config, None)
        .await
        .map_err(|e| anyhow!("Cannot check registration status: {e}"))?;

    if already {
        return Ok(false);
    }

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
