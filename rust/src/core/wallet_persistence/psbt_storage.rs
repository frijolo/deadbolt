use anyhow::Result;
use rusqlite::Connection;

pub struct PsbtRow {
    pub id: i64,
    pub psbt: String, // base64-encoded
    pub txid: String,
    pub label: Option<String>,
    pub created_at: i64,
    pub recipient: String,
    pub amount_sat: u64,
    pub fee_sat: u64,
    pub spend_path_id: u32,
    pub threshold: u32,
    pub mfps: Vec<String>,
    /// JSON-serialized `Vec<APIRecipient>`. None for rows created before multi-recipient support.
    pub recipients_json: Option<String>,
    /// When true, the PSBT is queued to be broadcast automatically as soon as
    /// its timelock matures. Column added by the dev schema layer.
    pub auto_broadcast: bool,
}

impl PsbtRow {
    /// Return a copy of `self` with `psbt` replaced. Used after signing to avoid
    /// manually reconstructing every field.
    pub fn with_psbt(self, psbt: String) -> Self {
        Self { psbt, ..self }
    }
}

pub fn ensure_unsigned_txs_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS unsigned_txs (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            psbt          TEXT NOT NULL,
            txid          TEXT NOT NULL DEFAULT '',
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
    // Migration: add txid column to existing tables that predate this schema.
    let _ = conn.execute(
        "ALTER TABLE unsigned_txs ADD COLUMN txid TEXT NOT NULL DEFAULT ''",
        [],
    );
    // Migration: add recipients_json column (multi-recipient support).
    let _ = conn.execute(
        "ALTER TABLE unsigned_txs ADD COLUMN recipients_json TEXT",
        [],
    );
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub fn insert_psbt(
    conn: &Connection,
    psbt: &str,
    txid: &str,
    label: Option<&str>,
    recipient: &str,
    amount_sat: u64,
    fee_sat: u64,
    spend_path_id: u32,
    threshold: u32,
    mfps: &[String],
    recipients_json: Option<&str>,
) -> Result<i64> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    let mfps_str = mfps.join(",");
    conn.execute(
        "INSERT INTO unsigned_txs
         (psbt, txid, label, created_at, recipient, amount_sat, fee_sat, spend_path_id, threshold, mfps, recipients_json)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
        rusqlite::params![
            psbt,
            txid,
            label,
            now,
            recipient,
            amount_sat as i64,
            fee_sat as i64,
            spend_path_id,
            threshold,
            mfps_str,
            recipients_json
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn update_psbt_label(conn: &Connection, id: i64, label: Option<&str>) -> Result<()> {
    let n = conn.execute(
        "UPDATE unsigned_txs SET label = ?1 WHERE id = ?2",
        rusqlite::params![label, id],
    )?;
    if n == 0 {
        return Err(anyhow::anyhow!("PSBT {} not found", id));
    }
    Ok(())
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

pub fn set_psbt_auto_broadcast(conn: &Connection, id: i64, enabled: bool) -> Result<()> {
    let n = conn.execute(
        "UPDATE unsigned_txs SET auto_broadcast = ?1 WHERE id = ?2",
        rusqlite::params![enabled as i64, id],
    )?;
    if n == 0 {
        return Err(anyhow::anyhow!("PSBT {} not found", id));
    }
    Ok(())
}

pub fn list_auto_broadcast_pending_ids(conn: &Connection) -> Result<Vec<i64>> {
    let mut stmt = conn
        .prepare("SELECT id FROM unsigned_txs WHERE auto_broadcast = 1 ORDER BY created_at ASC")?;
    let rows = stmt
        .query_map([], |row| row.get::<_, i64>(0))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

/// Return the raw PSBT base64 of every pending auto-broadcast row.
///
/// Used by the background-broadcast scheduler to derive each row's
/// `nLockTime` without loading the rest of the row data.
pub fn pending_auto_broadcast_psbts(conn: &Connection) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        "SELECT psbt FROM unsigned_txs WHERE auto_broadcast = 1 ORDER BY created_at ASC",
    )?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

pub fn delete_psbt_row(conn: &Connection, id: i64) -> Result<()> {
    conn.execute(
        "DELETE FROM unsigned_txs WHERE id = ?1",
        rusqlite::params![id],
    )?;
    Ok(())
}

fn parse_psbt_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PsbtRow> {
    let mfps_str: String = row.get(10)?;
    let mfps = if mfps_str.is_empty() {
        vec![]
    } else {
        mfps_str.split(',').map(|s| s.to_string()).collect()
    };
    let recipients_json: Option<String> = row.get(11).ok().flatten();
    let auto_broadcast: i64 = row.get(12).unwrap_or(0);
    Ok(PsbtRow {
        id: row.get(0)?,
        psbt: row.get(1)?,
        txid: row.get(2)?,
        label: row.get(3)?,
        created_at: row.get(4)?,
        recipient: row.get(5)?,
        amount_sat: row.get::<_, i64>(6)? as u64,
        fee_sat: row.get::<_, i64>(7)? as u64,
        spend_path_id: row.get::<_, u32>(8)?,
        threshold: row.get::<_, u32>(9)?,
        mfps,
        recipients_json,
        auto_broadcast: auto_broadcast != 0,
    })
}

pub fn get_psbt_row(conn: &Connection, id: i64) -> Result<PsbtRow> {
    conn.query_row(
        "SELECT id, psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
                spend_path_id, threshold, mfps, recipients_json, auto_broadcast
         FROM unsigned_txs WHERE id = ?1",
        rusqlite::params![id],
        parse_psbt_row,
    )
    .map_err(|e| anyhow::anyhow!("PSBT {} not found: {}", id, e))
}

pub fn get_psbt_row_by_txid(conn: &Connection, txid: &str) -> Result<Option<PsbtRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
                spend_path_id, threshold, mfps, recipients_json, auto_broadcast
         FROM unsigned_txs WHERE txid = ?1 LIMIT 1",
    )?;
    let mut rows = stmt.query_map(rusqlite::params![txid], parse_psbt_row)?;
    rows.next()
        .transpose()
        .map_err(|e| anyhow::anyhow!("{}", e))
}

pub fn list_psbt_rows(conn: &Connection) -> Result<Vec<PsbtRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
                spend_path_id, threshold, mfps, recipients_json, auto_broadcast
         FROM unsigned_txs ORDER BY created_at DESC",
    )?;
    let rows = stmt
        .query_map([], parse_psbt_row)?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}
