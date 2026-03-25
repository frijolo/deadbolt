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
    pub created_at: i64,
    pub last_synced_at: Option<i64>,
}

/// Create the wallet_info table if needed and upsert the single row.
pub fn upsert_wallet_info(
    conn: &Connection,
    name: &str,
    descriptor: &str,
    network: &str,
    created_at: i64,
) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS wallet_info (
            id             INTEGER PRIMARY KEY CHECK (id = 1),
            name           TEXT NOT NULL,
            descriptor     TEXT NOT NULL,
            network        TEXT NOT NULL,
            created_at     INTEGER NOT NULL,
            last_synced_at INTEGER
        );",
    )?;
    conn.execute(
        "INSERT OR REPLACE INTO wallet_info
         (id, name, descriptor, network, created_at)
         VALUES (1, ?1, ?2, ?3, ?4)",
        rusqlite::params![name, descriptor, network, created_at],
    )?;
    Ok(())
}

/// Read the single wallet_info row.
pub fn read_wallet_info(conn: &Connection) -> Result<WalletInfoRow> {
    conn.query_row(
        "SELECT name, descriptor, network, created_at, last_synced_at
         FROM wallet_info WHERE id = 1",
        [],
        |row| {
            Ok(WalletInfoRow {
                name: row.get(0)?,
                descriptor: row.get(1)?,
                network: row.get(2)?,
                created_at: row.get(3)?,
                last_synced_at: row.get(4)?,
            })
        },
    )
    .map_err(|e| anyhow::anyhow!("Failed to read wallet_info: {}", e))
}

