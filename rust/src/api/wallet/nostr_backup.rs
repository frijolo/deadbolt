use super::*;

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
// Discovery: fetching all events for an xpub requires only the derived pubkey —
// no d-tag knowledge needed. A single REQ (kinds=[30078], authors=[pubkey])
// returns every descriptor backed up under that xpub.
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
use std::time::Duration;
use tokio::time::timeout;
use tokio_tungstenite::{connect_async, tungstenite::Message};

use crate::core::key_protection::{
    decrypt_bytes, encrypt_bytes, generate_data_key, resolve_xpub_data_key, wrap_with_xpub,
    XpubSlot,
};
use crate::core::wallet_info::{create_wallet_db, resolve_wallet_key, WalletProtectionRequest};

type HmacSha256 = Hmac<Sha256>;

const D_TAG_PREFIX: &str = "deadbolt-backup";
const KIND: u16 = 30078;
const CONNECT_TIMEOUT_SECS: u64 = 10;
const FETCH_TIMEOUT_SECS: u64 = 15;
// Standard Argon2id parameters for Nostr payload encryption (same as file backup "Standard" level).
const M_COST: u32 = 65536;
const T_COST: u32 = 3;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Status of a Nostr relay for one wallet's backup.
pub struct NostrRelayStatus {
    pub url: String,
    /// True if at least one xpub backup event was confirmed on this relay.
    pub has_backup: bool,
    /// Unix timestamp of the most recent event found (or published).
    pub last_published_at: Option<i64>,
    /// Event ID of the most recent event found.
    pub event_id: Option<String>,
    /// Non-null when the relay could not be reached or returned an error.
    pub error: Option<String>,
}

