use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use rand::rngs::OsRng;
use rand::TryRngCore;
use zeroize::Zeroizing;

use crate::api::model::{APINetwork, APIProtectionType, APISecurityLevel};
use crate::core::key_protection::{
    biometric_slots, biometric_slots_mut, generate_data_key, generate_salt, resolve_data_key,
    resolve_xpub_data_key, unwrap_biometric_slots, wrap_key, wrap_with_xpub, BiometricSlot,
    ProtectionMeta, DEFAULT_P_COST,
};
use crate::core::wallet_meta::{read_meta, write_meta};
use crate::core::wallet_persistence::{
    load_or_create_wallet, open_encrypted_connection, read_wallet_info, rekey_database,
    upsert_wallet_info, WalletInfoRow,
};

/// Format 16 bytes as a UUID v4 string (8-4-4-4-12 hex groups).
fn bytes_to_uuid(bytes: &[u8; 16]) -> String {
    let hex = hex::encode(bytes);
    let mut uuid = String::with_capacity(36);
    // UUID layout: 8-4-4-4-12. Insert dashes after these hex char counts.
    let dash_after = [8, 12, 16, 20];
    let mut di = 0;
    for (i, c) in hex.chars().enumerate() {
        if di < dash_after.len() && i == dash_after[di] {
            uuid.push('-');
            di += 1;
        }
        uuid.push(c);
    }
    uuid
}

pub fn generate_uuid_v4() -> Result<String> {
    let mut bytes = [0u8; 16];
    OsRng
        .try_fill_bytes(&mut bytes)
        .map_err(|e| anyhow::anyhow!("OS RNG failed: {e}"))?;
    // Set version 4 and RFC 4122 variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    Ok(bytes_to_uuid(&bytes))
}

/// How to protect the per-wallet data key.
pub enum WalletProtectionRequest {
    /// Wrap with the device key (Type 0).
    DeviceKey,
    /// Derive wrapping key from password via Argon2id (Type 1).
    UserPassword {
        password: String,
        m_cost: u32,
        t_cost: u32,
    },
    /// Wrap with each xpub in the descriptor; any one can unlock (Type 2).
    /// `xpub_slots`: list of `(mfp, xpub, derivation)` triples extracted from the descriptor.
    XpubKey {
        xpub_slots: Vec<(String, String, String)>,
        m_cost: u32,
        t_cost: u32,
    },
}

/// Create a new wallet .db file with a UUID filename, initialize BDK tables,
/// write the wallet_info row, and create the .meta sidecar.
/// Returns (absolute_path, WalletInfoRow).
pub fn create_wallet_db(
    wallets_dir: &str,
    name: &str,
    descriptor: &str,
    network_str: &str,
    device_key_hex: &str,
    protection: WalletProtectionRequest,
) -> Result<(String, WalletInfoRow)> {
    use std::path::Path;

    std::fs::create_dir_all(wallets_dir)?;

    let uuid = generate_uuid_v4()?;
    let path = Path::new(wallets_dir).join(format!("{}.db", uuid));
    let path_str = path.to_string_lossy().to_string();

    let created_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;

    let api_network = crate::api::model::APINetwork::try_from(network_str)?;
    let network: bdk_wallet::bitcoin::Network = api_network.into();
    let addr_hash = hash_first_address(descriptor, api_network);

    // Generate a unique per-wallet data key
    let data_key = Zeroizing::new(generate_data_key()?);

    // Initialize BDK tables in the encrypted SQLite file using the data key
    let (_wallet, conn) = load_or_create_wallet(&path_str, descriptor, network, &data_key)?;

    // Write metadata row
    upsert_wallet_info(&conn, name, descriptor, network_str, created_at)?;

    // Build and write the protection meta sidecar
    let meta = build_protection_meta(
        &data_key,
        device_key_hex,
        protection,
        Some(name),
        Some(network_str),
        addr_hash.as_deref(),
    )?;
    write_meta(&path_str, &meta)?;

    let row = WalletInfoRow {
        name: name.to_string(),
        descriptor: descriptor.to_string(),
        network: network_str.to_string(),
        created_at,
        last_synced_at: None,
        first_address_hash: None,
    };

    Ok((path_str, row))
}

