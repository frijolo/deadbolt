use std::collections::HashMap;

use anyhow::Result;
use bdk_wallet::keys::DescriptorPublicKey;

use crate::api::model::{APIAbsoluteTimelock, APIRelativeTimelock};
use crate::core::error::WalletError;
use crate::core::pubkey::PubKey;
use crate::core::wallet::WalletType;

pub mod multisig;
pub mod single_key;
pub mod taproot;

pub use multisig::{build_path_policy, build_policy, build_sh, build_sh_wsh, build_wsh};
pub use single_key::{build_sh_wpkh, build_single_key};
pub use taproot::build_tr;

/// Definition of a spend path for descriptor building
pub struct SpendPathDef {
    pub threshold: usize,
    pub mfps: Vec<String>,
    pub rel_timelock: APIRelativeTimelock,
    pub abs_timelock: APIAbsoluteTimelock,
    pub is_key_path: bool,
    /// Taproot script tree priority (0 = deepest/least likely, higher = shallower/more likely).
    /// Ignored for non-Taproot descriptors.
    pub priority: usize,
}

/// Parse a descriptor string and return it with the canonical BDK checksum appended.
///
/// This is the single place where every generated descriptor is validated and
/// normalised. Calling `.to_string()` on the parsed `Descriptor` object makes
/// BDK append the `#xxxxxxxx` checksum, regardless of whether the raw string
/// already contained one.
fn append_checksum(desc_str: &str) -> Result<String> {
    let descriptor: bdk_wallet::miniscript::Descriptor<DescriptorPublicKey> = desc_str
        .parse()
        .map_err(|e| WalletError::BuilderError(format!("Invalid descriptor: {}", e)))?;
    Ok(descriptor.to_string())
}

/// Build a descriptor string from wallet type, keys, and spend path definitions.
///
/// Each spend path branch uses a distinct derivation pair (<0;1>/*, <2;3>/*, ...)
/// so the same xpub in different branches counts as a different key for the
/// policy compiler, avoiding "duplicate keys" errors.
///
/// All returned descriptors include the canonical BDK checksum (`#xxxxxxxx`).
pub fn build_descriptor(
    wallet_type: WalletType,
    keys: &[PubKey],
    spend_paths: &[SpendPathDef],
) -> Result<String> {
    if keys.is_empty() {
        return Err(WalletError::BuilderError("No keys provided".into()).into());
    }
    if spend_paths.is_empty() {
        return Err(WalletError::BuilderError("No spend paths provided".into()).into());
    }

    let raw = match wallet_type {
        WalletType::P2PKH => build_single_key("pkh", keys, spend_paths),
        WalletType::P2WPKH => build_single_key("wpkh", keys, spend_paths),
        WalletType::P2SH_WPKH => build_sh_wpkh(keys, spend_paths),
        WalletType::P2WSH => build_wsh(keys, spend_paths),
        WalletType::P2SH_WSH => build_sh_wsh(keys, spend_paths),
        WalletType::P2TR => build_tr(keys, spend_paths),
        WalletType::P2SH => build_sh(keys, spend_paths),
        WalletType::Unknown => {
            return Err(WalletError::BuilderError("Unknown wallet type".into()).into())
        }
    }?;

    // Ensure every descriptor leaves this function with a valid checksum,
    // regardless of whether the specific builder already added one.
    append_checksum(&raw)
}

// --- Key helpers (shared across submodules) ---

/// Construct key string with standard multipath wildcard
pub fn key_with_wildcard(key: &PubKey) -> String {
    format!("{}/<0;1>/*", key)
}

/// Construct key string with an unused derivation pair.
/// Tracks usage by xpub (not MFP) so that two different MFPs sharing the
/// same xpub receive different derivation slots and don't produce duplicates.
pub fn key_with_derivation(key: &PubKey, keys_uses: &mut HashMap<String, usize>) -> String {
    let xpub_id = key
        .xpub()
        .map(|x| x.to_string())
        .unwrap_or_else(|_| key.to_string());
    let uses: &mut usize = keys_uses.entry(xpub_id).or_insert(0);
    let ext = *uses * 2;
    let int = ext + 1;
    *uses += 1;
    format!("{}/<{};{}>/*", key, ext, int)
}

/// Find a key by its master fingerprint
pub fn resolve_key<'a>(mfp: &str, keys: &'a [PubKey]) -> Result<&'a PubKey> {
    keys.iter()
        .find(|k| k.mfp().to_string() == mfp)
        .ok_or_else(|| WalletError::BuilderError(format!("Key not found for MFP: {}", mfp)).into())
}

/// Resolve MFPs to key strings with standard <0;1>/* wildcard
pub fn resolve_key_strings(mfps: &[String], keys: &[PubKey]) -> Result<Vec<String>> {
    mfps.iter()
        .map(|mfp| {
            let key = resolve_key(mfp, keys)?;
            Ok(key_with_wildcard(key))
        })
        .collect()
}

/// Parse a key string into a DescriptorPublicKey
pub fn parse_dpk(key_str: &str, mfp: &str) -> Result<DescriptorPublicKey> {
    key_str.parse::<DescriptorPublicKey>().map_err(|e| {
        WalletError::BuilderError(format!("Failed to parse key for MFP {mfp}: {e}")).into()
    })
}

#[cfg(test)]
mod tests;
