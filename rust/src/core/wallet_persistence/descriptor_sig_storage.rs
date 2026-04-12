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
#[path = "descriptor_sig_storage_tests.rs"]
mod tests;
