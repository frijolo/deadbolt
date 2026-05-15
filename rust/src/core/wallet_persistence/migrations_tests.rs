use super::*;
use crate::core::wallet_persistence::open_encrypted_connection;
use crate::test_support::KEY_HEX;
use tempfile::tempdir;

fn open_test_db() -> (Connection, tempfile::TempDir) {
    let dir = tempdir().unwrap();
    let path = dir.path().join("test.db").to_string_lossy().to_string();
    let conn = open_encrypted_connection(&path, KEY_HEX).unwrap();
    (conn, dir)
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
