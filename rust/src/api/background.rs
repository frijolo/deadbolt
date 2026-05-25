// Background auto-broadcast — FFI surface.
//
// Phase 0 spike: only the read-only `list_wallet_headers` is implemented.
// `run_background_tick` lands in Phase 1.
//
// See WIP/background_broadcast_android.md.

use anyhow::Result;
use flutter_rust_bridge::frb;
use std::path::Path;

use crate::core::key_protection::ProtectionMeta;
use crate::core::wallet_meta::read_meta;

/// Public header information about one wallet on disk.
///
/// `protection_type` mirrors `ProtectionMeta`:
///   - 0 = DeviceKey
///   - 1 = UserPassword
///   - 2 = XpubKey
#[frb]
#[derive(Debug, Clone)]
pub struct BgWalletHeader {
    pub wallet_path: String,
    pub protection_type: u8,
}

/// Enumerate `<app_support_dir>/wallets/*.db` and return their protection
/// type. Reads only the public `.meta` sidecar — never decrypts the DB body.
///
/// Wallets whose `.meta` is missing or malformed are silently skipped.
#[frb]
pub fn list_wallet_headers(app_support_dir: String) -> Result<Vec<BgWalletHeader>> {
    let wallets_dir = Path::new(&app_support_dir).join("wallets");
    if !wallets_dir.is_dir() {
        return Ok(Vec::new());
    }

    let mut out = Vec::new();
    for entry in std::fs::read_dir(&wallets_dir)? {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("db") {
            continue;
        }
        let wallet_path = match path.to_str() {
            Some(s) => s.to_string(),
            None => continue,
        };
        let meta = match read_meta(&wallet_path) {
            Ok(m) => m,
            Err(_) => continue,
        };
        out.push(BgWalletHeader {
            wallet_path,
            protection_type: protection_type_of(&meta),
        });
    }
    out.sort_by(|a, b| a.wallet_path.cmp(&b.wallet_path));
    Ok(out)
}

fn protection_type_of(meta: &ProtectionMeta) -> u8 {
    match meta {
        ProtectionMeta::DeviceKey { .. } => 0,
        ProtectionMeta::UserPassword { .. } => 1,
        ProtectionMeta::XpubKey { .. } => 2,
    }
}