/// Build the `ProtectionMeta` for the given protection request.
pub fn build_protection_meta(
    data_key: &str,
    device_key_hex: &str,
    protection: WalletProtectionRequest,
    display_name: Option<&str>,
    network: Option<&str>,
    first_address_hash: Option<&str>,
) -> Result<ProtectionMeta> {
    match protection {
        WalletProtectionRequest::DeviceKey => {
            let wrapped_key = wrap_key(data_key, device_key_hex)?;
            Ok(ProtectionMeta::DeviceKey {
                version: 1,
                wrapped_key,
            })
        }
        WalletProtectionRequest::UserPassword {
            password,
            m_cost,
            t_cost,
        } => {
            use crate::core::key_protection::derive_key_from_password;
            let salt = generate_salt()?;
            let wrapping_key =
                derive_key_from_password(&password, &salt, m_cost, t_cost, DEFAULT_P_COST)?;
            let wrapped_key = wrap_key(data_key, &wrapping_key)?;
            Ok(ProtectionMeta::UserPassword {
                version: 1,
                salt,
                m_cost,
                t_cost,
                p_cost: DEFAULT_P_COST,
                wrapped_key,
                display_name: display_name.map(|s| s.to_string()),
                network: network.map(|s| s.to_string()),
                last_synced_at: None,
                biometric_slots: vec![],
                first_address_hash: first_address_hash.map(|s| s.to_string()),
            })
        }
        WalletProtectionRequest::XpubKey {
            xpub_slots,
            m_cost,
            t_cost,
        } => {
            if xpub_slots.is_empty() {
                return Err(anyhow::anyhow!(
                    "XpubKey protection requires at least one xpub"
                ));
            }
            let slots = xpub_slots
                .iter()
                .map(|(mfp, xpub, derivation)| {
                    wrap_with_xpub(mfp, xpub, data_key, m_cost, t_cost, derivation)
                })
                .collect::<Result<Vec<_>>>()?;
            Ok(ProtectionMeta::XpubKey {
                version: 1,
                slots,
                display_name: display_name.map(|s| s.to_string()),
                network: network.map(|s| s.to_string()),
                last_synced_at: None,
                biometric_slots: vec![],
                first_address_hash: first_address_hash.map(|s| s.to_string()),
            })
        }
    }
}

/// Open a wallet and return its data key by resolving the protection meta.
/// - For DeviceKey wallets: pass `password = None`.
/// - For UserPassword wallets: pass `password = Some("user-password")`.
/// - For XpubKey wallets: pass `password = Some("xpub or [mfp/path]xpub")`.
/// - `biometric_key`: optional 32-byte hex key retrieved from the platform keystore.
///   When provided, biometric slots are tried first before falling back to the
///   password/xpub credential.
pub fn resolve_wallet_key(
    wallet_path: &str,
    device_key_hex: &str,
    password: Option<&str>,
    biometric_key: Option<&str>,
) -> Result<String> {
    let meta = read_meta(wallet_path)?;

    // Try biometric slots first when a key is provided.
    if let Some(bio_key) = biometric_key {
        let bio_slots: &[BiometricSlot] = match &meta {
            ProtectionMeta::UserPassword {
                biometric_slots, ..
            } => biometric_slots,
            ProtectionMeta::XpubKey {
                biometric_slots, ..
            } => biometric_slots,
            _ => &[],
        };
        if !bio_slots.is_empty() {
            return unwrap_biometric_slots(bio_key, bio_slots);
        }
    }

    match &meta {
        ProtectionMeta::DeviceKey { .. } => resolve_data_key(&meta, device_key_hex),
        ProtectionMeta::UserPassword { .. } => {
            let pwd =
                password.ok_or_else(|| anyhow::anyhow!("Password required to open this wallet"))?;
            resolve_data_key(&meta, pwd)
        }
        ProtectionMeta::XpubKey { slots, .. } => {
            let credential =
                password.ok_or_else(|| anyhow::anyhow!("xpub required to open this wallet"))?;
            resolve_xpub_data_key(credential, slots)
        }
    }
}

