use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use bdk_wallet::{PersistedWallet, Wallet};
use rusqlite::Connection;

////////////////////
// WalletInfoRow  //
////////////////////

pub struct WalletInfoRow {
    pub name: String,
    pub descriptor: String,
    pub network: String,
    pub source_project_id: Option<i64>,
    pub created_at: i64,
    pub last_synced_at: Option<i64>,
}

/// Create the wallet_info table if needed and upsert the single row.
pub fn upsert_wallet_info(
    conn: &Connection,
    name: &str,
    descriptor: &str,
    network: &str,
    source_project_id: Option<i64>,
    created_at: i64,
) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS wallet_info (
            id                INTEGER PRIMARY KEY CHECK (id = 1),
            name              TEXT NOT NULL,
            descriptor        TEXT NOT NULL,
            network           TEXT NOT NULL,
            source_project_id INTEGER,
            created_at        INTEGER NOT NULL,
            last_synced_at    INTEGER
        );",
    )?;
    conn.execute(
        "INSERT OR REPLACE INTO wallet_info
         (id, name, descriptor, network, source_project_id, created_at)
         VALUES (1, ?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![name, descriptor, network, source_project_id, created_at],
    )?;
    Ok(())
}

/// Read the single wallet_info row.
pub fn read_wallet_info(conn: &Connection) -> Result<WalletInfoRow> {
    conn.query_row(
        "SELECT name, descriptor, network, source_project_id, created_at, last_synced_at
         FROM wallet_info WHERE id = 1",
        [],
        |row| {
            Ok(WalletInfoRow {
                name: row.get(0)?,
                descriptor: row.get(1)?,
                network: row.get(2)?,
                source_project_id: row.get(3)?,
                created_at: row.get(4)?,
                last_synced_at: row.get(5)?,
            })
        },
    )
    .map_err(|e| anyhow::anyhow!("Failed to read wallet_info: {}", e))
}

//////////////////////
// tx_labels table  //
//////////////////////

/// Create the tx_labels table if it does not already exist.
pub fn ensure_tx_labels_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS tx_labels (
            txid  TEXT PRIMARY KEY,
            label TEXT NOT NULL
        );",
    )?;
    Ok(())
}

/// Upsert a label for a txid. Deletes the row if label is empty.
pub fn set_tx_label(conn: &Connection, txid: &str, label: &str) -> Result<()> {
    if label.is_empty() {
        conn.execute("DELETE FROM tx_labels WHERE txid = ?1", rusqlite::params![txid])?;
    } else {
        conn.execute(
            "INSERT OR REPLACE INTO tx_labels (txid, label) VALUES (?1, ?2)",
            rusqlite::params![txid, label],
        )?;
    }
    Ok(())
}

/// Return all labels as a HashMap<txid, label>.
pub fn get_all_tx_labels(conn: &Connection) -> Result<std::collections::HashMap<String, String>> {
    let mut stmt = conn.prepare("SELECT txid, label FROM tx_labels")?;
    let map = stmt
        .query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(map)
}

////////////////////////////
// address_labels table   //
////////////////////////////

/// Create the address_labels table if it does not already exist.
pub fn ensure_address_labels_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS address_labels (
            address TEXT PRIMARY KEY,
            label   TEXT NOT NULL
        );",
    )?;
    Ok(())
}

/// Upsert a label for an address. Deletes the row if label is empty.
pub fn set_address_label(conn: &Connection, address: &str, label: &str) -> Result<()> {
    if label.is_empty() {
        conn.execute(
            "DELETE FROM address_labels WHERE address = ?1",
            rusqlite::params![address],
        )?;
    } else {
        conn.execute(
            "INSERT OR REPLACE INTO address_labels (address, label) VALUES (?1, ?2)",
            rusqlite::params![address, label],
        )?;
    }
    Ok(())
}

