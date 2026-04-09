use anyhow::Result;
use rusqlite::Connection;

pub struct DbDescriptorSig {
    pub mfp: String,
    /// Full descriptor key entry, e.g. `[aabbccdd/48'/0'/0'/2']xpub…`
    pub xpub_entry: String,
    /// "bip322" | "message"
    pub sig_method: String,
    /// DER hex for bip322 variants; base64 for qr_message variant.
    pub sig_hex: String,
    pub signed_at: i64,
}

pub fn ensure_descriptor_sigs_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS descriptor_sigs (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            mfp         TEXT NOT NULL UNIQUE,
            xpub_entry  TEXT NOT NULL,
            sig_method  TEXT NOT NULL,
            sig_hex     TEXT NOT NULL,
            signed_at   INTEGER NOT NULL
        );",
    )?;
    Ok(())
}

pub fn insert_descriptor_sig(
    conn: &Connection,
    mfp: &str,
    xpub_entry: &str,
    sig_method: &str,
    sig_hex: &str,
) -> Result<i64> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    conn.execute(
        "INSERT OR REPLACE INTO descriptor_sigs (mfp, xpub_entry, sig_method, sig_hex, signed_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![mfp, xpub_entry, sig_method, sig_hex, now],
    )?;
    Ok(now)
}

pub fn list_descriptor_sigs(conn: &Connection) -> Result<Vec<DbDescriptorSig>> {
    // Table may not exist in older wallet DBs opened before this feature was added.
    let exists: bool = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='descriptor_sigs'",
            [],
            |row| row.get::<_, i64>(0),
        )
        .unwrap_or(0)
        > 0;
    if !exists {
        return Ok(vec![]);
    }

    let mut stmt = conn.prepare(
        "SELECT mfp, xpub_entry, sig_method, sig_hex, signed_at
         FROM descriptor_sigs ORDER BY signed_at ASC",
    )?;
    let entries = stmt
        .query_map([], |row| {
            Ok(DbDescriptorSig {
                mfp: row.get(0)?,
                xpub_entry: row.get(1)?,
                sig_method: row.get(2)?,
                sig_hex: row.get(3)?,
                signed_at: row.get(4)?,
            })
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(entries)
}

pub fn delete_descriptor_sig(conn: &Connection, mfp: &str) -> Result<()> {
    let n = conn.execute(
        "DELETE FROM descriptor_sigs WHERE mfp = ?1",
        rusqlite::params![mfp],
    )?;
    if n == 0 {
        return Err(anyhow::anyhow!("No descriptor signature for MFP {}", mfp));
    }
    Ok(())
}

/// Serialize stored sigs as a JSON array suitable for inclusion in backup payloads.
/// Returns `None` when no sigs are stored (omit the field entirely).
pub fn get_descriptor_sigs_as_json(conn: &Connection) -> Result<Option<serde_json::Value>> {
    let sigs = list_descriptor_sigs(conn)?;
    if sigs.is_empty() {
        return Ok(None);
    }
    let arr: Vec<serde_json::Value> = sigs
        .into_iter()
        .map(|s| {
            serde_json::json!({
                "mfp": s.mfp,
                "xpub_entry": s.xpub_entry,
                "sig_method": s.sig_method,
                "sig_hex": s.sig_hex,
            })
        })
        .collect();
    Ok(Some(serde_json::Value::Array(arr)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::wallet_persistence::open_encrypted_connection;
    use tempfile::tempdir;

    const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
    const MFP: &str = "c449c5c5";
    const XPUB_ENTRY: &str = "[c449c5c5/48'/0'/0'/2']xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn";

    fn open_test_db() -> (Connection, tempfile::TempDir) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX).unwrap();
        ensure_descriptor_sigs_table(&conn).unwrap();
        (conn, dir)
    }

    #[test]
    fn test_insert_and_list() -> Result<()> {
        let (conn, _dir) = open_test_db();
        insert_descriptor_sig(&conn, MFP, XPUB_ENTRY, "bip322", "deadbeef")?;
        let sigs = list_descriptor_sigs(&conn)?;
        assert_eq!(sigs.len(), 1);
        assert_eq!(sigs[0].mfp, MFP);
        assert_eq!(sigs[0].sig_method, "bip322");
        assert_eq!(sigs[0].sig_hex, "deadbeef");
        Ok(())
    }

    #[test]
    fn test_insert_replaces_by_mfp() -> Result<()> {
        let (conn, _dir) = open_test_db();
        insert_descriptor_sig(&conn, MFP, XPUB_ENTRY, "bip322", "aaa")?;
        insert_descriptor_sig(&conn, MFP, XPUB_ENTRY, "message", "bbb")?;
        let sigs = list_descriptor_sigs(&conn)?;
        assert_eq!(sigs.len(), 1);
        assert_eq!(sigs[0].sig_method, "message");
        assert_eq!(sigs[0].sig_hex, "bbb");
        Ok(())
    }

    #[test]
    fn test_delete() -> Result<()> {
        let (conn, _dir) = open_test_db();
        insert_descriptor_sig(&conn, MFP, XPUB_ENTRY, "hotkey", "aaa")?;
        delete_descriptor_sig(&conn, MFP)?;
        let sigs = list_descriptor_sigs(&conn)?;
        assert!(sigs.is_empty());
        Ok(())
    }

    #[test]
    fn test_delete_nonexistent_returns_error() {
        let (conn, _dir) = open_test_db();
        assert!(delete_descriptor_sig(&conn, "00000000").is_err());
    }

    #[test]
    fn test_get_as_json_empty() -> Result<()> {
        let (conn, _dir) = open_test_db();
        assert!(get_descriptor_sigs_as_json(&conn)?.is_none());
        Ok(())
    }

    #[test]
    fn test_get_as_json_populated() -> Result<()> {
        let (conn, _dir) = open_test_db();
        insert_descriptor_sig(&conn, MFP, XPUB_ENTRY, "bip322", "cafebabe")?;
        let json = get_descriptor_sigs_as_json(&conn)?.unwrap();
        let arr = json.as_array().unwrap();
        assert_eq!(arr.len(), 1);
        assert_eq!(arr[0]["mfp"], MFP);
        assert_eq!(arr[0]["sig_method"], "bip322");
        Ok(())
    }

    #[test]
    fn test_list_on_table_missing_returns_empty() -> Result<()> {
        // Connection without calling ensure_descriptor_sigs_table — simulates old DB.
        let dir = tempdir()?;
        let path = dir.path().join("old.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;
        let sigs = list_descriptor_sigs(&conn)?;
        assert!(sigs.is_empty());
        Ok(())
    }
}