/// Scan all *.db files in wallets_dir, auto-migrate legacy wallets (no .meta),
/// and return wallet info rows sorted newest-first. Unreadable files are skipped.
pub fn list_wallets_in_dir(
    wallets_dir: &str,
    device_key_hex: &str,
) -> Vec<(String, WalletInfoRow)> {
    let dir = match std::fs::read_dir(wallets_dir) {
        Ok(d) => d,
        Err(_) => return vec![],
    };

    let mut results = vec![];
    for entry in dir.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("db") {
            continue;
        }
        let path_str = path.to_string_lossy().to_string();

        // Read the .meta sidecar (single filesystem read per wallet).
        // If absent, the wallet predates the key-envelope format — migrate it first.
        let meta = match read_meta(&path_str) {
            Ok(m) => m,
            Err(_) => {
                if let Err(e) = migrate_legacy_wallet(&path_str, device_key_hex) {
                    // Soft failure: skip unmigratable wallets rather than aborting list().
                    // Output to stderr (logcat on Android) until a proper log crate is wired up.
                    eprintln!("Wallet migration skipped for '{}': {}", path_str, e);
                    continue;
                }
                match read_meta(&path_str) {
                    Ok(m) => m,
                    Err(_) => continue,
                }
            }
        };

        // UserPassword and XpubKey wallets: include them as locked entries so they
        // appear in the list with a lock indicator. Name and network come from the
        // meta sidecar (written at creation time and refreshed on open).
        let locked_row = match &meta {
            ProtectionMeta::UserPassword {
                display_name,
                network,
                last_synced_at,
                first_address_hash,
                ..
            } => Some((
                display_name.clone(),
                network.clone(),
                *last_synced_at,
                first_address_hash.clone(),
            )),
            ProtectionMeta::XpubKey {
                display_name,
                network,
                last_synced_at,
                first_address_hash,
                ..
            } => Some((
                display_name.clone(),
                network.clone(),
                *last_synced_at,
                first_address_hash.clone(),
            )),
            _ => None,
        };
        if let Some((display_name, network, last_synced_at, first_address_hash)) = locked_row {
            let name = display_name
                .as_deref()
                .unwrap_or("Locked Wallet")
                .to_string();
            let network_str = network.as_deref().unwrap_or("bitcoin").to_string();
            results.push((
                path_str,
                WalletInfoRow {
                    name,
                    descriptor: String::new(),
                    network: network_str,
                    created_at: 0,
                    last_synced_at,
                    first_address_hash,
                },
            ));
            continue;
        }

        // DeviceKey wallet — resolve key directly from the already-read meta.
        let key = match resolve_data_key(&meta, device_key_hex) {
            Ok(k) => k,
            Err(_) => continue,
        };

        let conn = match open_encrypted_connection(&path_str, &key) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let row = match read_wallet_info(&conn) {
            Ok(r) => r,
            Err(_) => continue,
        };
        results.push((path_str, row));
    }

    // Newest first
    results.sort_by_key(|r| std::cmp::Reverse(r.1.created_at));
    results
}

/// Migrate a legacy wallet (encrypted with device key directly) to the key-envelope format.
/// Re-keys the database with a fresh data key, then writes a DeviceKey .meta sidecar.
fn migrate_legacy_wallet(wallet_path: &str, device_key_hex: &str) -> Result<()> {
    // Generate a fresh data key and re-key the database (fails fast if key is wrong)
    let data_key = Zeroizing::new(generate_data_key()?);
    rekey_database(wallet_path, device_key_hex, &data_key)?;

    // Write the DeviceKey meta sidecar
    let wrapped_key = wrap_key(&data_key, device_key_hex)?;
    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key,
    };
    write_meta(wallet_path, &meta)?;

    Ok(())
}

/// Read wallet_info from a single wallet file.
/// `password` is required for UserPassword wallets.
pub fn get_wallet_info_from_file(
    wallet_path: &str,
    device_key_hex: &str,
    password: Option<&str>,
) -> Result<WalletInfoRow> {
    let key = resolve_wallet_key(wallet_path, device_key_hex, password, None)?;
    let conn = open_encrypted_connection(wallet_path, &key)?;
    read_wallet_info(&conn)
}

