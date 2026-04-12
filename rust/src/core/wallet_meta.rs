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
#[path = "wallet_meta_tests.rs"]
mod tests;
