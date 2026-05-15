// ---------------------------------------------------------------------------
// Nostr distributed descriptor backups
// ---------------------------------------------------------------------------
//
// Design: one NIP-78 event (kind 30078) per xpub per descriptor.
// Each event is:
//   - Signed by a Nostr keypair derived deterministically from that xpub via
//     HMAC-SHA256("deadbolt-nostr-backup-v1", xpub).
//   - Addressed with d = "deadbolt-backup-{descriptor_fingerprint}", where
//     descriptor_fingerprint is the first 8 hex chars of SHA-256(descriptor).
//     This makes each (xpub, descriptor) pair occupy a unique addressable slot,
//     so one xpub can hold backups for multiple distinct wallets without clobbering.
//   - Encrypted with the existing XpubKey scheme: Argon2id + AES-256-GCM,
//     one slot for the owning xpub only.
//   - Content: only the descriptor (no seeds, no full DB).
//
// Discovery and decryption both require the xpub: the derived pubkey (computed
// from the xpub via HMAC-SHA256) is used for the relay REQ filter, and the raw
// xpub is the Argon2id password that unwraps the data key. A single REQ
// (kinds=[30078], authors=[derived_pubkey]) returns every descriptor backed up
// under that xpub.
//
// Payload JSON format (stored in event content as base64):
// {
//   "version": 1,
//   "wallet_name": "...",
//   "network": "bitcoin",
//   "created_at": <unix_secs>,
//   "protection": { "type": 2, "slots": [{ XpubSlot for this event's xpub }] },
//   "data": "<base64(AES-256-GCM(export_data_key, {"descriptor":"..."}))>"
// }

use anyhow::{anyhow, Result};
use base64::{engine::general_purpose, Engine as _};
use futures::{SinkExt, StreamExt};
use hmac::{Hmac, Mac};
use nostr::prelude::*;
use sha2::{Digest, Sha256};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::time::Duration;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message};

use crate::core::key_protection::{
    decrypt_bytes, encrypt_bytes, generate_data_key, parse_xpub_credential, resolve_xpub_data_key,
    wrap_with_xpub, XpubSlot,
};
use crate::core::wallet_info::{create_wallet_db, WalletProtectionRequest};
use crate::core::wallet_persistence::descriptor_sig_storage::get_descriptor_sigs_as_json;

type HmacSha256 = Hmac<Sha256>;

const D_TAG_PREFIX: &str = "deadbolt-backup";
const KIND: u16 = 30078;
/// Delay between retry attempts (not user-configurable).
const RETRY_DELAY_MS: u64 = 500;
// Standard Argon2id parameters for Nostr payload encryption (same as file backup "Standard" level).

/// Runtime-configurable relay timeout (seconds). Default: 15.
/// A single timeout governs both the WebSocket connect and the message
/// receive phase of each relay operation.
static RELAY_TIMEOUT_SECS: AtomicU64 = AtomicU64::new(15);

/// Runtime-configurable total attempt count per relay operation. Default: 3.
/// 1 = no retries; 2 = one retry; 3 = two retries; etc.
static RELAY_MAX_ATTEMPTS: AtomicU32 = AtomicU32::new(3);

/// Apply connection settings loaded from persistent storage (e.g. SharedPreferences).
///
/// Call this once on app start and whenever the user changes the values.
/// Thread-safe; changes take effect on the next relay operation.
pub fn set_nostr_relay_config(timeout_secs: u64, max_attempts: u32) {
    RELAY_TIMEOUT_SECS.store(timeout_secs.max(1), Ordering::Relaxed);
    RELAY_MAX_ATTEMPTS.store(max_attempts.max(1), Ordering::Relaxed);
}

// Standard Argon2id parameters for Nostr payload encryption (same as file backup "Standard" level).
const M_COST: u32 = 65536;
const T_COST: u32 = 3;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Status of a Nostr relay for one wallet's backup.
pub struct NostrRelayStatus {
    pub url: String,
    /// True when every xpub in the descriptor has a valid backup event on this
    /// relay. An empty-content "deleted" event counts as no backup.
    pub has_backup: bool,
    /// Unix timestamp of the most recent event found (or published).
    pub last_published_at: Option<i64>,
    /// Event ID of the most recent event found.
    pub event_id: Option<String>,
    /// Non-null when the relay could not be reached or returned an error.
    pub error: Option<String>,
    /// Number of xpubs that have a valid backup for this specific descriptor.
    /// For singlesig this is 0 or 1; for multisig it can be anywhere from 0
    /// to `total_xpubs`.
    pub backed_up_xpubs: i64,
    /// Total number of xpubs in the wallet descriptor (1 for singlesig,
    /// N for N-of-M multisig).
    pub total_xpubs: i64,
}

/// Return type of `import_nostr_backup`.
pub struct NostrImportResult {
    pub wallet: crate::api::model::APIWalletInfo,
}