/// Rename a wallet by updating its wallet_info row.
/// `password` is required for UserPassword wallets.
pub fn rename_wallet_in_file(
    wallet_path: &str,
    new_name: &str,
    device_key_hex: &str,
    password: Option<&str>,
) -> Result<()> {
    let key = resolve_wallet_key(wallet_path, device_key_hex, password, None)?;
    let conn = open_encrypted_connection(wallet_path, &key)?;
    conn.execute(
        "UPDATE wallet_info SET name = ?1 WHERE id = 1",
        rusqlite::params![new_name],
    )?;

    // Keep the sidecar display_name in sync so locked UserPassword/XpubKey wallets
    // show the new name in the list before they are unlocked.
    if let Ok(mut meta) = read_meta(wallet_path) {
        let touched = match &mut meta {
            ProtectionMeta::UserPassword { display_name, .. }
            | ProtectionMeta::XpubKey { display_name, .. } => {
                *display_name = Some(new_name.to_string());
                true
            }
            _ => false,
        };
        if touched {
            let _ = write_meta(wallet_path, &meta);
        }
    }

    Ok(())
}

/// Refresh the cached `network` and `last_synced_at` fields in a `UserPassword` or
/// `XpubKey` meta sidecar after the wallet has been successfully opened or synced.
///
/// No-op for DeviceKey wallets. Best-effort: failures are silently ignored.
pub fn refresh_user_password_meta_cache(
    wallet_path: &str,
    network: APINetwork,
    last_synced_at: Option<i64>,
    first_address_hash: Option<&str>,
) {
    let Ok(mut meta) = read_meta(wallet_path) else {
        return;
    };
    let network_str = Some(network.as_str().to_string());
    match &mut meta {
        ProtectionMeta::UserPassword {
            network: cached_network,
            last_synced_at: cached_ts,
            first_address_hash: cached_hash,
            ..
        } => {
            *cached_network = network_str;
            *cached_ts = last_synced_at;
            if cached_hash.is_none() {
                *cached_hash = first_address_hash.map(|s| s.to_string());
            }
        }
        ProtectionMeta::XpubKey {
            network: cached_network,
            last_synced_at: cached_ts,
            first_address_hash: cached_hash,
            ..
        } => {
            *cached_network = network_str;
            *cached_ts = last_synced_at;
            if cached_hash.is_none() {
                *cached_hash = first_address_hash.map(|s| s.to_string());
            }
        }
        _ => return,
    }
    let _ = write_meta(wallet_path, &meta);
}

/// SHA-256 hex digest of the first external receive address derived from `descriptor`.
/// Returns `None` when the descriptor cannot be parsed (e.g. multisig with unknown keys).
pub fn hash_first_address(
    descriptor: &str,
    network: crate::api::model::APINetwork,
) -> Option<String> {
    let addr = crate::api::wallet::discovery::first_address_from_descriptor(
        descriptor.to_string(),
        network,
    )
    .ok()?;
    Some(crate::api::wallet::discovery::sha256_hex(addr))
}

/// Check whether a wallet requires a credential (password or xpub) to open.
/// Returns `false` only for DeviceKey wallets.
pub fn wallet_needs_password(wallet_path: &str) -> bool {
    matches!(
        read_meta(wallet_path),
        Ok(ProtectionMeta::UserPassword { .. }) | Ok(ProtectionMeta::XpubKey { .. })
    )
}

/// Check whether a wallet is XpubKey protected.
pub fn wallet_needs_xpub(wallet_path: &str) -> bool {
    matches!(read_meta(wallet_path), Ok(ProtectionMeta::XpubKey { .. }))
}

/// Read the network hint from the wallet's meta sidecar without opening the DB.
/// Returns the lowercase network string (e.g. "bitcoin", "testnet") or None.
pub fn wallet_network_hint(wallet_path: &str) -> Option<String> {
    match read_meta(wallet_path) {
        Ok(ProtectionMeta::UserPassword { network, .. }) => network,
        Ok(ProtectionMeta::XpubKey { network, .. }) => network,
        _ => None,
    }
}