/// Return all address labels as a HashMap<address, label>.
pub fn get_all_address_labels(
    conn: &Connection,
) -> Result<std::collections::HashMap<String, String>> {
    let mut stmt = conn.prepare("SELECT address, label FROM address_labels")?;
    let map = stmt
        .query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(map)
}

//////////////////////////////
// key_labels table          //
//////////////////////////////

/// Create the key_labels table if it does not already exist.
pub fn ensure_key_labels_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS key_labels (
            mfp   TEXT PRIMARY KEY,
            label TEXT NOT NULL
        );",
    )?;
    Ok(())
}

/// Upsert a label for a master fingerprint. Deletes the row if label is empty.
pub fn set_key_label(conn: &Connection, mfp: &str, label: &str) -> Result<()> {
    if label.is_empty() {
        conn.execute("DELETE FROM key_labels WHERE mfp = ?1", rusqlite::params![mfp])?;
    } else {
        conn.execute(
            "INSERT OR REPLACE INTO key_labels (mfp, label) VALUES (?1, ?2)",
            rusqlite::params![mfp, label],
        )?;
    }
    Ok(())
}

/// Return all key labels as a HashMap<mfp, label>.
pub fn get_all_key_labels(conn: &Connection) -> Result<std::collections::HashMap<String, String>> {
    let mut stmt = conn.prepare("SELECT mfp, label FROM key_labels")?;
    let map = stmt
        .query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(map)
}

//////////////////////////////
// path_labels table         //
//////////////////////////////

/// Create the path_labels table if it does not already exist.
pub fn ensure_path_labels_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS path_labels (
            rust_id INTEGER PRIMARY KEY,
            label   TEXT NOT NULL
        );",
    )?;
    Ok(())
}

/// Upsert a label for a spend path (keyed by rust_id). Deletes the row if label is empty.
pub fn set_path_label(conn: &Connection, rust_id: u32, label: &str) -> Result<()> {
    if label.is_empty() {
        conn.execute(
            "DELETE FROM path_labels WHERE rust_id = ?1",
            rusqlite::params![rust_id],
        )?;
    } else {
        conn.execute(
            "INSERT OR REPLACE INTO path_labels (rust_id, label) VALUES (?1, ?2)",
            rusqlite::params![rust_id, label],
        )?;
    }
    Ok(())
}

/// Return all path labels as a HashMap<rust_id, label>.
pub fn get_all_path_labels(conn: &Connection) -> Result<std::collections::HashMap<u32, String>> {
    let mut stmt = conn.prepare("SELECT rust_id, label FROM path_labels")?;
    let map = stmt
        .query_map([], |row| Ok((row.get::<_, u32>(0)?, row.get::<_, String>(1)?)))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(map)
}

//////////////////////////////
// unsigned_txs table       //
//////////////////////////////

pub struct PsbtRow {
    pub id: i64,
    pub psbt: String, // base64-encoded
    pub label: Option<String>,
    pub created_at: i64,
    pub recipient: String,
    pub amount_sat: u64,
    pub fee_sat: u64,
    pub spend_path_id: u32,
    pub threshold: u32,
    pub mfps: Vec<String>,
}

pub fn ensure_unsigned_txs_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS unsigned_txs (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            psbt          TEXT NOT NULL,
            label         TEXT,
            created_at    INTEGER NOT NULL,
            recipient     TEXT NOT NULL,
            amount_sat    INTEGER NOT NULL,
            fee_sat       INTEGER NOT NULL,
            spend_path_id INTEGER NOT NULL,
            threshold     INTEGER NOT NULL,
            mfps          TEXT NOT NULL
        );",
    )?;
    Ok(())
}