/// Detailed verification result of descriptor signatures embedded in a Nostr backup payload.
pub struct APIDescriptorSigVerification {
    /// Number of signatures that verified successfully.
    pub valid_count: i64,
    /// Total number of xpubs in the descriptor (from descriptor parsing). 0 if parsing failed.
    pub total_xpubs: i64,
    /// True when at least one signature present in the payload failed verification.
    pub has_invalid: bool,
    /// True when the xpub that discovered this backup has a valid signature in the payload.
    pub owner_xpub_signed: bool,
}

/// Response from `fetch_nostr_backup` with full metadata including first address.
pub struct NostrBackupResponse {
    pub bytes: Vec<u8>,
    pub wallet_name: Option<String>,
    pub network: Option<String>,
    pub created_at: Option<i64>,
    pub first_address: Option<String>,
    pub wallet_type: Option<crate::api::model::APIWalletType>,
    /// The decrypted descriptor string. Present when decryption succeeded.
    /// Can be passed to `scan_descriptor` to fetch on-chain balance/tx count.
    pub descriptor: Option<String>,
    /// Verification result of any descriptor signatures embedded in the backup.
    /// `None` only when decryption failed (i.e. `descriptor` is also `None`).
    pub descriptor_sig_verification: Option<APIDescriptorSigVerification>,
}

// ---------------------------------------------------------------------------
// Private helpers: descriptor signature verification for backup payloads
// ---------------------------------------------------------------------------

/// Extract the bare xpub from an `xpub_entry` string like `[mfp/path]xpubXXX`.
fn xpub_entry_bare(xpub_entry: &str) -> &str {
    if let Some(pos) = xpub_entry.rfind(']') {
        &xpub_entry[pos + 1..]
    } else {
        xpub_entry
    }
}

/// Verify descriptor signatures embedded in a decrypted backup inner payload.
///
/// `owner_xpub` is the bare xpub that was used to discover the backup. The
/// result indicates whether that specific key has a valid signature, how many
/// keys have signed in total, and whether any signature failed verification.
fn verify_descriptor_sigs_from_payload(
    inner: &serde_json::Value,
    descriptor: &str,
    owner_xpub: &str,
) -> APIDescriptorSigVerification {
    // Count total xpubs expected in the descriptor.
    let total_xpubs = crate::core::descriptor::DescriptorAnalyzer::analyze(descriptor)
        .and_then(|a| a.public_keys())
        .map(|k| k.len() as i64)
        .unwrap_or(0);

    let Some(arr) = inner.get("descriptor_sigs").and_then(|v| v.as_array()) else {
        return APIDescriptorSigVerification {
            valid_count: 0,
            total_xpubs,
            has_invalid: false,
            owner_xpub_signed: false,
        };
    };
    if arr.is_empty() {
        return APIDescriptorSigVerification {
            valid_count: 0,
            total_xpubs,
            has_invalid: false,
            owner_xpub_signed: false,
        };
    }

    let message = crate::core::bip322::descriptor_sig_message(descriptor);
    let mut valid_count: i64 = 0;
    let mut has_invalid = false;
    let mut owner_xpub_signed = false;

    for sig_val in arr {
        let (Some(xpub_entry), Some(sig_method), Some(sig_hex)) = (
            sig_val["xpub_entry"].as_str(),
            sig_val["sig_method"].as_str(),
            sig_val["sig_hex"].as_str(),
        ) else {
            has_invalid = true;
            continue;
        };
        let is_valid = crate::api::wallet::descriptor_sig::verify_one_sig(
            &message, xpub_entry, sig_method, sig_hex,
        );
        if is_valid {
            valid_count += 1;
            if xpub_entry_bare(xpub_entry) == owner_xpub {
                owner_xpub_signed = true;
            }
        } else {
            has_invalid = true;
        }
    }

    APIDescriptorSigVerification {
        valid_count,
        total_xpubs,
        has_invalid,
        owner_xpub_signed,
    }
}

// ---------------------------------------------------------------------------
// Private helpers: cryptographic key derivation
// ---------------------------------------------------------------------------

/// Compute the d-tag for a given descriptor.
///
/// Format: `deadbolt-backup-{first8hex(SHA-256(descriptor))}`.
/// The fingerprint ensures each distinct descriptor gets its own addressable
/// NIP-78 slot, so one xpub can back up multiple wallets without overwriting.
fn descriptor_d_tag(descriptor: &str) -> String {
    let hash = Sha256::digest(descriptor.as_bytes());
    format!("{}-{}", D_TAG_PREFIX, hex::encode(&hash[..4]))
}

/// Derive a deterministic Nostr keypair from an xpub string.
///
/// Uses HMAC-SHA256(key="deadbolt-nostr-backup-v1", data=xpub) to produce
/// 32 bytes used directly as a secp256k1 private key scalar.
fn derive_nostr_keypair(xpub: &str) -> Result<Keys> {
    let mut mac = HmacSha256::new_from_slice(b"deadbolt-nostr-backup-v1")
        .map_err(|e| anyhow!("HMAC init: {e}"))?;
    mac.update(xpub.as_bytes());
    let result = mac.finalize().into_bytes();
    let secret_key =
        SecretKey::from_slice(&result).map_err(|e| anyhow!("secp256k1 key derivation: {e}"))?;
    Ok(Keys::new(secret_key))
}

