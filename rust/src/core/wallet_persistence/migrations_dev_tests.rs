use super::*;
use crate::core::wallet_persistence::labels::ensure_column;
use crate::core::wallet_persistence::migrations::run_wallet_migrations;
use crate::core::wallet_persistence::open_encrypted_connection;
use crate::test_support::KEY_HEX;
use std::collections::HashSet;
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
fn ensure_column_adds_when_absent() -> Result<()> {
    let (conn, _dir) = open_test_db();
    conn.execute_batch("CREATE TABLE t (id INTEGER);")?;
    ensure_column(&conn, "t", "extra", "TEXT")?;
    assert!(column_set(&conn, "t").contains("extra"));
    Ok(())
}

#[test]
fn ensure_column_is_idempotent() -> Result<()> {
    let (conn, _dir) = open_test_db();
    conn.execute_batch("CREATE TABLE t (id INTEGER, extra TEXT);")?;
    conn.execute("INSERT INTO t (id, extra) VALUES (1, 'keep')", [])?;
    ensure_column(&conn, "t", "extra", "TEXT")?;
    ensure_column(&conn, "t", "extra", "TEXT")?;
    let kept: String = conn.query_row("SELECT extra FROM t WHERE id = 1", [], |r| r.get(0))?;
    assert_eq!(kept, "keep");
    Ok(())
}

#[test]
fn dev_schema_adds_auto_broadcast_column() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    assert!(column_set(&conn, "unsigned_txs").contains("auto_broadcast"));
    Ok(())
}

#[test]
fn dev_schema_runs_twice_safely() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    run_wallet_migrations(&conn)?;
    assert!(column_set(&conn, "unsigned_txs").contains("auto_broadcast"));
    Ok(())
}

#[test]
fn dev_schema_preserves_existing_psbt_rows() -> Result<()> {
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