/// Add a new xpub slot to a XpubKey-protected wallet.
/// `data_key` must be the already-resolved data key (obtained after opening).
/// `derivation` is the path suffix stored as a display hint (may be empty).
/// Returns an error if the MFP is already registered or the wallet is not XpubKey protected.
pub fn add_xpub_slot_to_wallet(
    wallet_path: &str,
    mfp: &str,
    xpub: &str,
    data_key: &str,
    derivation: &str,
) -> Result<()> {
    let mut meta = read_meta(wallet_path)?;
    if let ProtectionMeta::XpubKey { ref mut slots, .. } = meta {
        if slots.iter().any(|s| s.mfp == mfp) {
            return Err(anyhow::anyhow!("MFP {} is already registered", mfp));
        }
        let (m_cost, t_cost) = slots.first().map(|s| (s.m_cost, s.t_cost)).unwrap_or((
            APISecurityLevel::Standard.m_cost(),
            APISecurityLevel::Standard.t_cost(),
        ));
        let slot = wrap_with_xpub(mfp, xpub, data_key, m_cost, t_cost, derivation)?;
        slots.push(slot);
        write_meta(wallet_path, &meta)?;
        Ok(())
    } else {
        Err(anyhow::anyhow!("Wallet is not XpubKey protected"))
    }
}

/// Remove a slot by MFP from a XpubKey-protected wallet.
/// Fails if it would leave the wallet with zero slots.
pub fn remove_xpub_slot_from_wallet(wallet_path: &str, mfp: &str) -> Result<()> {
    let mut meta = read_meta(wallet_path)?;
    if let ProtectionMeta::XpubKey { ref mut slots, .. } = meta {
        if slots.len() <= 1 {
            return Err(anyhow::anyhow!("Cannot remove the last xpub slot"));
        }
        let before = slots.len();
        slots.retain(|s| s.mfp != mfp);
        if slots.len() == before {
            return Err(anyhow::anyhow!("MFP {} not found", mfp));
        }
        write_meta(wallet_path, &meta)?;
        Ok(())
    } else {
        Err(anyhow::anyhow!("Wallet is not XpubKey protected"))
    }
}

/// List the registered MFPs for a XpubKey-protected wallet.
pub fn list_xpub_mfps(wallet_path: &str) -> Result<Vec<String>> {
    let meta = read_meta(wallet_path)?;
    if let ProtectionMeta::XpubKey { slots, .. } = meta {
        Ok(slots.into_iter().map(|s| s.mfp).collect())
    } else {
        Err(anyhow::anyhow!("Wallet is not XpubKey protected"))
    }
}

/// Add a biometric slot to a UserPassword or XpubKey wallet.
/// Resolves the data key using `device_key_hex` + `current_credential`, then wraps
/// it with the provided `biometric_key_hex` (a 32-byte random key from the platform
/// keystore). Returns the new slot ID (UUID v4) to be stored alongside the key.
pub fn add_biometric_slot_to_wallet(
    wallet_path: &str,
    device_key_hex: &str,
    current_credential: Option<&str>,
    biometric_key_hex: &str,
) -> Result<String> {
    let data_key = resolve_wallet_key(wallet_path, device_key_hex, current_credential, None)?;
    let wrapped_key = wrap_key(&data_key, biometric_key_hex)?;
    let id = generate_uuid_v4()?;

    let mut meta = read_meta(wallet_path)?;
    if let Some(slots) = biometric_slots_mut(&mut meta) {
        slots.push(BiometricSlot {
            id: id.clone(),
            wrapped_key,
        });
    } else {
        return Err(anyhow::anyhow!(
            "Biometric slots are only supported for UserPassword and XpubKey wallets"
        ));
    }
    write_meta(wallet_path, &meta)?;
    Ok(id)
}

/// Remove a biometric slot by ID from a UserPassword or XpubKey wallet.
pub fn remove_biometric_slot_from_wallet(wallet_path: &str, biometric_id: &str) -> Result<()> {
    let mut meta = read_meta(wallet_path)?;
    let Some(slots) = biometric_slots_mut(&mut meta) else {
        return Err(anyhow::anyhow!("Wallet does not support biometric slots"));
    };
    let before = slots.len();
    slots.retain(|s| s.id != biometric_id);
    if slots.len() == before {
        return Err(anyhow::anyhow!("Biometric slot {} not found", biometric_id));
    }
    write_meta(wallet_path, &meta)
}

