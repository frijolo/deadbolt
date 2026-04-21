use super::*;
use crate::core::key_protection::ProtectionMeta;
use crate::core::wallet_meta::{meta_exists, read_meta};
use tempfile::tempdir;

const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
const DEVICE_KEY: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

#[test]
fn test_uuid_v4_format() {
    let uuid = generate_uuid_v4();
    assert_eq!(uuid.len(), 36);
    let parts: Vec<&str> = uuid.split('-').collect();
    assert_eq!(parts.len(), 5);
    assert_eq!(&uuid[14..15], "4");
    let variant = &uuid[19..20];
    assert!(["8", "9", "a", "b"].contains(&variant));
}

#[test]
fn test_uuid_v4_unique() {
    assert_ne!(generate_uuid_v4(), generate_uuid_v4());
}

#[test]
fn test_create_wallet_db_device_key() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, row) = create_wallet_db(
        &wallets_dir,
        "Test",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;

    assert!(std::path::Path::new(&path).exists());
    assert!(path.ends_with(".db"));
    assert!(meta_exists(&path));
    assert_eq!(row.name, "Test");
    assert_eq!(row.network, "bitcoin");
    assert!(row.last_synced_at.is_none());
    Ok(())
}

#[test]
fn test_create_wallet_db_user_password() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, row) = create_wallet_db(
        &wallets_dir,
        "Secure",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::UserPassword {
            password: "test-password".to_string(),
            m_cost: 1024,
            t_cost: 1,
        },
    )?;

    assert!(std::path::Path::new(&path).exists());
    assert!(meta_exists(&path));
    assert!(wallet_needs_password(&path));
    assert_eq!(row.name, "Secure");
    Ok(())
}

#[test]
fn test_device_key_wallet_opens_without_password() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, _) = create_wallet_db(
        &wallets_dir,
        "NoPass",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;

    let key = resolve_wallet_key(&path, DEVICE_KEY, None, None)?;
    let conn = open_encrypted_connection(&path, &key)?;
    let row = read_wallet_info(&conn)?;
    assert_eq!(row.name, "NoPass");
    Ok(())
}

#[test]
fn test_user_password_wallet_opens_with_correct_password() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, _) = create_wallet_db(
        &wallets_dir,
        "PassWallet",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::UserPassword {
            password: "my-secret".to_string(),
            m_cost: 1024,
            t_cost: 1,
        },
    )?;

    let key = resolve_wallet_key(&path, DEVICE_KEY, Some("my-secret"), None)?;
    let conn = open_encrypted_connection(&path, &key)?;
    let row = read_wallet_info(&conn)?;
    assert_eq!(row.name, "PassWallet");
    Ok(())
}

#[test]
fn test_user_password_wallet_fails_with_wrong_password() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, _) = create_wallet_db(
        &wallets_dir,
        "PassWallet",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::UserPassword {
            password: "correct".to_string(),
            m_cost: 1024,
            t_cost: 1,
        },
    )?;

    let result = resolve_wallet_key(&path, DEVICE_KEY, Some("wrong"), None);
    assert!(result.is_err(), "Should fail with wrong password");
    Ok(())
}

#[test]
fn test_user_password_wallet_fails_without_password() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, _) = create_wallet_db(
        &wallets_dir,
        "PassWallet",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::UserPassword {
            password: "secret".to_string(),
            m_cost: 1024,
            t_cost: 1,
        },
    )?;

    let result = resolve_wallet_key(&path, DEVICE_KEY, None, None);
    assert!(result.is_err(), "Should require password");
    let msg = result.unwrap_err().to_string();
    assert!(msg.contains("Password required"), "Error: {}", msg);
    Ok(())
}

#[test]
fn test_legacy_migration() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    // Create a legacy wallet (encrypted directly with device key, no .meta)
    let uuid = generate_uuid_v4();
    let path = dir
        .path()
        .join(format!("{}.db", uuid))
        .to_string_lossy()
        .to_string();
    let _ = crate::core::wallet_persistence::load_or_create_wallet(
        &path,
        MAINNET_DESC,
        bdk_wallet::bitcoin::Network::Bitcoin,
        DEVICE_KEY,
    )?;
    let conn = open_encrypted_connection(&path, DEVICE_KEY)?;
    crate::core::wallet_persistence::upsert_wallet_info(
        &conn,
        "Legacy",
        MAINNET_DESC,
        "bitcoin",
        1_000_000,
    )?;
    drop(conn);

    assert!(!meta_exists(&path), "Should start without .meta");

    // list_wallets_in_dir should auto-migrate
    let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].1.name, "Legacy");
    assert!(meta_exists(&path), "Should have .meta after migration");
    Ok(())
}

#[test]
fn test_list_wallets_empty_dir() {
    let dir = tempdir().unwrap();
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let result = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
    assert!(result.is_empty());
}