// ---------------------------------------------------------------------------
// Private helpers: payload construction
// ---------------------------------------------------------------------------

/// Build the encrypted backup payload JSON bytes for a single (mfp, xpub) pair.
fn build_payload_for_xpub(
    descriptor: &str,
    wallet_name: &str,
    network: &str,
    mfp: &str,
    xpub: &str,
    created_at: i64,
    descriptor_sigs: Option<serde_json::Value>,
) -> Result<Vec<u8>> {
    let inner = if let Some(sigs) = descriptor_sigs {
        serde_json::json!({ "descriptor": descriptor, "descriptor_sigs": sigs })
    } else {
        serde_json::json!({ "descriptor": descriptor })
    };
    let inner_bytes = serde_json::to_vec(&inner)?;

    // Fresh export data key per backup
    let export_data_key = generate_data_key()?;

    // AES-256-GCM encrypt the inner plaintext
    let encrypted_inner = encrypt_bytes(&export_data_key, &inner_bytes)?;
    let data_b64 = general_purpose::STANDARD.encode(&encrypted_inner);

    // Build single XpubKey slot (Argon2id-wrapped export data key)
    let slot = wrap_with_xpub(mfp, xpub, &export_data_key, M_COST, T_COST, "")?;
    let slot_value = serde_json::to_value(&slot).map_err(|e| anyhow!("slot serialization: {e}"))?;

    let payload = serde_json::json!({
        "version": 1,
        "wallet_name": wallet_name,
        "network": network,
        "created_at": created_at,
        "protection": {
            "type": 2,
            "slots": [slot_value]
        },
        "data": data_b64,
    });

    serde_json::to_vec(&payload).map_err(|e| anyhow!("payload serialization: {e}"))
}

/// Build and sign a NIP-78 Nostr event containing the backup payload.
/// `d_tag` is the addressable identifier, e.g. "deadbolt-backup-{fingerprint}".
fn build_nostr_event(keys: &Keys, payload_bytes: &[u8], d_tag: &str) -> Result<Event> {
    let content = general_purpose::STANDARD.encode(payload_bytes);
    EventBuilder::new(Kind::Custom(KIND), content)
        .tag(Tag::identifier(d_tag))
        .tag(Tag::hashtag(D_TAG_PREFIX))
        .sign_with_keys(keys)
        .map_err(|e| anyhow!("event signing: {e}"))
}

// ---------------------------------------------------------------------------
// Private helpers: Nostr relay WebSocket protocol
// ---------------------------------------------------------------------------

type WsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn ws_open(relay_url: &str, secs: u64) -> Result<WsStream> {
    match timeout(Duration::from_secs(secs), connect_async(relay_url)).await {
        Ok(Ok((ws, _))) => Ok(ws),
        Ok(Err(e)) => Err(anyhow!("connect: {e}")),
        Err(_) => Err(anyhow!("connection timeout ({secs}s)")),
    }
}

/// Inner implementation of ws_publish_event — one attempt, no retry.
async fn ws_publish_event_once(relay_url: &str, event: &Event) -> (bool, Option<String>) {
    let secs = RELAY_TIMEOUT_SECS.load(Ordering::Relaxed);
    let msg = match serde_json::to_string(&serde_json::json!(["EVENT", event])) {
        Ok(m) => m,
        Err(e) => return (false, Some(format!("serialize: {e}"))),
    };

    let (mut write, mut read) = match ws_open(relay_url, secs).await {
        Ok(ws) => ws.split(),
        Err(e) => return (false, Some(e.to_string())),
    };

    if let Err(e) = write.send(Message::Text(msg.into())).await {
        let _ = write.close().await;
        return (false, Some(format!("send: {e}")));
    }

    let event_id = event.id.to_hex();
    let mut success = false;
    let mut relay_error: Option<String> = None;

    let _ = timeout(Duration::from_secs(secs), async {
        while let Some(msg_result) = read.next().await {
            if let Ok(Message::Text(text)) = msg_result {
                if let Ok(arr) = serde_json::from_str::<serde_json::Value>(&text) {
                    if arr[0] == "OK" && arr[1].as_str() == Some(&event_id) {
                        if arr[2].as_bool() == Some(true) {
                            success = true;
                        } else {
                            relay_error = arr[3].as_str().map(|s| s.to_string());
                        }
                        break;
                    }
                }
            }
        }
    })
    .await;

    let _ = write.close().await;

    if success {
        (true, None)
    } else {
        (false, relay_error.or(Some("no OK response".to_string())))
    }
}

/// Publish a signed event JSON string to a relay, retrying on failure.
/// Total attempts = RELAY_MAX_ATTEMPTS (runtime-configurable).
async fn ws_publish_event(relay_url: &str, event: &Event) -> (bool, Option<String>) {
    let max_attempts = RELAY_MAX_ATTEMPTS.load(Ordering::Relaxed).max(1);
    let mut last_err: Option<String> = None;
    for attempt in 0..max_attempts {
        let (ok, err) = ws_publish_event_once(relay_url, event).await;
        if ok {
            return (true, None);
        }
        last_err = err;
        if attempt + 1 < max_attempts {
            tokio::time::sleep(Duration::from_millis(RETRY_DELAY_MS)).await;
        }
    }
    (false, last_err)
}