/// Response from `fetch_nostr_backup` with full metadata including first address.
pub struct NostrBackupResponse {
    pub bytes: Vec<u8>,
    pub wallet_name: Option<String>,
    pub network: Option<String>,
    pub created_at: Option<i64>,
    pub first_address: Option<String>,
    pub wallet_type: Option<crate::api::model::APIWalletType>,
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
) -> Result<Vec<u8>> {
    // Inner plaintext: just the descriptor
    let inner = serde_json::json!({ "descriptor": descriptor });
    let inner_bytes = serde_json::to_vec(&inner)?;

    // Fresh export data key per backup
    let export_data_key = generate_data_key();

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

/// Publish a signed event JSON string to a relay.
/// Returns `(success, error)`. Success means the relay returned `["OK", id, true, ...]`.
async fn ws_publish_event(relay_url: &str, event: &Event) -> (bool, Option<String>) {
    let msg = match serde_json::to_string(&serde_json::json!(["EVENT", event])) {
        Ok(m) => m,
        Err(e) => return (false, Some(format!("serialize: {e}"))),
    };

    let connect_result = timeout(
        Duration::from_secs(CONNECT_TIMEOUT_SECS),
        connect_async(relay_url),
    )
    .await;

    let (ws_stream, _) = match connect_result {
        Ok(Ok(ws)) => ws,
        Ok(Err(e)) => return (false, Some(format!("connect: {e}"))),
        Err(_) => return (false, Some("connection timeout".to_string())),
    };

    let (mut write, mut read) = ws_stream.split();

    if let Err(e) = write.send(Message::Text(msg.into())).await {
        let _ = write.close().await;
        return (false, Some(format!("send: {e}")));
    }

    let event_id = event.id.to_hex();
    let mut success = false;
    let mut relay_error: Option<String> = None;

    let _ = timeout(Duration::from_secs(FETCH_TIMEOUT_SECS), async {
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

/// Query a relay for backup events authored by one of the given Nostr pubkeys.
/// Returns `(has_backup, last_timestamp, event_id)`.
async fn ws_fetch_backup(
    relay_url: &str,
    pubkeys: &[PublicKey],
) -> Result<(bool, Option<i64>, Option<String>)> {
    let connect_result = timeout(
        Duration::from_secs(CONNECT_TIMEOUT_SECS),
        connect_async(relay_url),
    )
    .await;

    let (ws_stream, _) = match connect_result {
        Ok(Ok(ws)) => ws,
        Ok(Err(e)) => return Err(anyhow!("connect: {e}")),
        Err(_) => return Err(anyhow!("connection timeout")),
    };

    let (mut write, mut read) = ws_stream.split();

    // Build REQ filter: kind 30078, any of our pubkeys.
    // No #d filter — one pubkey can hold multiple descriptor backups with
    // distinct d-tags; querying by author+kind returns all of them.
    let sub_id = "dbl1";
    let filter = Filter::new()
        .kind(Kind::Custom(KIND))
        .authors(pubkeys.to_vec());

    let req_msg = serde_json::json!(["REQ", sub_id, filter]).to_string();

    if let Err(e) = write.send(Message::Text(req_msg.into())).await {
        let _ = write.close().await;
        return Err(anyhow!("send REQ: {e}"));
    }

    let mut best_timestamp: Option<i64> = None;
    let mut best_event_id: Option<String> = None;

    let _ = timeout(Duration::from_secs(FETCH_TIMEOUT_SECS), async {
        while let Some(msg_result) = read.next().await {
            if let Ok(Message::Text(text)) = msg_result {
                if let Ok(arr) = serde_json::from_str::<serde_json::Value>(&text) {
                    if arr[0] == "EOSE" {
                        break;
                    }
                    if arr[0] == "EVENT" && arr[1].as_str() == Some(sub_id) {
                        if let Some(ev) = arr.get(2) {
                            let ts = ev["created_at"].as_i64().unwrap_or(0);
                            if best_timestamp.is_none_or(|prev| ts > prev) {
                                best_timestamp = Some(ts);
                                best_event_id = ev["id"].as_str().map(|s| s.to_string());
                            }
                        }
                    }
                }
            }
        }
    })
    .await;

    // Close subscription
    let close_msg = serde_json::json!(["CLOSE", sub_id]).to_string();
    let _ = write.send(Message::Text(close_msg.into())).await;
    let _ = write.close().await;

    let has_backup = best_timestamp.is_some();
    Ok((has_backup, best_timestamp, best_event_id))
}

/// Fetch all raw payload blobs for a single xpub from a relay.
///
/// Returns one entry per distinct descriptor backed up under this xpub.
/// No `#d` filter is applied — all kind-30078 events authored by the derived
/// pubkey are returned, regardless of their d-tag.
async fn ws_fetch_payloads_for_xpub(relay_url: &str, pubkey: &PublicKey) -> Result<Vec<Vec<u8>>> {
    let connect_result = timeout(
        Duration::from_secs(CONNECT_TIMEOUT_SECS),
        connect_async(relay_url),
    )
    .await;

    let (ws_stream, _) = match connect_result {
        Ok(Ok(ws)) => ws,
        Ok(Err(e)) => return Err(anyhow!("connect: {e}")),
        Err(_) => return Err(anyhow!("connection timeout")),
    };

    let (mut write, mut read) = ws_stream.split();

    let sub_id = "dbl2";
    // Query by author + kind only — no #d filter so all descriptor backups
    // for this xpub are returned, even if the xpub appears in multiple wallets.
    let filter = Filter::new().kind(Kind::Custom(KIND)).author(*pubkey);

    let req_msg = serde_json::json!(["REQ", sub_id, filter]).to_string();
    if let Err(e) = write.send(Message::Text(req_msg.into())).await {
        let _ = write.close().await;
        return Err(anyhow!("send REQ: {e}"));
    }

    // Track the most recent payload per d-tag to deduplicate re-published backups.
    let mut best_per_dtag: std::collections::HashMap<String, (i64, Vec<u8>)> =
        std::collections::HashMap::new();

    let _ = timeout(Duration::from_secs(FETCH_TIMEOUT_SECS), async {
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
                                if let Ok(bytes) = general_purpose::STANDARD.decode(content) {
                                    // Key by d-tag so only the latest version of each
                                    // backup slot is kept.
                                    let d_tag = ev["tags"]
                                        .as_array()
                                        .and_then(|tags| {
                                            tags.iter().find(|t| t[0].as_str() == Some("d"))
                                        })
                                        .and_then(|t| t[1].as_str())
                                        .unwrap_or("")
                                        .to_string();
                                    let entry =
                                        best_per_dtag.entry(d_tag).or_insert((i64::MIN, vec![]));
                                    if ts >= entry.0 {
                                        *entry = (ts, bytes);
                                    }
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

    Ok(best_per_dtag.into_values().map(|(_, b)| b).collect())
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
    let wallet_data_key =
        resolve_wallet_key(&wallet_path, &device_key_hex, open_password.as_deref())?;
    let row = {
        let conn = open_encrypted_connection(&wallet_path, &wallet_data_key)?;
        read_wallet_info(&conn)?
    };

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
                url,
            }
        })
        .collect();

    Ok(statuses)
}

/// Check which relays have a backup event for this wallet. One status per relay.
/// `has_backup = true` means the relay has at least one xpub event for this wallet.
pub async fn check_nostr_backup_status(
    descriptor: String,
    relay_urls: Vec<String>,
) -> Result<Vec<NostrRelayStatus>> {
    let xpub_map = super::extract_xpub_mfp_map(&descriptor);
    if xpub_map.is_empty() {
        return Err(anyhow!("No xpubs in descriptor"));
    }

    // Derive the Nostr pubkeys for all xpubs
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
        handles.push(tokio::spawn(async move {
            let result = ws_fetch_backup(&url, &pks).await;
            (url, result)
        }));
    }

    let mut statuses = Vec::new();
    for handle in handles {
        if let Ok((url, result)) = handle.await {
            match result {
                Ok((has_backup, last_at, event_id)) => {
                    statuses.push(NostrRelayStatus {
                        url,
                        has_backup,
                        last_published_at: last_at,
                        event_id,
                        error: None,
                    });
                }
                Err(e) => {
                    statuses.push(NostrRelayStatus {
                        url,
                        has_backup: false,
                        last_published_at: None,
                        event_id: None,
                        error: Some(e.to_string()),
                    });
                }
            }
        }
    }

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
    let keys = derive_nostr_keypair(&xpub)?;
    let pubkey = keys.public_key();

    // Collect all payload blobs from the first relay that has any.
    let mut all_blobs: Vec<Vec<u8>> = Vec::new();
    for relay_url in &relay_urls {
        match ws_fetch_payloads_for_xpub(relay_url, &pubkey).await {
            Ok(blobs) if !blobs.is_empty() => {
                all_blobs = blobs;
                break;
            }
            _ => continue,
        }
    }

    if all_blobs.is_empty() {
        return Err(anyhow!("No backup found on any of the configured relays"));
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
        let wallet_type = super::discovery::wallet_type_from_descriptor(descriptor);

        responses.push(NostrBackupResponse {
            bytes,
            wallet_name,
            network: network_str,
            created_at,
            first_address,
            wallet_type: Some(wallet_type),
        });
    }

    if responses.is_empty() {
        return Err(anyhow!("No backup found on any of the configured relays"));
    }

    // Sort most-recently-published first.
    responses.sort_by(|a, b| b.created_at.cmp(&a.created_at));

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
) -> Result<APIWalletInfo> {
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

    // Determine network
    let network_str = payload["network"].as_str().unwrap_or("bitcoin");

    // Create the wallet (DeviceKey-protected — watch-only)
    let (path, row) = create_wallet_db(
        &wallets_dir,
        &name,
        &descriptor,
        network_str,
        &device_key_hex,
        WalletProtectionRequest::DeviceKey,
    )?;

    super::row_to_api_info(path, row)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_derive_nostr_keypair_deterministic() {
        let xpub = "xpub6C5sJJ3iZxbkUDa4zMBGEPfUuQScT6eEJPZGUBJvFrLwS7T6cjvzGTjK9h8hmz";
        let k1 = derive_nostr_keypair(xpub).unwrap();
        let k2 = derive_nostr_keypair(xpub).unwrap();
        assert_eq!(k1.public_key(), k2.public_key());
    }

    #[test]
    fn test_derive_nostr_keypair_different_xpubs() {
        let k1 = derive_nostr_keypair("xpubAAA").unwrap();
        let k2 = derive_nostr_keypair("xpubBBB").unwrap();
        assert_ne!(k1.public_key(), k2.public_key());
    }

    #[test]
    fn test_descriptor_d_tag_format() {
        let desc = "wpkh([deadbeef/84'/0'/0']xpub6C5s.../<0;1>/*)";
        let tag = descriptor_d_tag(desc);
        assert!(tag.starts_with("deadbolt-backup-"), "tag: {tag}");
        // fingerprint is 8 lowercase hex chars
        let fingerprint = tag.strip_prefix("deadbolt-backup-").unwrap();
        assert_eq!(fingerprint.len(), 8);
        assert!(fingerprint.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_descriptor_d_tag_different_descriptors() {
        let t1 = descriptor_d_tag("wpkh([aabb/84'/0'/0']xpub6Aaa.../<0;1>/*)");
        let t2 = descriptor_d_tag("wpkh([aabb/84'/0'/1']xpub6Aaa.../<0;1>/*)");
        assert_ne!(t1, t2, "different descriptors must yield different d-tags");
    }

    #[test]
    fn test_descriptor_d_tag_same_descriptor_deterministic() {
        let desc = "wpkh([deadbeef/84'/0'/0']xpub6C5s.../<0;1>/*)";
        assert_eq!(descriptor_d_tag(desc), descriptor_d_tag(desc));
    }

    #[test]
    fn test_payload_roundtrip() {
        let descriptor = "wpkh([deadbeef/84'/0'/0']xpub6C5sJJ3iZxbkUDa4zMBGEPfUuQScT6eEJPZGUBJvFrLwS7T6cjvzGTjK9h8hmzXmqVbHD5sS9Kf2hHimLMjMiUZFrCHn5qGVmCNBHHxr1/<0;1>/*)";
        let xpub = "xpub6C5sJJ3iZxbkUDa4zMBGEPfUuQScT6eEJPZGUBJvFrLwS7T6cjvzGTjK9h8hmzXmqVbHD5sS9Kf2hHimLMjMiUZFrCHn5qGVmCNBHHxr1";
        let mfp = "deadbeef";
        let payload_bytes =
            build_payload_for_xpub(descriptor, "Test Wallet", "bitcoin", mfp, xpub, 0).unwrap();

        // Verify structure
        let payload: serde_json::Value = serde_json::from_slice(&payload_bytes).unwrap();
        assert_eq!(payload["version"], 1);
        assert_eq!(payload["wallet_name"], "Test Wallet");
        assert_eq!(payload["network"], "bitcoin");
        assert_eq!(payload["protection"]["type"], 2);
        assert!(payload["protection"]["slots"].as_array().unwrap().len() == 1);

        // Verify decryptable with the xpub
        let slots: Vec<XpubSlot> = payload["protection"]["slots"]
            .as_array()
            .unwrap()
            .iter()
            .map(|s| serde_json::from_value(s.clone()).unwrap())
            .collect();
        let export_key = resolve_xpub_data_key(xpub, &slots).unwrap();

        let data_b64 = payload["data"].as_str().unwrap();
        let encrypted = general_purpose::STANDARD.decode(data_b64).unwrap();
        let inner_bytes = decrypt_bytes(&export_key, &encrypted).unwrap();
        let inner: serde_json::Value = serde_json::from_slice(&inner_bytes).unwrap();
        assert_eq!(inner["descriptor"].as_str().unwrap(), descriptor);
    }
}