/// Add a column to `table` if it doesn't already exist.
/// `col_def` is the full SQL type + constraint, e.g. `"INTEGER NOT NULL DEFAULT 0"`.
/// This is a migration guard for DBs created before the column was introduced.
fn ensure_column(conn: &Connection, table: &str, column: &str, col_def: &str) -> Result<()> {
    let exists: i32 = conn
        .query_row(
            &format!("SELECT COUNT(*) FROM pragma_table_info('{table}') WHERE name = '{column}'"),
            [],
            |row| row.get(0),
        )
        .unwrap_or(0);
    if exists == 0 {
        conn.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {col_def}"),
            [],
        )?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Generic label-table helpers.
//
// `set_entity_label`   — full schema (is_auto + source_entity): tx/address/coin labels
// `set_simple_label`   — key-only schema (no metadata columns):  key/path labels
// ---------------------------------------------------------------------------

/// Upsert/delete a label in a simple two-column table `(key_col, label)`.
/// Used by key_labels (TEXT key) and path_labels (INTEGER key), which have no
/// `is_auto`/`source_entity` columns unlike the other label tables.
fn set_simple_label(
    conn: &Connection,
    table: &str,
    key_col: &str,
    key: &dyn rusqlite::types::ToSql,
    label: &str,
) -> Result<()> {
    if label.is_empty() {
        conn.execute(&format!("DELETE FROM {table} WHERE {key_col} = ?1"), [key])?;
    } else {
        conn.execute(
            &format!("INSERT OR REPLACE INTO {table} ({key_col}, label) VALUES (?1, ?2)"),
            [key, &label as &dyn rusqlite::types::ToSql],
        )?;
    }
    Ok(())
}

fn set_entity_label(
    conn: &Connection,
    table: &str,
    key_col: &str,
    key: &str,
    label: &str,
    is_auto: bool,
    source: Option<&str>,
) -> Result<()> {
    if label.is_empty() {
        conn.execute(
            &format!("DELETE FROM {table} WHERE {key_col} = ?1"),
            rusqlite::params![key],
        )?;
    } else {
        conn.execute(
            &format!(
                "INSERT OR REPLACE INTO {table} ({key_col}, label, is_auto, source_entity) \
                 VALUES (?1, ?2, ?3, ?4)"
            ),
            rusqlite::params![key, label, is_auto as i32, source],
        )?;
    }
    Ok(())
}

fn get_all_entity_labels(
    conn: &Connection,
    table: &str,
    key_col: &str,
) -> Result<std::collections::HashMap<String, String>> {
    let mut stmt = conn.prepare(&format!("SELECT {key_col}, label FROM {table}"))?;
    let map = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(map)
}

fn get_all_entity_labels_with_flag(
    conn: &Connection,
    table: &str,
    key_col: &str,
) -> Result<std::collections::HashMap<String, (String, bool)>> {
    let mut stmt = conn.prepare(&format!("SELECT {key_col}, label, is_auto FROM {table}"))?;
    let map = stmt
        .query_map([], |row| {
            let is_auto: i32 = row.get(2)?;
            Ok((
                row.get::<_, String>(0)?,
                (row.get::<_, String>(1)?, is_auto != 0),
            ))
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(map)
}

fn get_entity_label(
    conn: &Connection,
    table: &str,
    key_col: &str,
    key: &str,
) -> Result<Option<String>> {
    let mut stmt = conn.prepare(&format!("SELECT label FROM {table} WHERE {key_col} = ?1"))?;
    let result = stmt.query_row([key], |row| row.get::<_, String>(0)).ok();
    Ok(result)
}

fn get_entity_label_with_flag(
    conn: &Connection,
    table: &str,
    key_col: &str,
    key: &str,
) -> Result<Option<(String, bool)>> {
    let mut stmt = conn.prepare(&format!(
        "SELECT label, is_auto FROM {table} WHERE {key_col} = ?1"
    ))?;
    let result = stmt
        .query_row([key], |row| {
            let is_auto: i32 = row.get(1)?;
            Ok((row.get::<_, String>(0)?, is_auto != 0))
        })
        .ok();
    Ok(result)
}

fn entity_has_explicit_label(
    conn: &Connection,
    table: &str,
    key_col: &str,
    key: &str,
) -> Result<bool> {
    let mut stmt = conn.prepare(&format!(
        "SELECT 1 FROM {table} WHERE {key_col} = ?1 AND is_auto = 0"
    ))?;
    let exists = stmt.query_row([key], |_row| Ok(true)).ok();
    Ok(exists.unwrap_or(false))
}

//////////////////////
// tx_labels table  //
//////////////////////

/// Create the tx_labels table if it does not already exist.
pub fn ensure_tx_labels_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS tx_labels (
            txid          TEXT PRIMARY KEY,
            label         TEXT NOT NULL,
            is_auto       INTEGER NOT NULL DEFAULT 0,
            source_entity TEXT
        );",
    )?;
    ensure_column(conn, "tx_labels", "is_auto", "INTEGER NOT NULL DEFAULT 0")?;
    ensure_column(conn, "tx_labels", "source_entity", "TEXT")?;
    Ok(())
}

/// Upsert a label for a txid. Deletes the row if label is empty.
/// `source` identifies the entity that propagated this auto-label (e.g. `"addr:bc1q…"`).
/// Pass `None` for explicit (user-set) labels.
pub fn set_tx_label(
    conn: &Connection,
    txid: &str,
    label: &str,
    is_auto: bool,
    source: Option<&str>,
) -> Result<()> {
    set_entity_label(conn, "tx_labels", "txid", txid, label, is_auto, source)
}

/// Return all labels as a HashMap<txid, label>.
pub fn get_all_tx_labels(conn: &Connection) -> Result<std::collections::HashMap<String, String>> {
    get_all_entity_labels(conn, "tx_labels", "txid")
}

/// Return all labels with is_auto flag as a HashMap<txid, (label, is_auto)>.
pub fn get_all_tx_labels_with_flag(
    conn: &Connection,
) -> Result<std::collections::HashMap<String, (String, bool)>> {
    get_all_entity_labels_with_flag(conn, "tx_labels", "txid")
}

/// Get a specific tx label.
pub fn get_tx_label(conn: &Connection, txid: &str) -> Result<Option<String>> {
    get_entity_label(conn, "tx_labels", "txid", txid)
}

/// Get a specific tx label with is_auto flag.
pub fn get_tx_label_with_flag(conn: &Connection, txid: &str) -> Result<Option<(String, bool)>> {
    get_entity_label_with_flag(conn, "tx_labels", "txid", txid)
}

/// Check if a tx has an explicit (non-auto) label.
pub fn tx_has_explicit_label(conn: &Connection, txid: &str) -> Result<bool> {
    entity_has_explicit_label(conn, "tx_labels", "txid", txid)
}

////////////////////////////
// address_labels table   //
////////////////////////////

/// Create the address_labels table if it does not already exist.
pub fn ensure_address_labels_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS address_labels (
            address       TEXT PRIMARY KEY,
            label         TEXT NOT NULL,
            is_auto       INTEGER NOT NULL DEFAULT 0,
            source_entity TEXT
        );",
    )?;
    ensure_column(
        conn,
        "address_labels",
        "is_auto",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    ensure_column(conn, "address_labels", "source_entity", "TEXT")?;
    Ok(())
}

