use anyhow::Result;
use rand::rngs::OsRng;
use rand::TryRngCore;

use crate::api::model::APINetwork;
use crate::core::key_protection::{
    generate_data_key, generate_salt, resolve_data_key, resolve_xpub_data_key, wrap_key,
    wrap_with_xpub, ProtectionMeta, DEFAULT_M_COST, DEFAULT_P_COST, DEFAULT_T_COST,
};
use crate::core::wallet_meta::{read_meta, write_meta};
use crate::core::wallet_persistence::{
    load_or_create_wallet, open_encrypted_connection, read_wallet_info, rekey_database,
    upsert_wallet_info, WalletInfoRow,
};

pub fn generate_uuid_v4() -> String {
    let mut bytes = [0u8; 16];
    OsRng.try_fill_bytes(&mut bytes).expect("OS RNG failed");
    // Set version 4 and RFC 4122 variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5],
        bytes[6], bytes[7],
        bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
    )
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

    let uuid = generate_uuid_v4();
    let path = Path::new(wallets_dir).join(format!("{}.db", uuid));
    let path_str = path.to_string_lossy().to_string();

    let created_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;

    let network: bdk_wallet::bitcoin::Network =
        crate::api::model::APINetwork::try_from(network_str)?.into();

    // Generate a unique per-wallet data key
    let data_key = generate_data_key();

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
    )?;
    write_meta(&path_str, &meta)?;

    let row = WalletInfoRow {
        name: name.to_string(),
        descriptor: descriptor.to_string(),
        network: network_str.to_string(),
        created_at,
        last_synced_at: None,
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
            let salt = generate_salt();
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
            })
        }
    }
}

/// Open a wallet and return its data key by resolving the protection meta.
/// - For DeviceKey wallets: pass `password = None`.
/// - For UserPassword wallets: pass `password = Some("user-password")`.
/// - For XpubKey wallets: pass `password = Some("xpub or [mfp/path]xpub")`.
pub fn resolve_wallet_key(
    wallet_path: &str,
    device_key_hex: &str,
    password: Option<&str>,
) -> Result<String> {
    let meta = read_meta(wallet_path)?;
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
                ..
            } => Some((display_name.clone(), network.clone(), *last_synced_at)),
            ProtectionMeta::XpubKey {
                display_name,
                network,
                last_synced_at,
                ..
            } => Some((display_name.clone(), network.clone(), *last_synced_at)),
            _ => None,
        };
        if let Some((display_name, network, last_synced_at)) = locked_row {
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
    results.sort_by(|a, b| b.1.created_at.cmp(&a.1.created_at));
    results
}

