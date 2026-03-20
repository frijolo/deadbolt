use anyhow::Result;

use crate::core::key_protection::ProtectionMeta;

/// Return the .meta sidecar path for a wallet .db file.
/// e.g. "/path/to/<uuid>.db" → "/path/to/<uuid>.db.meta"
pub fn meta_path(wallet_path: &str) -> String {
    format!("{}.meta", wallet_path)
}

/// Serialize and write a `ProtectionMeta` to the sidecar file.
pub fn write_meta(wallet_path: &str, meta: &ProtectionMeta) -> Result<()> {
    let path = meta_path(wallet_path);
    let json = serde_json::to_string(meta)?;
    std::fs::write(&path, json)?;
    Ok(())
}

/// Read and deserialize the `ProtectionMeta` from the sidecar file.
pub fn read_meta(wallet_path: &str) -> Result<ProtectionMeta> {
    let path = meta_path(wallet_path);
    let json = std::fs::read_to_string(&path)
        .map_err(|e| anyhow::anyhow!("Cannot read meta file '{}': {}", path, e))?;
    let meta: ProtectionMeta = serde_json::from_str(&json)
        .map_err(|e| anyhow::anyhow!("Cannot parse meta file '{}': {}", path, e))?;
    Ok(meta)
}

/// Delete the sidecar file (silently ignores missing files).
pub fn delete_meta(wallet_path: &str) {
    let path = meta_path(wallet_path);
    let _ = std::fs::remove_file(path);
}

/// Returns true if the sidecar .meta file exists for this wallet.
pub fn meta_exists(wallet_path: &str) -> bool {
    std::path::Path::new(&meta_path(wallet_path)).exists()
}

#[cfg(test)]
mod tests {
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
}
