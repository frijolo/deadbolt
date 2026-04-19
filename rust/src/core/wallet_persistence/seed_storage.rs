use anyhow::Result;
use log::warn;
use rusqlite::Connection;

pub struct SeedEntry {
    pub mfp: String,
    pub seed_type: String, // "mnemonic" | "xprv"
    pub mnemonic: Option<String>,
    pub passphrase: String,
    pub xprv: Option<String>,
    pub created_at: i64,
}

pub fn ensure_seed_entries_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS seed_entries (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            mfp        TEXT NOT NULL UNIQUE,
            seed_type  TEXT NOT NULL,
            mnemonic   TEXT,
            passphrase TEXT NOT NULL DEFAULT '',
            xprv       TEXT,
            created_at INTEGER NOT NULL
        );",
    )?;
    Ok(())
}

pub fn insert_seed_entry(
    conn: &Connection,
    mfp: &str,
    seed_type: &str,
    mnemonic: Option<&str>,
    passphrase: &str,
    xprv: Option<&str>,
) -> Result<i64> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    conn.execute(
        "INSERT OR REPLACE INTO seed_entries (mfp, seed_type, mnemonic, passphrase, xprv, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![mfp, seed_type, mnemonic, passphrase, xprv, now],
    )?;
    Ok(now)
}

pub fn list_seed_entries(conn: &Connection) -> Result<(Vec<SeedEntry>, Vec<String>)> {
    let mut stmt = conn.prepare(
        "SELECT mfp, seed_type, mnemonic, passphrase, xprv, created_at FROM seed_entries ORDER BY created_at ASC",
    )?;
    let mut entries = Vec::new();
    let mut corrupt_rows = Vec::new();
    for result in stmt.query_map([], |row| {
        Ok(SeedEntry {
            mfp: row.get(0)?,
            seed_type: row.get(1)?,
            mnemonic: row.get(2)?,
            passphrase: row.get::<_, Option<String>>(3)?.unwrap_or_default(),
            xprv: row.get(4)?,
            created_at: row.get(5)?,
        })
    })? {
        match result {
            Ok(entry) => entries.push(entry),
            Err(e) => {
                warn!("list_seed_entries: corrupt row ignored: {e}");
                corrupt_rows.push(format!("Corrupt seed entry #{}", corrupt_rows.len() + 1));
            }
        }
    }
    Ok((entries, corrupt_rows))
}

pub fn delete_seed_entry(conn: &Connection, mfp: &str) -> Result<()> {
    let n = conn.execute(
        "DELETE FROM seed_entries WHERE mfp = ?1",
        rusqlite::params![mfp],
    )?;
    if n == 0 {
        return Err(anyhow::anyhow!("No signing key with MFP {} found", mfp));
    }
    Ok(())
}

pub fn has_seed_for_mfp(conn: &Connection, mfp: &str) -> Result<bool> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM seed_entries WHERE mfp = ?1",
        rusqlite::params![mfp],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}