/// List the biometric slot IDs for a UserPassword or XpubKey wallet.
/// Returns an empty Vec for DeviceKey wallets.
pub fn list_biometric_slot_ids(wallet_path: &str) -> Result<Vec<String>> {
    let meta = read_meta(wallet_path)?;
    let ids = biometric_slots(&meta)
        .map(|slots| slots.iter().map(|s| s.id.clone()).collect())
        .unwrap_or_default();
    Ok(ids)
}

/// Returns true if the wallet has at least one biometric slot registered.
pub fn wallet_has_biometric_slots(wallet_path: &str) -> bool {
    read_meta(wallet_path)
        .ok()
        .as_ref()
        .and_then(biometric_slots)
        .is_some_and(|s| !s.is_empty())
}

/// Convert a stored network string from [WalletInfoRow] into a BDK [Network].
///
/// This replaces the repeated pattern `APINetwork::try_from(info.network)?.into()`
/// found in 17+ call sites across `psbt.rs`, `wallet/mod.rs`, `descriptor_*.rs`.
pub fn bdk_network(network_str: &str) -> Result<Network> {
    let api = APINetwork::try_from(network_str)?;
    Ok(match api {
        APINetwork::Bitcoin => Network::Bitcoin,
        APINetwork::Testnet => Network::Testnet,
        APINetwork::Testnet4 => Network::Testnet4,
        APINetwork::Signet => Network::Signet,
        APINetwork::Regtest => Network::Regtest,
    })
}

/// Build a [`WalletProtectionRequest`] from an API protection type and the
/// parameters needed by the target protection scheme.
///
/// Replaces the duplicated `match protection_type { DeviceKey → … | UserPassword → … | XpubKey → … }`
/// pattern found in [`create_wallet`](crate::api::wallet::create_wallet) and
/// [`change_protection`](crate::api::wallet::change_protection).
pub fn build_protection_request(
    ptype: APIProtectionType,
    password: Option<String>,
    m_cost: u32,
    t_cost: u32,
    xpub_descriptor: Option<&str>,
) -> Result<WalletProtectionRequest> {
    Ok(match ptype {
        APIProtectionType::DeviceKey => WalletProtectionRequest::DeviceKey,
        APIProtectionType::UserPassword => {
            let pwd = password
                .ok_or_else(|| anyhow::anyhow!("Password required for UserPassword protection"))?;
            WalletProtectionRequest::UserPassword {
                password: pwd,
                m_cost,
                t_cost,
            }
        }
        APIProtectionType::XpubKey => {
            let descriptor = xpub_descriptor
                .ok_or_else(|| anyhow::anyhow!("Descriptor required for XpubKey protection"))?;
            WalletProtectionRequest::XpubKey {
                xpub_slots: crate::core::descriptor_parser::xpub_slots_from_descriptor(descriptor)?,
                m_cost,
                t_cost,
            }
        }
    })
}

/// Open a wallet for reading by resolving its data key and returning the connection + wallet info.
///
/// Replaces the repeated pattern `resolve_wallet_key → open_encrypted_connection → read_wallet_info`
/// found in [`backup::export_wallet`](crate::api::wallet::backup::export_wallet) and
/// [`nostr_backup::publish_nostr_backup`](crate::api::wallet::nostr_backup::publish_nostr_backup).
///
/// Returns `(data_key_hex, Connection, WalletInfoRow)`. The caller is responsible for dropping the connection.
pub fn open_snapshot(
    wallet_path: &str,
    device_key_hex: &str,
    password: Option<&str>,
) -> Result<(String, rusqlite::Connection, WalletInfoRow)> {
    let wallet_data_key = resolve_wallet_key(wallet_path, device_key_hex, password, None)?;
    let conn = open_encrypted_connection(wallet_path, &wallet_data_key)?;
    let row = read_wallet_info(&conn)?;
    Ok((wallet_data_key, conn, row))
}

#[cfg(test)]
#[path = "wallet_info_tests.rs"]
mod tests;
