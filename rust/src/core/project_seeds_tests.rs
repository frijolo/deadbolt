use super::*;
use tempfile::tempdir;

const DEVICE_KEY: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

#[test]
fn test_create_and_reopen() -> Result<()> {
    let dir = tempdir()?;
    let app_dir = dir.path().to_string_lossy().to_string();

    let conn = open_project_seeds_db(&app_dir, DEVICE_KEY)?;
    drop(conn);

    // Second open must succeed
    let conn2 = open_project_seeds_db(&app_dir, DEVICE_KEY)?;
    drop(conn2);
    Ok(())
}

#[test]
fn test_insert_and_list() -> Result<()> {
    let dir = tempdir()?;
    let app_dir = dir.path().to_string_lossy().to_string();
    let conn = open_project_seeds_db(&app_dir, DEVICE_KEY)?;

    insert_project_seed_entry(
        &conn,
        1,
        "aabbccdd",
        "mnemonic",
        Some("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
        "",
        None,
    )?;

    let entries = list_project_seed_entries(&conn, 1)?;
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].mfp, "aabbccdd");
    assert_eq!(entries[0].seed_type, "mnemonic");

    // Different project sees nothing
    let entries2 = list_project_seed_entries(&conn, 2)?;
    assert!(entries2.is_empty());
    Ok(())
}

#[test]
fn test_reveal_and_delete() -> Result<()> {
    let dir = tempdir()?;
    let app_dir = dir.path().to_string_lossy().to_string();
    let conn = open_project_seeds_db(&app_dir, DEVICE_KEY)?;

    let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    insert_project_seed_entry(&conn, 1, "aabbccdd", "mnemonic", Some(mnemonic), "", None)?;

    let revealed = reveal_project_seed_value(&conn, 1, "aabbccdd")?;
    assert_eq!(revealed, mnemonic);

    delete_project_seed_entry(&conn, 1, "aabbccdd")?;
    assert!(list_project_seed_entries(&conn, 1)?.is_empty());
    Ok(())
}

#[test]
fn test_wrong_device_key_fails() -> Result<()> {
    let dir = tempdir()?;
    let app_dir = dir.path().to_string_lossy().to_string();

    // Create with correct key
    let _ = open_project_seeds_db(&app_dir, DEVICE_KEY)?;

    // Open with wrong key — AES-GCM unwrap must fail
    let wrong = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    let result = open_project_seeds_db(&app_dir, wrong);
    assert!(result.is_err());
    Ok(())
}