pub fn insert_psbt(
    conn: &Connection,
    psbt: &str,
    label: Option<&str>,
    recipient: &str,
    amount_sat: u64,
    fee_sat: u64,
    spend_path_id: u32,
    threshold: u32,
    mfps: &[String],
) -> Result<i64> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    let mfps_str = mfps.join(",");
    conn.execute(
        "INSERT INTO unsigned_txs
         (psbt, label, created_at, recipient, amount_sat, fee_sat, spend_path_id, threshold, mfps)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        rusqlite::params![
            psbt,
            label,
            now,
            recipient,
            amount_sat as i64,
            fee_sat as i64,
            spend_path_id,
            threshold,
            mfps_str
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn update_psbt_data(conn: &Connection, id: i64, psbt_base64: &str) -> Result<()> {
    let n = conn.execute(
        "UPDATE unsigned_txs SET psbt = ?1 WHERE id = ?2",
        rusqlite::params![psbt_base64, id],
    )?;
    if n == 0 {
        return Err(anyhow::anyhow!("PSBT {} not found", id));
    }
    Ok(())
}

pub fn delete_psbt_row(conn: &Connection, id: i64) -> Result<()> {
    conn.execute("DELETE FROM unsigned_txs WHERE id = ?1", rusqlite::params![id])?;
    Ok(())
}

fn parse_psbt_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PsbtRow> {
    let mfps_str: String = row.get(9)?;
    let mfps = if mfps_str.is_empty() {
        vec![]
    } else {
        mfps_str.split(',').map(|s| s.to_string()).collect()
    };
    Ok(PsbtRow {
        id: row.get(0)?,
        psbt: row.get(1)?,
        label: row.get(2)?,
        created_at: row.get(3)?,
        recipient: row.get(4)?,
        amount_sat: row.get::<_, i64>(5)? as u64,
        fee_sat: row.get::<_, i64>(6)? as u64,
        spend_path_id: row.get::<_, u32>(7)?,
        threshold: row.get::<_, u32>(8)?,
        mfps,
    })
}

pub fn get_psbt_row(conn: &Connection, id: i64) -> Result<PsbtRow> {
    conn.query_row(
        "SELECT id, psbt, label, created_at, recipient, amount_sat, fee_sat,
                spend_path_id, threshold, mfps
         FROM unsigned_txs WHERE id = ?1",
        rusqlite::params![id],
        |row| parse_psbt_row(row),
    )
    .map_err(|e| anyhow::anyhow!("PSBT {} not found: {}", id, e))
}

pub fn list_psbt_rows(conn: &Connection) -> Result<Vec<PsbtRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, psbt, label, created_at, recipient, amount_sat, fee_sat,
                spend_path_id, threshold, mfps
         FROM unsigned_txs ORDER BY created_at DESC",
    )?;
    let rows = stmt
        .query_map([], |row| parse_psbt_row(row))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

/// Update last_synced_at to the current Unix timestamp.
pub fn touch_last_synced(conn: &Connection) -> Result<()> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    conn.execute(
        "UPDATE wallet_info SET last_synced_at = ?1 WHERE id = 1",
        rusqlite::params![now],
    )?;
    Ok(())
}

/// Open an encrypted SQLite connection using SQLCipher.
pub fn open_encrypted_connection(path: &str, key_hex: &str) -> Result<Connection> {
    let conn = Connection::open(path)?;
    conn.execute_batch(&format!("PRAGMA key = \"x'{}'\"", key_hex))?;
    // Enable WAL mode for efficient concurrent reads
    conn.execute_batch("PRAGMA journal_mode = WAL;")?;
    Ok(conn)
}

