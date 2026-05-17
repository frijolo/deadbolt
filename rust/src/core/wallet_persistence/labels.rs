use anyhow::{anyhow, Result};
use rusqlite::Connection;

// ===========================================================================
// Table-name allowlist
// ===========================================================================

const TABLES: &[&str] = &[
    "tx_labels",
    "address_labels",
    "key_labels",
    "path_labels",
    "coin_labels",
    // Dev zone (feature/future-tx-planning): apply_dev_schema uses ensure_column
    // on unsigned_txs to add the auto_broadcast flag. Remove from this list once
    // the dev migration is collapsed into a numbered migrate_v1_to_v2.
    "unsigned_txs",
];

/// Validate that `name` is an allowed label-table name.
///
/// This is a defensive guard against accidental SQL injection via table names.
/// All callers insert the table name directly into `format!` strings; the
/// identifier itself is never user input (it's always a literal from Rust
/// source), so this is a fuzzing / refactor safety net rather than a
/// runtime exploit prevention.
pub fn validate_table_name(name: &str) -> Result<()> {
    if TABLES.contains(&name) {
        Ok(())
    } else {
        Err(anyhow!(
            "unknown label table '{name}'; expected one of {}",
            TABLES.join(", ")
        ))
    }
}

// ---------------------------------------------------------------------------
// Migration helper
// ---------------------------------------------------------------------------

/// Add a column to `table` if it doesn't already exist.
/// `col_def` is the full SQL type + constraint, e.g. `"INTEGER NOT NULL DEFAULT 0"`.
/// This is a migration guard for DBs created before the column was introduced.
pub(super) fn ensure_column(
    conn: &Connection,
    table: &str,
    column: &str,
    col_def: &str,
) -> Result<()> {
    validate_table_name(table)?;
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
    validate_table_name(table)?;
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
    validate_table_name(table)?;
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
    validate_table_name(table)?;
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
    validate_table_name(table)?;
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
    validate_table_name(table)?;
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
    validate_table_name(table)?;
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
    validate_table_name(table)?;
    let mut stmt = conn.prepare(&format!(
        "SELECT 1 FROM {table} WHERE {key_col} = ?1 AND is_auto = 0"
    ))?;
    let exists = stmt.query_row([key], |_row| Ok(true)).ok();
    Ok(exists.unwrap_or(false))
}

// ---------------------------------------------------------------------------
// tx_labels table
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// address_labels table
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// key_labels table
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// path_labels table
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// coin_labels table
// ---------------------------------------------------------------------------

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
