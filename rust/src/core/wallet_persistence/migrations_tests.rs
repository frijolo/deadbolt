use super::*;
use crate::core::wallet_persistence::labels::{ensure_coin_labels_table, ensure_column};
use crate::core::wallet_persistence::open_encrypted_connection;
use crate::test_support::KEY_HEX;
use tempfile::tempdir;

fn open_test_db() -> (Connection, tempfile::TempDir) {
    let dir = tempdir().unwrap();
    let path = dir.path().join("test.db").to_string_lossy().to_string();
    let conn = open_encrypted_connection(&path, KEY_HEX).unwrap();
    (conn, dir)
}

fn column_set(conn: &Connection, table: &str) -> HashSet<String> {
    conn.prepare(&format!("PRAGMA table_info({table})"))
        .unwrap()
        .query_map([], |r| r.get::<_, String>(1))
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
}

#[test]
fn migration_sets_schema_version() -> Result<()> {
    let (conn, _dir) = open_test_db();
    assert_eq!(get_schema_version(&conn)?, 0);
    run_wallet_migrations(&conn)?;
    assert_eq!(get_schema_version(&conn)?, WALLET_SCHEMA_VERSION);
    Ok(())
}

#[test]
fn migration_is_idempotent() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    run_wallet_migrations(&conn)?; // must not fail
    assert_eq!(get_schema_version(&conn)?, WALLET_SCHEMA_VERSION);
    Ok(())
}

#[test]
fn migration_creates_descriptor_sigs_when_absent() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;

    // Table should now exist with the correct columns.
    let mut stmt = conn.prepare("PRAGMA table_info(descriptor_sigs)")?;
    let cols: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .filter_map(|r| r.ok())
        .collect();
    assert!(cols.contains(&"mfp".to_string()));
    assert!(cols.contains(&"sig_hex".to_string()));
    Ok(())
}

#[test]
fn migration_fixes_incompatible_descriptor_sigs_schema() -> Result<()> {
    let (conn, _dir) = open_test_db();

    // Simulate a provisional install: create descriptor_sigs with a different schema.
    conn.execute_batch(
        "CREATE TABLE descriptor_sigs (
            id       INTEGER PRIMARY KEY,
            mfp      TEXT NOT NULL UNIQUE,
            old_col  TEXT NOT NULL
        );",
    )?;

    // Migration must detect the mismatch and recreate with the correct schema.
    run_wallet_migrations(&conn)?;

    let mut stmt = conn.prepare("PRAGMA table_info(descriptor_sigs)")?;
    let cols: HashSet<String> = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .filter_map(|r| r.ok())
        .collect();
    assert!(cols.contains("xpub_entry"), "missing xpub_entry after fix");
    assert!(cols.contains("sig_method"), "missing sig_method after fix");
    assert!(cols.contains("sig_hex"), "missing sig_hex after fix");
    assert!(cols.contains("signed_at"), "missing signed_at after fix");
    assert!(!cols.contains("old_col"), "old column should be gone");
    Ok(())
}

#[test]
fn migration_preserves_correct_descriptor_sigs_data() -> Result<()> {
    let (conn, _dir) = open_test_db();

    // Pre-create descriptor_sigs with the correct schema and insert a row.
    conn.execute_batch(
        "CREATE TABLE descriptor_sigs (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            mfp        TEXT NOT NULL UNIQUE,
            xpub_entry TEXT NOT NULL,
            sig_method TEXT NOT NULL,
            sig_hex    TEXT NOT NULL,
            signed_at  INTEGER NOT NULL
        );",
    )?;
    conn.execute(
        "INSERT INTO descriptor_sigs (mfp, xpub_entry, sig_method, sig_hex, signed_at)
         VALUES ('aabbccdd', 'xpub...', 'bip322', 'deadbeef', 1700000000)",
        [],
    )?;

    run_wallet_migrations(&conn)?;

    // The existing row must survive.
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM descriptor_sigs WHERE mfp = 'aabbccdd'",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(count, 1, "existing descriptor sig was unexpectedly deleted");
    Ok(())
}

// ---------------------------------------------------------------------------
// v1 → v2: spaced tx planning
// ---------------------------------------------------------------------------

#[test]
fn migration_v2_adds_auto_broadcast_column() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    assert!(column_set(&conn, "unsigned_txs").contains("auto_broadcast"));
    Ok(())
}

#[test]
fn migration_v2_creates_tx_plans_table() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let exists: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='tx_plans'",
        [],
        |r| r.get(0),
    )?;
    assert_eq!(exists, 1);
    Ok(())
}

#[test]
fn migration_v2_preserves_existing_psbt_rows() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    conn.execute(
        "INSERT INTO unsigned_txs
         (psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
          spend_path_id, threshold, mfps, recipients_json)
         VALUES ('psbt', 'tx', NULL, 1700000000, 'r', 1, 1, 0, 1, '', NULL)",
        [],
    )?;
    run_wallet_migrations(&conn)?;
    let (auto, count): (i64, i64) = conn.query_row(
        "SELECT auto_broadcast, COUNT(*) FROM unsigned_txs",
        [],
        |r| Ok((r.get(0)?, r.get(1)?)),
    )?;
    assert_eq!(count, 1);
    assert_eq!(auto, 0, "auto_broadcast should default to 0");
    Ok(())
}

// ---------------------------------------------------------------------------
// ensure_column helper (exercised via migrate_v1_to_v2)
// ---------------------------------------------------------------------------

#[test]
fn ensure_column_adds_when_absent() -> Result<()> {
    // `ensure_column`'s `validate_table_name` allowlist (commit 3e3a8b7)
    // only accepts real production tables. Use the raw `coin_labels`
    // base schema *without* `ensure_coin_labels_table` (which would have
    // already added `is_auto` and `source_entity`), so the "add when
    // absent" branch is exercised.
    let (conn, _dir) = open_test_db();
    conn.execute_batch(
        "CREATE TABLE coin_labels (
            outpoint TEXT PRIMARY KEY,
            label    TEXT NOT NULL
        );",
    )?;
    assert!(!column_set(&conn, "coin_labels").contains("is_auto"));
    ensure_column(
        &conn,
        "coin_labels",
        "is_auto",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    assert!(column_set(&conn, "coin_labels").contains("is_auto"));
    Ok(())
}

#[test]
fn ensure_column_is_idempotent() -> Result<()> {
    let (conn, _dir) = open_test_db();
    ensure_coin_labels_table(&conn)?;
    conn.execute(
        "INSERT INTO coin_labels (outpoint, label) VALUES ('abc:0', 'keep')",
        [],
    )?;
    ensure_column(&conn, "coin_labels", "source_entity", "TEXT")?;
    ensure_column(&conn, "coin_labels", "source_entity", "TEXT")?;
    let kept: String = conn.query_row(
        "SELECT label FROM coin_labels WHERE outpoint = 'abc:0'",
        [],
        |r| r.get(0),
    )?;
    assert_eq!(kept, "keep");
    Ok(())
}
