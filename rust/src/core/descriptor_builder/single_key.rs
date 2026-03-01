use anyhow::Result;

use crate::core::error::WalletError;
use crate::core::pubkey::PubKey;

use super::{SpendPathDef, key_with_wildcard, resolve_key};

/// Single-key types: pkh(...), wpkh(...)
pub fn build_single_key(prefix: &str, keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    let sp = &spend_paths[0];
    if sp.threshold != 1 || sp.mfps.len() != 1 {
        return Err(WalletError::BuilderError(format!(
            "{} requires exactly 1 key with threshold 1",
            prefix
        ))
        .into());
    }
    let key = resolve_key(&sp.mfps[0], keys)?;
    Ok(format!("{}({})", prefix, key_with_wildcard(key)))
}

/// sh(wpkh(...))
pub fn build_sh_wpkh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    let sp = &spend_paths[0];
    if sp.threshold != 1 || sp.mfps.len() != 1 {
        return Err(WalletError::BuilderError(
            "P2SH-WPKH requires exactly 1 key with threshold 1".into(),
        )
        .into());
    }
    let key = resolve_key(&sp.mfps[0], keys)?;
    Ok(format!("sh(wpkh({}))", key_with_wildcard(key)))
}