/// Load an existing BDK wallet from the encrypted database, or create it if it doesn't exist.
pub fn load_or_create_wallet(
    path: &str,
    descriptor: &str,
    network: Network,
    key_hex: &str,
) -> Result<(PersistedWallet<Connection>, Connection)> {
    let mut conn = open_encrypted_connection(path, key_hex)?;

    // Do not pass the descriptor to load(): create_from_two_path_descriptor
    // splits the two-path descriptor into external (<0>/*) and internal (<1>/*)
    // before persisting. Passing the original two-path descriptor as the
    // external key would never match what BDK stored, so load_wallet() would
    // always return None and then create_wallet() would panic on existing tables.
    let wallet = match Wallet::load().load_wallet(&mut conn)? {
        Some(w) => w,
        None => Wallet::create_from_two_path_descriptor(descriptor.to_owned())
            .network(network)
            .create_wallet(&mut conn)?,
    };

    ensure_tx_labels_table(&conn)?;
    ensure_address_labels_table(&conn)?;
    ensure_key_labels_table(&conn)?;
    ensure_path_labels_table(&conn)?;

    Ok((wallet, conn))
}

#[cfg(test)]
mod tests {
    use super::*;
    use bdk_wallet::bitcoin::Network;
    use tempfile::tempdir;

    #[test]
    fn test_upsert_and_read_wallet_info() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("test.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;

        upsert_wallet_info(
            &conn,
            "My Wallet",
            "desc",
            "bitcoin",
            Some(42),
            1_700_000_000,
        )?;
        let row = read_wallet_info(&conn)?;

        assert_eq!(row.name, "My Wallet");
        assert_eq!(row.descriptor, "desc");
        assert_eq!(row.network, "bitcoin");
        assert_eq!(row.source_project_id, Some(42));
        assert_eq!(row.created_at, 1_700_000_000);
        assert!(row.last_synced_at.is_none());
        Ok(())
    }

    #[test]
    fn test_upsert_overwrites_previous_row() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("test.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;

        upsert_wallet_info(&conn, "Old Name", "desc", "testnet", None, 1_000)?;
        upsert_wallet_info(&conn, "New Name", "desc", "testnet", None, 1_000)?;
        let row = read_wallet_info(&conn)?;

        assert_eq!(row.name, "New Name");
        Ok(())
    }

    #[test]
    fn test_touch_last_synced() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("test.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;

        upsert_wallet_info(&conn, "Wallet", "desc", "bitcoin", None, 1_000)?;
        assert!(read_wallet_info(&conn)?.last_synced_at.is_none());

        touch_last_synced(&conn)?;
        let ts = read_wallet_info(&conn)?.last_synced_at;
        assert!(ts.is_some());
        assert!(ts.unwrap() > 0);
        Ok(())
    }

    #[test]
    fn test_read_wallet_info_missing_table() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("test.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;

        let result = read_wallet_info(&conn);
        assert!(result.is_err());
        Ok(())
    }

    // 2-of-2 mainnet WSH descriptor with two-path notation (<0;1>/*)
    const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    // 32-byte test encryption key (not secret — test only)
    const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    #[test]
    fn test_open_encrypted_connection_creates_db() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("test.db").to_string_lossy().to_string();

        let conn = open_encrypted_connection(&path, KEY_HEX)?;
        // Verify the connection works with a simple query
        let result: i64 = conn.query_row("SELECT 1", [], |row| row.get(0))?;
        assert_eq!(result, 1);
        Ok(())
    }

    #[test]
    fn test_load_or_create_creates_fresh_wallet() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("wallet.db").to_string_lossy().to_string();

        let (_wallet, _conn) =
            load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;
        // File should now exist
        assert!(std::path::Path::new(&path).exists());
        Ok(())
    }

    #[test]
    fn test_load_or_create_reloads_existing() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("wallet.db").to_string_lossy().to_string();

        // First call: creates the wallet
        let _ = load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;
        // Second call: must reload without panic
        let (_wallet, _conn) =
            load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;
        Ok(())
    }


    #[test]
    fn test_wrong_key_cannot_open_existing_db() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("wallet.db").to_string_lossy().to_string();

        // Create with KEY_HEX
        let _ = load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;

        // Open with a different key — SQLCipher should reject this
        let wrong_key = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
        let result = load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, wrong_key);
        assert!(result.is_err(), "Opening with wrong key should fail");
        Ok(())
    }
}