/// Upsert a label for an address. Deletes the row if label is empty.
/// `source` identifies the entity that propagated this auto-label.
/// Pass `None` for explicit (user-set) labels.
pub fn set_address_label(
    conn: &Connection,
    address: &str,
    label: &str,
    is_auto: bool,
    source: Option<&str>,
) -> Result<()> {
    set_entity_label(
        conn,
        "address_labels",
        "address",
        address,
        label,
        is_auto,
        source,
    )
}

/// Return all address labels as a HashMap<address, label>.
pub fn get_all_address_labels(
    conn: &Connection,
) -> Result<std::collections::HashMap<String, String>> {
    get_all_entity_labels(conn, "address_labels", "address")
}

/// Return all address labels with is_auto flag as a HashMap<address, (label, is_auto)>.
pub fn get_all_address_labels_with_flag(
    conn: &Connection,
) -> Result<std::collections::HashMap<String, (String, bool)>> {
    get_all_entity_labels_with_flag(conn, "address_labels", "address")
}

/// Get a specific address label.
pub fn get_address_label(conn: &Connection, address: &str) -> Result<Option<String>> {
    get_entity_label(conn, "address_labels", "address", address)
}

/// Get a specific address label with is_auto flag.
pub fn get_address_label_with_flag(
    conn: &Connection,
    address: &str,
) -> Result<Option<(String, bool)>> {
    get_entity_label_with_flag(conn, "address_labels", "address", address)
}

/// Check if an address has an explicit (non-auto) label.
pub fn address_has_explicit_label(conn: &Connection, address: &str) -> Result<bool> {
    entity_has_explicit_label(conn, "address_labels", "address", address)
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
    set_simple_label(conn, "key_labels", "mfp", &mfp, label)
}

/// Return all key labels as a HashMap<mfp, label>.
pub fn get_all_key_labels(conn: &Connection) -> Result<std::collections::HashMap<String, String>> {
    let mut stmt = conn.prepare("SELECT mfp, label FROM key_labels")?;
    let map = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
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
    set_simple_label(conn, "path_labels", "rust_id", &rust_id, label)
}

/// Return all path labels as a HashMap<rust_id, label>.
pub fn get_all_path_labels(conn: &Connection) -> Result<std::collections::HashMap<u32, String>> {
    let mut stmt = conn.prepare("SELECT rust_id, label FROM path_labels")?;
    let map = stmt
        .query_map([], |row| {
            Ok((row.get::<_, u32>(0)?, row.get::<_, String>(1)?))
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(map)
}

//////////////////////////////
// coin_labels table         //
//////////////////////////////

/// Create the coin_labels table if it does not already exist.
pub fn ensure_coin_labels_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS coin_labels (
            outpoint      TEXT PRIMARY KEY,
            label         TEXT NOT NULL,
            is_auto       INTEGER NOT NULL DEFAULT 0,
            source_entity TEXT
        );",
    )?;
    ensure_column(conn, "coin_labels", "is_auto", "INTEGER NOT NULL DEFAULT 0")?;
    ensure_column(conn, "coin_labels", "source_entity", "TEXT")?;
    Ok(())
}

/// Upsert a label for a UTXO outpoint ("txid:vout"). Deletes the row if label is empty.
/// `source` identifies the entity that propagated this auto-label.
/// Pass `None` for explicit (user-set) labels.
pub fn set_coin_label(
    conn: &Connection,
    outpoint: &str,
    label: &str,
    is_auto: bool,
    source: Option<&str>,
) -> Result<()> {
    set_entity_label(
        conn,
        "coin_labels",
        "outpoint",
        outpoint,
        label,
        is_auto,
        source,
    )
}

/// Return all coin labels as a HashMap<outpoint, label>.
pub fn get_all_coin_labels(conn: &Connection) -> Result<std::collections::HashMap<String, String>> {
    get_all_entity_labels(conn, "coin_labels", "outpoint")
}

/// Return all coin labels with is_auto flag as a HashMap<outpoint, (label, is_auto)>.
pub fn get_all_coin_labels_with_flag(
    conn: &Connection,
) -> Result<std::collections::HashMap<String, (String, bool)>> {
    get_all_entity_labels_with_flag(conn, "coin_labels", "outpoint")
}

/// Get a specific coin label.
pub fn get_coin_label(conn: &Connection, outpoint: &str) -> Result<Option<String>> {
    get_entity_label(conn, "coin_labels", "outpoint", outpoint)
}

/// Get a specific coin label with is_auto flag.
pub fn get_coin_label_with_flag(
    conn: &Connection,
    outpoint: &str,
) -> Result<Option<(String, bool)>> {
    get_entity_label_with_flag(conn, "coin_labels", "outpoint", outpoint)
}