/// Migrate a legacy wallet (encrypted with device key directly) to the key-envelope format.
/// Re-keys the database with a fresh data key, then writes a DeviceKey .meta sidecar.
fn migrate_legacy_wallet(wallet_path: &str, device_key_hex: &str) -> Result<()> {
    // Generate a fresh data key and re-key the database (fails fast if key is wrong)
    let data_key = generate_data_key();
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
    let key = resolve_wallet_key(wallet_path, device_key_hex, password)?;
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
    let key = resolve_wallet_key(wallet_path, device_key_hex, password)?;
    let conn = open_encrypted_connection(wallet_path, &key)?;
    conn.execute(
        "UPDATE wallet_info SET name = ?1 WHERE id = 1",
        rusqlite::params![new_name],
    )?;
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
) {
    let Ok(mut meta) = read_meta(wallet_path) else {
        return;
    };
    let network_str = Some(network.as_str().to_string());
    match &mut meta {
        ProtectionMeta::UserPassword {
            network: cached_network,
            last_synced_at: cached_ts,
            ..
        } => {
            *cached_network = network_str;
            *cached_ts = last_synced_at;
        }
        ProtectionMeta::XpubKey {
            network: cached_network,
            last_synced_at: cached_ts,
            ..
        } => {
            *cached_network = network_str;
            *cached_ts = last_synced_at;
        }
        _ => return,
    }
    let _ = write_meta(wallet_path, &meta);
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
        let slot = wrap_with_xpub(
            mfp,
            xpub,
            data_key,
            DEFAULT_M_COST,
            DEFAULT_T_COST,
            derivation,
        )?;
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::key_protection::ProtectionMeta;
    use crate::core::wallet_meta::{meta_exists, read_meta};
    use tempfile::tempdir;

    const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    const DEVICE_KEY: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    #[test]
    fn test_uuid_v4_format() {
        let uuid = generate_uuid_v4();
        assert_eq!(uuid.len(), 36);
        let parts: Vec<&str> = uuid.split('-').collect();
        assert_eq!(parts.len(), 5);
        assert_eq!(&uuid[14..15], "4");
        let variant = &uuid[19..20];
        assert!(["8", "9", "a", "b"].contains(&variant));
    }

    #[test]
    fn test_uuid_v4_unique() {
        assert_ne!(generate_uuid_v4(), generate_uuid_v4());
    }

    #[test]
    fn test_create_wallet_db_device_key() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, row) = create_wallet_db(
            &wallets_dir,
            "Test",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;

        assert!(std::path::Path::new(&path).exists());
        assert!(path.ends_with(".db"));
        assert!(meta_exists(&path));
        assert_eq!(row.name, "Test");
        assert_eq!(row.network, "bitcoin");
        assert!(row.last_synced_at.is_none());
        Ok(())
    }

    #[test]
    fn test_create_wallet_db_user_password() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, row) = create_wallet_db(
            &wallets_dir,
            "Secure",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::UserPassword {
                password: "test-password".to_string(),
                m_cost: 1024,
                t_cost: 1,
            },
        )?;

        assert!(std::path::Path::new(&path).exists());
        assert!(meta_exists(&path));
        assert!(wallet_needs_password(&path));
        assert_eq!(row.name, "Secure");
        Ok(())
    }

    #[test]
    fn test_device_key_wallet_opens_without_password() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, _) = create_wallet_db(
            &wallets_dir,
            "NoPass",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;

        let key = resolve_wallet_key(&path, DEVICE_KEY, None)?;
        let conn = open_encrypted_connection(&path, &key)?;
        let row = read_wallet_info(&conn)?;
        assert_eq!(row.name, "NoPass");
        Ok(())
    }

    #[test]
    fn test_user_password_wallet_opens_with_correct_password() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, _) = create_wallet_db(
            &wallets_dir,
            "PassWallet",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::UserPassword {
                password: "my-secret".to_string(),
                m_cost: 1024,
                t_cost: 1,
            },
        )?;

        let key = resolve_wallet_key(&path, DEVICE_KEY, Some("my-secret"))?;
        let conn = open_encrypted_connection(&path, &key)?;
        let row = read_wallet_info(&conn)?;
        assert_eq!(row.name, "PassWallet");
        Ok(())
    }

    #[test]
    fn test_user_password_wallet_fails_with_wrong_password() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, _) = create_wallet_db(
            &wallets_dir,
            "PassWallet",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::UserPassword {
                password: "correct".to_string(),
                m_cost: 1024,
                t_cost: 1,
            },
        )?;

        let result = resolve_wallet_key(&path, DEVICE_KEY, Some("wrong"));
        assert!(result.is_err(), "Should fail with wrong password");
        Ok(())
    }

    #[test]
    fn test_user_password_wallet_fails_without_password() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, _) = create_wallet_db(
            &wallets_dir,
            "PassWallet",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::UserPassword {
                password: "secret".to_string(),
                m_cost: 1024,
                t_cost: 1,
            },
        )?;

        let result = resolve_wallet_key(&path, DEVICE_KEY, None);
        assert!(result.is_err(), "Should require password");
        let msg = result.unwrap_err().to_string();
        assert!(msg.contains("Password required"), "Error: {}", msg);
        Ok(())
    }

    #[test]
    fn test_legacy_migration() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        // Create a legacy wallet (encrypted directly with device key, no .meta)
        let uuid = generate_uuid_v4();
        let path = dir
            .path()
            .join(format!("{}.db", uuid))
            .to_string_lossy()
            .to_string();
        let _ = crate::core::wallet_persistence::load_or_create_wallet(
            &path,
            MAINNET_DESC,
            bdk_wallet::bitcoin::Network::Bitcoin,
            DEVICE_KEY,
        )?;
        let conn = open_encrypted_connection(&path, DEVICE_KEY)?;
        crate::core::wallet_persistence::upsert_wallet_info(
            &conn,
            "Legacy",
            MAINNET_DESC,
            "bitcoin",
            1_000_000,
        )?;
        drop(conn);

        assert!(!meta_exists(&path), "Should start without .meta");

        // list_wallets_in_dir should auto-migrate
        let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].1.name, "Legacy");
        assert!(meta_exists(&path), "Should have .meta after migration");
        Ok(())
    }

    #[test]
    fn test_list_wallets_empty_dir() {
        let dir = tempdir().unwrap();
        let wallets_dir = dir.path().to_string_lossy().to_string();
        let result = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
        assert!(result.is_empty());
    }

    #[test]
    fn test_list_wallets_multiple() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        create_wallet_db(
            &wallets_dir,
            "Wallet A",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;
        std::thread::sleep(std::time::Duration::from_secs(1));
        create_wallet_db(
            &wallets_dir,
            "Wallet B",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;

        let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].1.name, "Wallet B");
        assert_eq!(list[1].1.name, "Wallet A");
        Ok(())
    }

    #[test]
    fn test_list_wallets_includes_password_protected() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        // Create a device-key wallet
        create_wallet_db(
            &wallets_dir,
            "Open Wallet",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;

        // Create a password-protected wallet
        create_wallet_db(
            &wallets_dir,
            "Secret Vault",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::UserPassword {
                password: "s3cr3t".to_string(),
                m_cost: 1024,
                t_cost: 1,
            },
        )?;

        // Both wallets must appear in the list
        let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
        assert_eq!(
            list.len(),
            2,
            "Both wallets (open + locked) should be listed"
        );

        let names: Vec<&str> = list.iter().map(|(_, row)| row.name.as_str()).collect();
        assert!(names.contains(&"Open Wallet"), "Open wallet must appear");
        assert!(
            names.contains(&"Secret Vault"),
            "Password wallet must appear with its name"
        );

        // The password wallet's row has empty descriptor, correct network, and no sync date
        let locked = list.iter().find(|(_, r)| r.name == "Secret Vault").unwrap();
        assert!(
            locked.1.descriptor.is_empty(),
            "Locked wallet descriptor must be empty"
        );
        assert_eq!(
            locked.1.network, "bitcoin",
            "Locked wallet network cached from creation"
        );
        assert!(
            locked.1.last_synced_at.is_none(),
            "Locked wallet has no last_synced_at before any sync"
        );

        Ok(())
    }

    #[test]
    fn test_refresh_user_password_meta_cache() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, _) = create_wallet_db(
            &wallets_dir,
            "Vault",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::UserPassword {
                password: "pw".to_string(),
                m_cost: 1024,
                t_cost: 1,
            },
        )?;

        // Initially last_synced_at should be None in the meta
        let meta = read_meta(&path)?;
        if let ProtectionMeta::UserPassword {
            last_synced_at,
            network,
            ..
        } = &meta
        {
            assert!(last_synced_at.is_none());
            assert_eq!(network.as_deref(), Some("bitcoin"));
        } else {
            panic!("Expected UserPassword meta");
        }

        // Simulate a sync: refresh cache with a timestamp
        refresh_user_password_meta_cache(&path, APINetwork::Testnet, Some(1_700_000_000));

        let updated = read_meta(&path)?;
        if let ProtectionMeta::UserPassword {
            last_synced_at,
            network,
            ..
        } = updated
        {
            assert_eq!(last_synced_at, Some(1_700_000_000));
            assert_eq!(network.as_deref(), Some("testnet"));
        } else {
            panic!("Expected UserPassword meta");
        }

        // list_wallets_in_dir should now show the updated network and last_synced_at
        let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
        assert_eq!(list.len(), 1);
        let row = &list[0].1;
        assert_eq!(row.network, "testnet");
        assert_eq!(row.last_synced_at, Some(1_700_000_000));
        Ok(())
    }

    #[test]
    fn test_list_wallets_skips_non_wallet_files() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        create_wallet_db(
            &wallets_dir,
            "Real",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;

        std::fs::write(dir.path().join("notes.txt"), b"ignore me")?;

        let bad_path = dir.path().join("corrupt.db").to_string_lossy().to_string();
        let conn =
            crate::core::wallet_persistence::open_encrypted_connection(&bad_path, DEVICE_KEY)?;
        let _ = conn;

        let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].1.name, "Real");
        Ok(())
    }

    #[test]
    fn test_get_wallet_info_from_file() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, _) = create_wallet_db(
            &wallets_dir,
            "MyWallet",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;

        let row = get_wallet_info_from_file(&path, DEVICE_KEY, None)?;
        assert_eq!(row.name, "MyWallet");
        Ok(())
    }

    #[test]
    fn test_rename_wallet_in_file() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, _) = create_wallet_db(
            &wallets_dir,
            "Original",
            MAINNET_DESC,
            "bitcoin",
            DEVICE_KEY,
            WalletProtectionRequest::DeviceKey,
        )?;

        rename_wallet_in_file(&path, "Renamed", DEVICE_KEY, None)?;

        let row = get_wallet_info_from_file(&path, DEVICE_KEY, None)?;
        assert_eq!(row.name, "Renamed");
        Ok(())
    }
}
