use anyhow::Result;
use rand::rngs::OsRng;
use rand::TryRngCore;

use crate::core::wallet_persistence::{
    load_or_create_wallet, open_encrypted_connection, read_wallet_info, upsert_wallet_info,
    WalletInfoRow,
};

fn generate_uuid_v4() -> String {
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

/// Create a new wallet .db file with a UUID filename, initialize BDK tables, and
/// write the wallet_info row. Returns (absolute_path, WalletInfoRow).
pub fn create_wallet_db(
    wallets_dir: &str,
    name: &str,
    descriptor: &str,
    network_str: &str,
    source_project_id: Option<i64>,
    key_hex: &str,
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

    // Initialize BDK tables in the encrypted SQLite file
    let (_wallet, conn) = load_or_create_wallet(&path_str, descriptor, network, key_hex)?;

    // Write metadata row
    upsert_wallet_info(
        &conn,
        name,
        descriptor,
        network_str,
        source_project_id,
        created_at,
    )?;

    let row = WalletInfoRow {
        name: name.to_string(),
        descriptor: descriptor.to_string(),
        network: network_str.to_string(),
        source_project_id,
        created_at,
        last_synced_at: None,
    };

    Ok((path_str, row))
}

/// Scan all *.db files in wallets_dir, read their wallet_info rows, and
/// return them sorted newest-first by created_at. Unreadable files are silently skipped.
pub fn list_wallets_in_dir(wallets_dir: &str, key_hex: &str) -> Vec<(String, WalletInfoRow)> {
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
        let conn = match open_encrypted_connection(&path_str, key_hex) {
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

/// Read wallet_info from a single wallet file.
pub fn get_wallet_info_from_file(wallet_path: &str, key_hex: &str) -> Result<WalletInfoRow> {
    let conn = open_encrypted_connection(wallet_path, key_hex)?;
    read_wallet_info(&conn)
}

/// Rename a wallet by updating its wallet_info row.
pub fn rename_wallet_in_file(wallet_path: &str, new_name: &str, key_hex: &str) -> Result<()> {
    let conn = open_encrypted_connection(wallet_path, key_hex)?;
    conn.execute(
        "UPDATE wallet_info SET name = ?1 WHERE id = 1",
        rusqlite::params![new_name],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    #[test]
    fn test_uuid_v4_format() {
        let uuid = generate_uuid_v4();
        // Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
        assert_eq!(uuid.len(), 36);
        let parts: Vec<&str> = uuid.split('-').collect();
        assert_eq!(parts.len(), 5);
        assert_eq!(parts[0].len(), 8);
        assert_eq!(parts[1].len(), 4);
        assert_eq!(parts[2].len(), 4);
        assert_eq!(parts[3].len(), 4);
        assert_eq!(parts[4].len(), 12);
        // Version nibble must be '4'
        assert_eq!(&uuid[14..15], "4");
        // Variant nibble must be 8, 9, a, or b
        let variant = &uuid[19..20];
        assert!(["8", "9", "a", "b"].contains(&variant));
    }

    #[test]
    fn test_uuid_v4_unique() {
        let a = generate_uuid_v4();
        let b = generate_uuid_v4();
        assert_ne!(a, b);
    }

    #[test]
    fn test_create_wallet_db() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        let (path, row) =
            create_wallet_db(&wallets_dir, "Test", MAINNET_DESC, "bitcoin", None, KEY_HEX)?;

        assert!(std::path::Path::new(&path).exists());
        assert!(path.ends_with(".db"));
        assert_eq!(row.name, "Test");
        assert_eq!(row.network, "bitcoin");
        assert!(row.last_synced_at.is_none());
        Ok(())
    }

    #[test]
    fn test_list_wallets_empty_dir() {
        let dir = tempdir().unwrap();
        let wallets_dir = dir.path().to_string_lossy().to_string();
        let result = list_wallets_in_dir(&wallets_dir, KEY_HEX);
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
            None,
            KEY_HEX,
        )?;
        // Small sleep to ensure different created_at timestamps
        std::thread::sleep(std::time::Duration::from_secs(1));
        create_wallet_db(
            &wallets_dir,
            "Wallet B",
            MAINNET_DESC,
            "bitcoin",
            None,
            KEY_HEX,
        )?;

        let list = list_wallets_in_dir(&wallets_dir, KEY_HEX);
        assert_eq!(list.len(), 2);
        // Newest first
        assert_eq!(list[0].1.name, "Wallet B");
        assert_eq!(list[1].1.name, "Wallet A");
        Ok(())
    }

    #[test]
    fn test_list_wallets_skips_non_wallet_files() -> anyhow::Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        // Create a real wallet
        create_wallet_db(&wallets_dir, "Real", MAINNET_DESC, "bitcoin", None, KEY_HEX)?;

        // Create a non-.db file — should be ignored
        std::fs::write(dir.path().join("notes.txt"), b"ignore me")?;

        // Create a .db file with no wallet_info table — should be skipped silently
        let bad_path = dir.path().join("corrupt.db").to_string_lossy().to_string();
        let conn = crate::core::wallet_persistence::open_encrypted_connection(&bad_path, KEY_HEX)?;
        let _ = conn; // no wallet_info written

        let list = list_wallets_in_dir(&wallets_dir, KEY_HEX);
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
            Some(7),
            KEY_HEX,
        )?;

        let row = get_wallet_info_from_file(&path, KEY_HEX)?;
        assert_eq!(row.name, "MyWallet");
        assert_eq!(row.source_project_id, Some(7));
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
            None,
            KEY_HEX,
        )?;

        rename_wallet_in_file(&path, "Renamed", KEY_HEX)?;

        let row = get_wallet_info_from_file(&path, KEY_HEX)?;
        assert_eq!(row.name, "Renamed");
        Ok(())
    }
}