#[test]
fn test_list_wallets_multiple() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    create_wallet_db(
        &wallets_dir,
        "Wallet A",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;
    std::thread::sleep(std::time::Duration::from_secs(1));
    create_wallet_db(
        &wallets_dir,
        "Wallet B",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;

    let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
    assert_eq!(list.len(), 2);
    assert_eq!(list[0].1.name, "Wallet B");
    assert_eq!(list[1].1.name, "Wallet A");
    Ok(())
}

#[test]
fn test_list_wallets_includes_password_protected() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    // Create a device-key wallet
    create_wallet_db(
        &wallets_dir,
        "Open Wallet",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;

    // Create a password-protected wallet
    create_wallet_db(
        &wallets_dir,
        "Secret Vault",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::UserPassword {
            password: "s3cr3t".to_string(),
            m_cost: 1024,
            t_cost: 1,
        },
    )?;

    // Both wallets must appear in the list
    let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
    assert_eq!(
        list.len(),
        2,
        "Both wallets (open + locked) should be listed"
    );

    let names: Vec<&str> = list.iter().map(|(_, row)| row.name.as_str()).collect();
    assert!(names.contains(&"Open Wallet"), "Open wallet must appear");
    assert!(
        names.contains(&"Secret Vault"),
        "Password wallet must appear with its name"
    );

    // The password wallet's row has empty descriptor, correct network, and no sync date
    let locked = list.iter().find(|(_, r)| r.name == "Secret Vault").unwrap();
    assert!(
        locked.1.descriptor.is_empty(),
        "Locked wallet descriptor must be empty"
    );
    assert_eq!(
        locked.1.network, "bitcoin",
        "Locked wallet network cached from creation"
    );
    assert!(
        locked.1.last_synced_at.is_none(),
        "Locked wallet has no last_synced_at before any sync"
    );

    Ok(())
}

#[test]
fn test_refresh_user_password_meta_cache() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, _) = create_wallet_db(
        &wallets_dir,
        "Vault",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::UserPassword {
            password: "pw".to_string(),
            m_cost: 1024,
            t_cost: 1,
        },
    )?;

    // Initially last_synced_at should be None in the meta
    let meta = read_meta(&path)?;
    if let ProtectionMeta::UserPassword {
        last_synced_at,
        network,
        ..
    } = &meta
    {
        assert!(last_synced_at.is_none());
        assert_eq!(network.as_deref(), Some("bitcoin"));
    } else {
        panic!("Expected UserPassword meta");
    }

    // Simulate a sync: refresh cache with a timestamp
    refresh_user_password_meta_cache(&path, APINetwork::Testnet, Some(1_700_000_000), None);

    let updated = read_meta(&path)?;
    if let ProtectionMeta::UserPassword {
        last_synced_at,
        network,
        ..
    } = updated
    {
        assert_eq!(last_synced_at, Some(1_700_000_000));
        assert_eq!(network.as_deref(), Some("testnet"));
    } else {
        panic!("Expected UserPassword meta");
    }

    // list_wallets_in_dir should now show the updated network and last_synced_at
    let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
    assert_eq!(list.len(), 1);
    let row = &list[0].1;
    assert_eq!(row.network, "testnet");
    assert_eq!(row.last_synced_at, Some(1_700_000_000));
    Ok(())
}

#[test]
fn test_list_wallets_skips_non_wallet_files() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    create_wallet_db(
        &wallets_dir,
        "Real",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;

    std::fs::write(dir.path().join("notes.txt"), b"ignore me")?;

    let bad_path = dir.path().join("corrupt.db").to_string_lossy().to_string();
    let conn = crate::core::wallet_persistence::open_encrypted_connection(&bad_path, DEVICE_KEY)?;
    let _ = conn;

    let list = list_wallets_in_dir(&wallets_dir, DEVICE_KEY);
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].1.name, "Real");
    Ok(())
}

#[test]
fn test_get_wallet_info_from_file() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, _) = create_wallet_db(
        &wallets_dir,
        "MyWallet",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;

    let row = get_wallet_info_from_file(&path, DEVICE_KEY, None)?;
    assert_eq!(row.name, "MyWallet");
    Ok(())
}

#[test]
fn test_rename_wallet_in_file() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    let (path, _) = create_wallet_db(
        &wallets_dir,
        "Original",
        MAINNET_DESC,
        "bitcoin",
        DEVICE_KEY,
        WalletProtectionRequest::DeviceKey,
    )?;

    rename_wallet_in_file(&path, "Renamed", DEVICE_KEY, None)?;

    let row = get_wallet_info_from_file(&path, DEVICE_KEY, None)?;
    assert_eq!(row.name, "Renamed");
    Ok(())
}
