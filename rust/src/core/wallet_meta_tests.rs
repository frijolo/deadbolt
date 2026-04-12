use super::*;
use crate::core::key_protection::{generate_data_key, generate_salt};
use tempfile::tempdir;

#[test]
fn test_meta_path() {
    assert_eq!(
        meta_path("/data/wallets/abc-123.db"),
        "/data/wallets/abc-123.db.meta"
    );
}

#[test]
fn test_write_read_device_key_meta() -> Result<()> {
    let dir = tempdir()?;
    let wallet_path = dir.path().join("wallet.db").to_string_lossy().to_string();

    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key: generate_data_key(),
    };
    write_meta(&wallet_path, &meta)?;
    assert!(meta_exists(&wallet_path));

    let back = read_meta(&wallet_path)?;
    match back {
        ProtectionMeta::DeviceKey { version, .. } => assert_eq!(version, 1),
        _ => panic!("Wrong variant"),
    }
    Ok(())
}

#[test]
fn test_write_read_user_password_meta() -> Result<()> {
    let dir = tempdir()?;
    let wallet_path = dir.path().join("wallet.db").to_string_lossy().to_string();

    let meta = ProtectionMeta::UserPassword {
        version: 1,
        salt: generate_salt(),
        m_cost: 65536,
        t_cost: 3,
        p_cost: 1,
        wrapped_key: generate_data_key(),
        display_name: Some("Test".to_string()),
        network: Some("bitcoin".to_string()),
        last_synced_at: None,
    };
    write_meta(&wallet_path, &meta)?;

    let back = read_meta(&wallet_path)?;
    match back {
        ProtectionMeta::UserPassword {
            m_cost,
            t_cost,
            p_cost,
            ..
        } => {
            assert_eq!(m_cost, 65536);
            assert_eq!(t_cost, 3);
            assert_eq!(p_cost, 1);
        }
        _ => panic!("Wrong variant"),
    }
    Ok(())
}

#[test]
fn test_delete_meta() -> Result<()> {
    let dir = tempdir()?;
    let wallet_path = dir.path().join("wallet.db").to_string_lossy().to_string();

    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key: generate_data_key(),
    };
    write_meta(&wallet_path, &meta)?;
    assert!(meta_exists(&wallet_path));

    delete_meta(&wallet_path);
    assert!(!meta_exists(&wallet_path));
    Ok(())
}

#[test]
fn test_delete_meta_missing_is_ok() {
    // Should not panic if file doesn't exist
    delete_meta("/nonexistent/wallet.db");
}

#[test]
fn test_read_meta_missing_fails() {
    let result = read_meta("/nonexistent/wallet.db");
    assert!(result.is_err());
}