/// Check if a coin has an explicit (non-auto) label.
pub fn coin_has_explicit_label(conn: &Connection, outpoint: &str) -> Result<bool> {
    entity_has_explicit_label(conn, "coin_labels", "outpoint", outpoint)
}

//////////////////////////////
// unsigned_txs table       //
//////////////////////////////

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
) -> Result<i64> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    let mfps_str = mfps.join(",");
    conn.execute(
        "INSERT INTO unsigned_txs
         (psbt, txid, label, created_at, recipient, amount_sat, fee_sat, spend_path_id, threshold, mfps)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
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
            mfps_str
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
    })
}

pub fn get_psbt_row(conn: &Connection, id: i64) -> Result<PsbtRow> {
    conn.query_row(
        "SELECT id, psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
                spend_path_id, threshold, mfps
         FROM unsigned_txs WHERE id = ?1",
        rusqlite::params![id],
        parse_psbt_row,
    )
    .map_err(|e| anyhow::anyhow!("PSBT {} not found: {}", id, e))
}

pub fn get_psbt_row_by_txid(conn: &Connection, txid: &str) -> Result<Option<PsbtRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
                spend_path_id, threshold, mfps
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
                spend_path_id, threshold, mfps
         FROM unsigned_txs ORDER BY created_at DESC",
    )?;
    let rows = stmt
        .query_map([], parse_psbt_row)?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

//////////////////////////////
// seed_entries table        //
//////////////////////////////

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

pub fn list_seed_entries(conn: &Connection) -> Result<Vec<SeedEntry>> {
    let mut stmt = conn.prepare(
        "SELECT mfp, seed_type, mnemonic, passphrase, xprv, created_at FROM seed_entries ORDER BY created_at ASC",
    )?;
    let entries = stmt
        .query_map([], |row| {
            Ok(SeedEntry {
                mfp: row.get(0)?,
                seed_type: row.get(1)?,
                mnemonic: row.get(2)?,
                passphrase: row.get::<_, Option<String>>(3)?.unwrap_or_default(),
                xprv: row.get(4)?,
                created_at: row.get(5)?,
            })
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(entries)
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

////////////////////////
// fiat_prices table  //
////////////////////////

/// Create the fiat_prices table if it does not already exist.
pub fn ensure_fiat_prices_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS fiat_prices (
            txid     TEXT NOT NULL,
            currency TEXT NOT NULL,
            price    REAL NOT NULL,
            PRIMARY KEY (txid, currency)
        );",
    )?;
    Ok(())
}

/// Store (or replace) the BTC price in `currency` at the time of a transaction.
pub fn store_fiat_price(conn: &Connection, txid: &str, currency: &str, price: f64) -> Result<()> {
    conn.execute(
        "INSERT OR REPLACE INTO fiat_prices (txid, currency, price) VALUES (?1, ?2, ?3)",
        rusqlite::params![txid, currency, price],
    )?;
    Ok(())
}

/// Return all stored (txid, price) pairs for the given currency.
pub fn get_fiat_prices(conn: &Connection, currency: &str) -> Result<Vec<(String, f64)>> {
    let mut stmt = conn.prepare("SELECT txid, price FROM fiat_prices WHERE currency = ?1")?;
    let prices = stmt
        .query_map([currency], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, f64>(1)?))
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(prices)
}

/// Delete all stored fiat prices (called when the user changes currency).
pub fn clear_fiat_prices(conn: &Connection) -> Result<()> {
    conn.execute("DELETE FROM fiat_prices", [])?;
    Ok(())
}

/// Update last_synced_at to the current Unix timestamp and return it.
pub fn touch_last_synced(conn: &Connection) -> Result<i64> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    conn.execute(
        "UPDATE wallet_info SET last_synced_at = ?1 WHERE id = 1",
        rusqlite::params![now],
    )?;
    Ok(now)
}

