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

    let (_wallet, _conn) = load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;
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
    let (_wallet, _conn) = load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;
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
    let (_wallet, conn_a) = load_or_create_wallet(&path, MAINNET_DESC, Network::Bitcoin, KEY_HEX)?;

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

// ---------------------------------------------------------------------------
// S2.5 — validate_table_name allowlist tests
// ---------------------------------------------------------------------------

#[test]
fn test_validate_table_name_accepts_all_known_tables() -> Result<()> {
    for table in [
        "tx_labels",
        "address_labels",
        "key_labels",
        "path_labels",
        "coin_labels",
    ] {
        validate_table_name(table)?;
    }
    Ok(())
}

#[test]
fn test_validate_table_name_rejects_invalid_names() -> Result<()> {
    let invalid = [
        "",
        "users",
        "sqlite_master",
        "tx_labels; DROP TABLE tx_labels;",
        " tx_labels",
        "tx_labels ",
        "0tx_labels",
        "coin_labelsx",
    ];
    for name in &invalid {
        assert!(
            validate_table_name(name).is_err(),
            "expected reject for '{name}'"
        );
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// S2.3 — list_seed_entries with corrupt rows
// ---------------------------------------------------------------------------

#[test]
fn test_list_seed_entries_returns_corrupt_rows() -> Result<()> {
    let dir = tempdir()?;
    let path = dir.path().join("test.db").to_string_lossy().to_string();
    let conn = open_encrypted_connection(&path, KEY_HEX)?;

    ensure_seed_entries_table(&conn)?;

    // Insert a valid entry
    insert_seed_entry(&conn, "abcd1234", "mnemonic", Some("testseed"), "", None)?;

    // Corrupt a row by inserting a non-numeric created_at
    conn.execute(
        "INSERT INTO seed_entries (mfp, seed_type, mnemonic, passphrase, xprv, created_at) \
         VALUES ('corrupt1', 'mnemonic', 'bad', '', '', 'not_a_number')",
        [],
    )?;

    let (entries, corrupt_rows) = list_seed_entries(&conn)?;

    // Valid entry should be returned
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].mfp, "abcd1234");

    // Corrupt row should be reported, not propagated as error
    assert_eq!(corrupt_rows.len(), 1);
    assert!(corrupt_rows[0].starts_with("Corrupt seed entry #"));

    Ok(())
}

#[test]
fn test_list_seed_entries_multiple_corrupt_rows() -> Result<()> {
    let dir = tempdir()?;
    let path = dir.path().join("test.db").to_string_lossy().to_string();
    let conn = open_encrypted_connection(&path, KEY_HEX)?;

    ensure_seed_entries_table(&conn)?;

    // Insert two valid entries
    insert_seed_entry(&conn, "abcd1234", "mnemonic", Some("seed1"), "", None)?;
    insert_seed_entry(&conn, "efgh5678", "xprv", None, "xprv1", None)?;

    // Corrupt two rows with different issues
    conn.execute(
        "INSERT INTO seed_entries (mfp, seed_type, mnemonic, passphrase, xprv, created_at) \
         VALUES ('bad1', 'mnemonic', 'x', '', '', 'NaN')",
        [],
    )?;
    conn.execute(
        "INSERT INTO seed_entries (mfp, seed_type, mnemonic, passphrase, xprv, created_at) \
         VALUES ('bad2', 'mnemonic', 'y', '', '', 'abc')",
        [],
    )?;

    let (entries, corrupt_rows) = list_seed_entries(&conn)?;

    assert_eq!(entries.len(), 2);
    assert_eq!(corrupt_rows.len(), 2);
    assert!(corrupt_rows[0].starts_with("Corrupt seed entry #1"));
    assert!(corrupt_rows[1].starts_with("Corrupt seed entry #2"));

    Ok(())
}