/// Inner implementation of ws_check_descriptor_backup — one attempt, no retry.
async fn ws_check_descriptor_backup_once(
    relay_url: &str,
    pubkeys: &[PublicKey],
    d_tag: &str,
) -> Result<(usize, Option<i64>, Option<String>)> {
    let secs = RELAY_TIMEOUT_SECS.load(Ordering::Relaxed);
    let (mut write, mut read) = ws_open(relay_url, secs).await?.split();

    let sub_id = "dbl1";
    // NIP-01 tag filter: `#d` restricts to events whose d-tag matches the
    // descriptor fingerprint.  This prevents a backup for wallet-A from
    // reporting as present when checking wallet-B's status.
    let req_msg = serde_json::json!([
        "REQ",
        sub_id,
        {
            "kinds": [KIND],
            "authors": pubkeys.iter().map(|pk| pk.to_hex()).collect::<Vec<_>>(),
            "#d": [d_tag],
        }
    ])
    .to_string();

    if let Err(e) = write.send(Message::Text(req_msg.into())).await {
        let _ = write.close().await;
        return Err(anyhow!("send REQ: {e}"));
    }

    // Per-pubkey: track the latest event and whether it carries real content.
    // A deletion event (empty content, higher timestamp) must beat an earlier
    // backup event, so we always update on ts >= previous.
    let expected: std::collections::HashSet<String> =
        pubkeys.iter().map(|pk| pk.to_hex()).collect();
    // key = pubkey hex, value = (latest_ts, has_valid_content)
    let mut per_pubkey: std::collections::HashMap<String, (i64, bool)> =
        std::collections::HashMap::new();
    // Track the most recent valid (non-empty) event for the relay-level fields.
    let mut last_ts: Option<i64> = None;
    let mut last_event_id: Option<String> = None;

    let _ = timeout(Duration::from_secs(secs), async {
        while let Some(msg_result) = read.next().await {
            if let Ok(Message::Text(text)) = msg_result {
                if let Ok(arr) = serde_json::from_str::<serde_json::Value>(&text) {
                    if arr[0] == "EOSE" {
                        break;
                    }
                    if arr[0] == "EVENT" && arr[1].as_str() == Some(sub_id) {
                        if let Some(ev) = arr.get(2) {
                            let author = ev["pubkey"].as_str().unwrap_or("").to_string();
                            if !expected.contains(&author) {
                                continue;
                            }
                            let ts = ev["created_at"].as_i64().unwrap_or(0);
                            let has_content = !ev["content"].as_str().unwrap_or("").is_empty();

                            let entry = per_pubkey.entry(author).or_insert((i64::MIN, false));
                            if ts >= entry.0 {
                                *entry = (ts, has_content);
                                if has_content && last_ts.is_none_or(|prev| ts > prev) {
                                    last_ts = Some(ts);
                                    last_event_id = ev["id"].as_str().map(|s| s.to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
    })
    .await;

    let close_msg = serde_json::json!(["CLOSE", sub_id]).to_string();
    let _ = write.send(Message::Text(close_msg.into())).await;
    let _ = write.close().await;

    let backed_up = per_pubkey.values().filter(|(_, ok)| *ok).count();
    Ok((backed_up, last_ts, last_event_id))
}

/// Check backup status for a relay, retrying on failure.
/// Total attempts = RELAY_MAX_ATTEMPTS (runtime-configurable).
async fn ws_check_descriptor_backup(
    relay_url: &str,
    pubkeys: &[PublicKey],
    d_tag: &str,
) -> Result<(usize, Option<i64>, Option<String>)> {
    let max_attempts = RELAY_MAX_ATTEMPTS.load(Ordering::Relaxed).max(1);
    let mut last_err = anyhow!("no attempts made");
    for attempt in 0..max_attempts {
        match ws_check_descriptor_backup_once(relay_url, pubkeys, d_tag).await {
            Ok(v) => return Ok(v),
            Err(e) => {
                last_err = e;
                if attempt + 1 < max_attempts {
                    tokio::time::sleep(Duration::from_millis(RETRY_DELAY_MS)).await;
                }
            }
        }
    }
    Err(last_err)
}

/// Inner implementation of ws_fetch_payloads_for_xpub — one attempt, no retry.
async fn ws_fetch_payloads_for_xpub_once(
    relay_url: &str,
    pubkey: &PublicKey,
) -> Result<Vec<Vec<u8>>> {
    let secs = RELAY_TIMEOUT_SECS.load(Ordering::Relaxed);
    let (mut write, mut read) = ws_open(relay_url, secs).await?.split();

    let sub_id = "dbl2";
    // Query by author + kind only — no #d filter so all descriptor backups
    // for this xpub are returned, even if the xpub appears in multiple wallets.
    let filter = Filter::new().kind(Kind::Custom(KIND)).author(*pubkey);

    let req_msg = serde_json::json!(["REQ", sub_id, filter]).to_string();
    if let Err(e) = write.send(Message::Text(req_msg.into())).await {
        let _ = write.close().await;
        return Err(anyhow!("send REQ: {e}"));
    }

    // Track the most recent event per d-tag (content may be empty = deleted).
    // Using `Option<Vec<u8>>` so we can distinguish "deleted" (None) from
    // "backup present" (Some(bytes)).
    let mut best_per_dtag: std::collections::HashMap<String, (i64, Option<Vec<u8>>)> =
        std::collections::HashMap::new();

    let _ = timeout(Duration::from_secs(secs), async {
        while let Some(msg_result) = read.next().await {
            if let Ok(Message::Text(text)) = msg_result {
                if let Ok(arr) = serde_json::from_str::<serde_json::Value>(&text) {
                    if arr[0] == "EOSE" {
                        break;
                    }
                    if arr[0] == "EVENT" && arr[1].as_str() == Some(sub_id) {
                        if let Some(ev) = arr.get(2) {
                            let ts = ev["created_at"].as_i64().unwrap_or(0);
                            if let Some(content) = ev["content"].as_str() {
                                // Key by d-tag so only the latest version of each
                                // backup slot is kept. Store None for empty content
                                // (deletion marker) so deleted slots are excluded.
                                let d_tag = ev["tags"]
                                    .as_array()
                                    .and_then(|tags| {
                                        tags.iter().find(|t| t[0].as_str() == Some("d"))
                                    })
                                    .and_then(|t| t[1].as_str())
                                    .unwrap_or("")
                                    .to_string();
                                let entry = best_per_dtag.entry(d_tag).or_insert((i64::MIN, None));
                                if ts >= entry.0 {
                                    let payload = if content.is_empty() {
                                        None
                                    } else {
                                        general_purpose::STANDARD.decode(content).ok()
                                    };
                                    *entry = (ts, payload);
                                }
                            }
                        }
                    }
                }
            }
        }
    })
    .await;

    let close_msg = serde_json::json!(["CLOSE", sub_id]).to_string();
    let _ = write.send(Message::Text(close_msg.into())).await;
    let _ = write.close().await;

    // Only return slots where the most recent event is a real backup (non-empty).
    Ok(best_per_dtag
        .into_values()
        .filter_map(|(_, payload)| payload)
        .collect())
}

/// Fetch all payload blobs for a relay, retrying on failure.
/// Total attempts = RELAY_MAX_ATTEMPTS (runtime-configurable).
async fn ws_fetch_payloads_for_xpub(relay_url: &str, pubkey: &PublicKey) -> Result<Vec<Vec<u8>>> {
    let max_attempts = RELAY_MAX_ATTEMPTS.load(Ordering::Relaxed).max(1);
    let mut last_err = anyhow!("no attempts made");
    for attempt in 0..max_attempts {
        match ws_fetch_payloads_for_xpub_once(relay_url, pubkey).await {
            Ok(v) => return Ok(v),
            Err(e) => {
                last_err = e;
                if attempt + 1 < max_attempts {
                    tokio::time::sleep(Duration::from_millis(RETRY_DELAY_MS)).await;
                }
            }
        }
    }
    Err(last_err)
}

// ---------------------------------------------------------------------------
// Public async functions (exposed via flutter_rust_bridge)
// ---------------------------------------------------------------------------

/// Publish an encrypted descriptor backup for every xpub in the wallet to all
/// configured Nostr relays. One event is published per xpub (each encrypted
/// for that xpub only), so any co-signer can independently locate and decrypt
/// their own backup using only their xpub.
///
/// Returns one `NostrRelayStatus` per relay URL. `has_backup = true` means
/// at least one xpub event was accepted by that relay.
pub async fn publish_nostr_backup(
    wallet_path: String,
    device_key_hex: String,
    open_password: Option<String>,
    relay_urls: Vec<String>,
) -> Result<Vec<NostrRelayStatus>> {
    let (_wallet_data_key, conn, row) = crate::core::wallet_info::open_snapshot(
        &wallet_path,
        &device_key_hex,
        open_password.as_deref(),
    )?;
    let descriptor_sigs = get_descriptor_sigs_as_json(&conn).unwrap_or(None);

    let xpub_map = super::extract_xpub_mfp_map(&row.descriptor);
    if xpub_map.is_empty() {
        return Err(anyhow!("No xpubs found in wallet descriptor"));
    }

    // Pre-build all (xpub, event) pairs so Argon2id runs on the calling thread
    // before we spawn tasks.
    let mut events: Vec<Event> = Vec::new();
    for (mfp, xpub) in &xpub_map {
        let payload = build_payload_for_xpub(
            &row.descriptor,
            &row.name,
            &row.network,
            mfp,
            xpub,
            row.created_at,
            descriptor_sigs.clone(),
        )?;
        let keys = derive_nostr_keypair(xpub)?;
        let d_tag = descriptor_d_tag(&row.descriptor);
        let event = build_nostr_event(&keys, &payload, &d_tag)?;
        events.push(event);
    }

    // Publish every event to every relay concurrently
    let mut handles = Vec::new();
    for relay_url in &relay_urls {
        for event in &events {
            let url = relay_url.clone();
            let ev = event.clone();
            handles.push(tokio::spawn(async move {
                let (ok, err) = ws_publish_event(&url, &ev).await;
                (url, ok, err)
            }));
        }
    }

    // Aggregate per-relay results
    let mut relay_ok: std::collections::HashMap<String, bool> =
        relay_urls.iter().map(|u| (u.clone(), false)).collect();
    let mut relay_err: std::collections::HashMap<String, String> = std::collections::HashMap::new();

    for handle in handles {
        if let Ok((url, ok, maybe_err)) = handle.await {
            if ok {
                relay_ok.insert(url, true);
            } else if let Some(e) = maybe_err {
                relay_err.entry(url).or_insert(e);
            }
        }
    }

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .map(|d| d.as_secs() as i64);

    let total_xpubs = xpub_map.len() as i64;

    let statuses = relay_urls
        .into_iter()
        .map(|url| {
            let ok = *relay_ok.get(&url).unwrap_or(&false);
            let err = if ok {
                None
            } else {
                relay_err.get(&url).cloned()
            };
            NostrRelayStatus {
                has_backup: ok,
                last_published_at: if ok { now } else { None },
                event_id: None,
                error: err,
                backed_up_xpubs: if ok { total_xpubs } else { 0 },
                total_xpubs,
                url,
            }
        })
        .collect();

    Ok(statuses)
}

/// Check which relays have a complete backup for this wallet.
///
/// `has_backup = true` means **every** xpub in the descriptor has published a
/// non-empty backup event with the matching d-tag on that relay.
/// `backed_up_xpubs` / `total_xpubs` give the exact per-cosigner breakdown
/// so the UI can distinguish "all backed up", "some backed up", and "none".
pub async fn check_nostr_backup_status(
    descriptor: String,
    relay_urls: Vec<String>,
) -> Result<Vec<NostrRelayStatus>> {
    let xpub_map = super::extract_xpub_mfp_map(&descriptor);
    if xpub_map.is_empty() {
        return Err(anyhow!("No xpubs in descriptor"));
    }

    let total_xpubs = xpub_map.len() as i64;
    let d_tag = descriptor_d_tag(&descriptor);

    // Derive the Nostr pubkeys for all xpubs in this descriptor.
    let pubkeys: Vec<PublicKey> = xpub_map
        .values()
        .map(|xpub| {
            let keys = derive_nostr_keypair(xpub)?;
            Ok(keys.public_key())
        })
        .collect::<Result<Vec<_>>>()?;

    let mut handles = Vec::new();
    for relay_url in &relay_urls {
        let url = relay_url.clone();
        let pks = pubkeys.clone();
        let dtag = d_tag.clone();
        handles.push(tokio::spawn(async move {
            let result = ws_check_descriptor_backup(&url, &pks, &dtag).await;
            (url, result)
        }));
    }

    let mut statuses = Vec::new();
    for handle in handles {
        if let Ok((url, result)) = handle.await {
            match result {
                Ok((backed_up, last_at, event_id)) => {
                    let backed_up_xpubs = backed_up as i64;
                    statuses.push(NostrRelayStatus {
                        url,
                        has_backup: backed_up_xpubs == total_xpubs,
                        last_published_at: last_at,
                        event_id,
                        error: None,
                        backed_up_xpubs,
                        total_xpubs,
                    });
                }
                Err(e) => {
                    statuses.push(NostrRelayStatus {
                        url,
                        has_backup: false,
                        last_published_at: None,
                        event_id: None,
                        error: Some(e.to_string()),
                        backed_up_xpubs: 0,
                        total_xpubs,
                    });
                }
            }
        }
    }

    Ok(statuses)
}

/// Overwrite this wallet's backup on each relay with an empty placeholder event.
///
/// Kind 30078 is an addressable (parameterized-replaceable) event: publishing a
/// new event with the same author pubkey and d-tag replaces the previous one.
/// This is more reliable than NIP-09 deletion requests, which many relays ignore.
///
/// For every xpub in the descriptor an empty kind-30078 event is signed with the
/// derived Nostr keypair and published to each relay URL.
/// Returns one `NostrRelayStatus` per relay — `has_backup` reflects
/// whether the replacement was accepted (relay returned `["OK", id, true]`).
pub async fn delete_nostr_backup(
    descriptor: String,
    relay_urls: Vec<String>,
) -> Result<Vec<NostrRelayStatus>> {
    let xpub_map = super::extract_xpub_mfp_map(&descriptor);
    if xpub_map.is_empty() {
        return Err(anyhow!("No xpubs found in wallet descriptor"));
    }

    let d_tag = descriptor_d_tag(&descriptor);

    // Build one empty replacement event per xpub keypair.
    // Same kind and d-tag as the original backup → relay replaces it.
    let mut events: Vec<Event> = Vec::new();
    for xpub in xpub_map.values() {
        let keys = derive_nostr_keypair(xpub)?;
        let event = EventBuilder::new(Kind::Custom(KIND), "")
            .tag(Tag::identifier(&d_tag))
            .sign_with_keys(&keys)
            .map_err(|e| anyhow!("replacement event signing: {e}"))?;
        events.push(event);
    }

    // Publish to every relay.
    let mut handles = Vec::new();
    for relay_url in &relay_urls {
        for event in &events {
            let url = relay_url.clone();
            let ev = event.clone();
            handles.push(tokio::spawn(async move {
                let (ok, err) = ws_publish_event(&url, &ev).await;
                (url, ok, err)
            }));
        }
    }

    let mut relay_ok: std::collections::HashMap<String, bool> =
        relay_urls.iter().map(|u| (u.clone(), false)).collect();
    let mut relay_err: std::collections::HashMap<String, String> = std::collections::HashMap::new();

    for handle in handles {
        if let Ok((url, ok, maybe_err)) = handle.await {
            if ok {
                relay_ok.insert(url, true);
            } else if let Some(e) = maybe_err {
                relay_err.entry(url).or_insert(e);
            }
        }
    }

    let total_xpubs = xpub_map.len() as i64;

    let statuses = relay_urls
        .into_iter()
        .map(|url| {
            let ok = *relay_ok.get(&url).unwrap_or(&false);
            NostrRelayStatus {
                // Deletion published an empty event — no real backup exists regardless.
                has_backup: false,
                last_published_at: None,
                event_id: None,
                error: if ok {
                    None
                } else {
                    relay_err.get(&url).cloned()
                },
                backed_up_xpubs: 0,
                total_xpubs,
                url,
            }
        })
        .collect();

    Ok(statuses)
}

/// Fetch all Nostr backups for a given xpub and decrypt each one to extract
/// metadata and the first external address.
///
/// One xpub can back up multiple distinct wallet descriptors (e.g. the same
/// hardware wallet key participates in several multisigs). This function returns
/// one `NostrBackupResponse` per distinct descriptor found on the relays.
/// Discovery requires only the xpub — no prior knowledge of the d-tag.
pub async fn fetch_nostr_backup(
    xpub: String,
    relay_urls: Vec<String>,
) -> Result<Vec<NostrBackupResponse>> {
    // Strip any keyspec prefix ([mfp/path]) — the Nostr keypair is derived
    // from the bare xpub only, matching how publish_nostr_backup works.
    let (_, bare_xpub) = parse_xpub_credential(&xpub);
    let keys = derive_nostr_keypair(bare_xpub)?;
    let pubkey = keys.public_key();

    // Collect all payload blobs from the first relay that has any.
    // Track whether at least one relay was reachable so we can distinguish
    // "no backup exists" from "network error — backup may exist but unreachable".
    let mut all_blobs: Vec<Vec<u8>> = Vec::new();
    let mut any_relay_reachable = false;
    for relay_url in &relay_urls {
        match ws_fetch_payloads_for_xpub(relay_url, &pubkey).await {
            Ok(blobs) => {
                any_relay_reachable = true;
                if !blobs.is_empty() {
                    all_blobs = blobs;
                    break;
                }
            }
            Err(_) => continue,
        }
    }

    if all_blobs.is_empty() {
        if any_relay_reachable {
            return Err(anyhow!("No backup found on any of the configured relays"));
        } else {
            return Err(anyhow!("No relay could be reached"));
        }
    }

    let mut responses: Vec<NostrBackupResponse> = Vec::new();

    for bytes in all_blobs {
        // Parse and decrypt each payload; skip silently if malformed or
        // if the xpub does not match (e.g. a co-signer's backup fetched
        // from a shared relay that happens to return unrelated events).
        let Ok(payload) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
            continue;
        };
        if payload["version"].as_u64() != Some(1) {
            continue;
        }
        if payload["protection"]["type"].as_u64() != Some(2) {
            continue;
        }
        let Ok(slots) = payload["protection"]["slots"]
            .as_array()
            .ok_or(())
            .and_then(|arr| {
                arr.iter()
                    .map(|s| serde_json::from_value::<XpubSlot>(s.clone()).map_err(|_| ()))
                    .collect::<Result<Vec<_>, _>>()
            })
        else {
            continue;
        };
        let Ok(export_data_key) = resolve_xpub_data_key(&xpub, &slots) else {
            continue;
        };
        let Some(data_b64) = payload["data"].as_str() else {
            continue;
        };
        let Ok(encrypted_inner) = general_purpose::STANDARD.decode(data_b64) else {
            continue;
        };
        let Ok(inner_bytes) = decrypt_bytes(&export_data_key, &encrypted_inner) else {
            continue;
        };
        let Ok(inner) = serde_json::from_slice::<serde_json::Value>(&inner_bytes) else {
            continue;
        };
        let Some(descriptor) = inner["descriptor"].as_str() else {
            continue;
        };

        let wallet_name = payload["wallet_name"].as_str().map(String::from);
        let network_str = payload["network"].as_str().map(String::from);
        let created_at = payload["created_at"].as_i64();

        let network = network_str
            .as_ref()
            .and_then(|n| n.as_str().try_into().ok())
            .unwrap_or(crate::api::model::APINetwork::Bitcoin);
        let first_address =
            super::discovery::first_address_from_descriptor(descriptor.to_string(), network).ok();
        let wallet_type = crate::core::descriptor::DescriptorAnalyzer::analyze(descriptor)
            .map(|a| crate::api::model::APIWalletType::from(a.wallet_type()))
            .unwrap_or(crate::api::model::APIWalletType::Unknown);
        let descriptor_sig_verification = Some(verify_descriptor_sigs_from_payload(
            &inner, descriptor, bare_xpub,
        ));

        responses.push(NostrBackupResponse {
            bytes,
            wallet_name,
            network: network_str,
            created_at,
            first_address,
            wallet_type: Some(wallet_type),
            descriptor: Some(descriptor.to_string()),
            descriptor_sig_verification,
        });
    }

    if responses.is_empty() {
        return Err(anyhow!("No backup found on any of the configured relays"));
    }

    // Sort most-recently-published first.
    responses.sort_by_key(|r| std::cmp::Reverse(r.created_at));

    Ok(responses)
}

/// Decrypt a Nostr backup payload and create a new wallet from the recovered
/// descriptor. The wallet is created as DeviceKey-protected (watch-only until
/// the user reconnects their hardware wallet or re-enters their mnemonic).
///
/// `xpub_credential`: bare xpub or `[mfp/path]xpub` keyspec.
pub async fn import_nostr_backup(
    backup_bytes: Vec<u8>,
    xpub_credential: String,
    device_key_hex: String,
    wallets_dir: String,
    wallet_name_override: Option<String>,
    network_hint: String,
) -> Result<NostrImportResult> {
    let payload: serde_json::Value = serde_json::from_slice(&backup_bytes)
        .map_err(|e| anyhow!("Invalid Nostr backup format: {e}"))?;

    let version = payload["version"]
        .as_u64()
        .ok_or_else(|| anyhow!("Missing version in Nostr backup"))?;
    if version != 1 {
        return Err(anyhow!("Unsupported Nostr backup version: {version}"));
    }

    let ptype = payload["protection"]["type"].as_u64().unwrap_or(0);
    if ptype != 2 {
        return Err(anyhow!(
            "Unexpected protection type in Nostr backup: {ptype}"
        ));
    }

    let slots: Vec<XpubSlot> = payload["protection"]["slots"]
        .as_array()
        .ok_or_else(|| anyhow!("Missing slots in Nostr backup"))?
        .iter()
        .map(|s| serde_json::from_value(s.clone()))
        .collect::<Result<_, _>>()
        .map_err(|e| anyhow!("Invalid slot in Nostr backup: {e}"))?;

    let export_data_key = resolve_xpub_data_key(&xpub_credential, &slots)
        .map_err(|_| anyhow!("xpub does not match any slot in this backup"))?;

    let data_b64 = payload["data"]
        .as_str()
        .ok_or_else(|| anyhow!("Missing data in Nostr backup"))?;
    let encrypted_inner = general_purpose::STANDARD
        .decode(data_b64)
        .map_err(|e| anyhow!("base64 decode: {e}"))?;
    let inner_bytes = decrypt_bytes(&export_data_key, &encrypted_inner)?;

    let inner: serde_json::Value =
        serde_json::from_slice(&inner_bytes).map_err(|e| anyhow!("inner JSON decode: {e}"))?;
    let descriptor = inner["descriptor"]
        .as_str()
        .ok_or_else(|| anyhow!("Missing descriptor in Nostr backup"))?
        .to_string();

    // Determine wallet name
    let name = wallet_name_override
        .filter(|n| !n.trim().is_empty())
        .unwrap_or_else(|| {
            payload["wallet_name"]
                .as_str()
                .unwrap_or("Restored Wallet")
                .to_string()
        });

    // Priority: payload > hint > descriptor analysis > "bitcoin"
    let network_str: String = payload["network"]
        .as_str()
        .and_then(|n| crate::api::model::APINetwork::try_from(n).ok())
        .map(|n| n.as_str().to_string())
        .or_else(|| {
            crate::api::model::APINetwork::try_from(network_hint.as_str())
                .ok()
                .map(|n| n.as_str().to_string())
        })
        .or_else(|| {
            crate::core::descriptor::DescriptorAnalyzer::analyze(&descriptor)
                .ok()
                .map(|a| {
                    crate::api::model::APINetwork::from(a.network())
                        .as_str()
                        .to_string()
                })
        })
        .unwrap_or("bitcoin".to_string());

    // Create the wallet (DeviceKey-protected — watch-only)
    let (path, row) = create_wallet_db(
        &wallets_dir,
        &name,
        &descriptor,
        &network_str,
        &device_key_hex,
        WalletProtectionRequest::DeviceKey,
    )?;

    let wallet = super::row_to_api_info(path, row)?;
    Ok(NostrImportResult { wallet })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
#[path = "nostr_backup_tests.rs"]
mod tests;