/// Re-key an existing SQLCipher database from `old_key_hex` to `new_key_hex`.
pub fn rekey_database(path: &str, old_key_hex: &str, new_key_hex: &str) -> Result<()> {
    let conn = open_encrypted_connection(path, old_key_hex)?;
    conn.execute_batch(&format!("PRAGMA rekey = \"x'{}'\"", new_key_hex))?;
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
    ensure_coin_labels_table(&conn)?;
    ensure_seed_entries_table(&conn)?;
    ensure_fiat_prices_table(&conn)?;

    // Clean up orphaned auto-labels created before source_entity was tracked.
    // Auto-labels are derived data and will be regenerated by repropagate_all_labels.
    conn.execute(
        "DELETE FROM tx_labels WHERE is_auto = 1 AND source_entity IS NULL",
        [],
    )?;
    conn.execute(
        "DELETE FROM address_labels WHERE is_auto = 1 AND source_entity IS NULL",
        [],
    )?;
    conn.execute(
        "DELETE FROM coin_labels WHERE is_auto = 1 AND source_entity IS NULL",
        [],
    )?;

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

        upsert_wallet_info(&conn, "My Wallet", "desc", "bitcoin", 1_700_000_000)?;
        let row = read_wallet_info(&conn)?;

        assert_eq!(row.name, "My Wallet");
        assert_eq!(row.descriptor, "desc");
        assert_eq!(row.network, "bitcoin");
        assert_eq!(row.created_at, 1_700_000_000);
        assert!(row.last_synced_at.is_none());
        Ok(())
    }

    #[test]
    fn test_upsert_overwrites_previous_row() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("test.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;

        upsert_wallet_info(&conn, "Old Name", "desc", "testnet", 1_000)?;
        upsert_wallet_info(&conn, "New Name", "desc", "testnet", 1_000)?;
        let row = read_wallet_info(&conn)?;

        assert_eq!(row.name, "New Name");
        Ok(())
    }

    #[test]
    fn test_touch_last_synced() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("test.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;

        upsert_wallet_info(&conn, "Wallet", "desc", "bitcoin", 1_000)?;
        assert!(read_wallet_info(&conn)?.last_synced_at.is_none());

        let now = touch_last_synced(&conn)?;
        assert!(now > 0);
        let ts = read_wallet_info(&conn)?.last_synced_at;
        assert_eq!(ts, Some(now));
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
    fn test_ensure_coin_labels_table_idempotent() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("labels.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;

        // Calling twice must not fail (Bug 3)
        ensure_coin_labels_table(&conn)?;
        ensure_coin_labels_table(&conn)?;
        Ok(())
    }

    #[test]
    fn test_set_tx_label_stores_source_entity() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("labels.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;
        ensure_tx_labels_table(&conn)?;

        set_tx_label(&conn, "txid1", "Salary", true, Some("addr:bc1q…"))?;
        let (label, is_auto) = get_tx_label_with_flag(&conn, "txid1")?.unwrap();
        assert_eq!(label, "Salary");
        assert!(is_auto);

        // source_entity should be persisted
        let source: Option<String> = conn
            .query_row(
                "SELECT source_entity FROM tx_labels WHERE txid = 'txid1'",
                [],
                |row| row.get(0),
            )
            .ok()
            .flatten();
        assert_eq!(source.as_deref(), Some("addr:bc1q…"));
        Ok(())
    }

    #[test]
    fn test_explicit_label_has_null_source_entity() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("labels.db").to_string_lossy().to_string();
        let conn = open_encrypted_connection(&path, KEY_HEX)?;
        ensure_tx_labels_table(&conn)?;

        set_tx_label(&conn, "txid1", "Exchange", false, None)?;
        let source: Option<String> = conn
            .query_row(
                "SELECT source_entity FROM tx_labels WHERE txid = 'txid1'",
                [],
                |row| row.get(0),
            )
            .ok()
            .flatten();
        assert!(source.is_none());
        Ok(())
    }

    /// Reproduce the backup-labels bug: write a label via conn_a (opened through
    /// load_or_create_wallet), then check whether a fresh conn_b can see it.
    /// If conn_a leaves an open transaction, conn_b will see an empty table.
    #[test]
    fn test_label_visible_from_second_connection() -> Result<()> {
        let dir = tempdir()?;
        let path = dir.path().join("wallet.db").to_string_lossy().to_string();

        // Simulate the app: open wallet through load_or_create_wallet (same as CoreWallet::open)
        let (_wallet, conn_a) =
            load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;

        // Write a label exactly as set_address_label does from the live wallet
        set_address_label(&conn_a, "bc1qtest", "my-label", false, None)?;

        // conn_a can read it back (within its own transaction if any)
        let labels_a = get_all_address_labels(&conn_a)?;
        assert!(
            labels_a.contains_key("bc1qtest"),
            "Label not visible from conn_a itself"
        );

        // Now open a completely fresh connection — same as export_wallet_backup does
        let conn_b = open_encrypted_connection(&path, KEY_HEX)?;
        let labels_b = get_all_address_labels(&conn_b)?;
        assert!(
            labels_b.contains_key("bc1qtest"),
            "Label NOT visible from conn_b — conn_a likely has an uncommitted transaction. \
             labels_b = {:?}",
            labels_b
        );
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
