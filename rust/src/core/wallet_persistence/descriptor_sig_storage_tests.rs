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
