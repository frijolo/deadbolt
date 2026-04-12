use anyhow::Result;
use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpriv, Xpub};
use bdk_wallet::bitcoin::secp256k1::{All, Secp256k1};
use bdk_wallet::bitcoin::Network;
use bdk_wallet::keys::bip39::Mnemonic;
use std::str::FromStr;

/// Parse a mnemonic phrase and derive the BIP32 root xprv for `network`.
pub fn mnemonic_to_root_xprv(words: &str, passphrase: &str, network: Network) -> Result<Xpriv> {
    let mnemonic =
        Mnemonic::parse(words).map_err(|e| anyhow::anyhow!("Invalid mnemonic: {}", e))?;
    let seed = mnemonic.to_seed(passphrase);
    let xprv = Xpriv::new_master(network, &seed)
        .map_err(|e| anyhow::anyhow!("Failed to derive master key: {}", e))?;
    Ok(xprv)
}

/// Parse an xprv string. Only accepts depth=0 (master key).
pub fn xprv_str_to_root_xprv(xprv_str: &str) -> Result<Xpriv> {
    let xprv = Xpriv::from_str(xprv_str).map_err(|e| anyhow::anyhow!("Invalid xprv: {}", e))?;
    if xprv.depth != 0 {
        return Err(anyhow::anyhow!(
            "Only master keys (depth=0) are accepted. This key has depth={}.",
            xprv.depth
        ));
    }
    Ok(xprv)
}

/// Return the master fingerprint (8 lowercase hex chars) of an xprv master key.
pub fn root_xprv_to_mfp(xprv: &Xpriv, secp: &Secp256k1<All>) -> String {
    let xpub = Xpub::from_priv(secp, xprv);
    let fingerprint = xpub.fingerprint();
    hex::encode(fingerprint.as_bytes())
}

/// Replace `[mfp/path]xpub...` entries in a descriptor with the corresponding
/// derived xprv from `root_xprv`, but only for entries whose MFP matches.
///
/// Returns the modified descriptor. If no matching entries are found, the
/// original descriptor is returned unchanged.
pub fn make_private_descriptor(
    descriptor: &str,
    root_xprv: &Xpriv,
    secp: &Secp256k1<All>,
) -> Result<String> {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        // Matches [8hexchars/path]xpub_or_xprv...
        // Stops at '/' (multipath), '<', ')', or '#' to not grab the separator
        regex::Regex::new(r"\[([0-9a-fA-F]{8})/([^\]]+)\]([A-Za-z0-9]+)")
            .expect("hard-coded key expression regex is valid")
    });

    let my_mfp = root_xprv_to_mfp(root_xprv, secp);

    let mut result = descriptor.to_string();
    // Collect replacements in reverse order so byte offsets remain valid.
    let mut replacements: Vec<(usize, usize, String)> = Vec::new();

    for cap in re.captures_iter(descriptor) {
        let cap_mfp = cap[1].to_lowercase();
        if cap_mfp != my_mfp {
            continue;
        }
        // Only replace if cap[3] looks like an xpub/tpub/upub/vpub (not already xprv/tprv).
        let key_str = &cap[3];
        if !key_str.starts_with("xpub")
            && !key_str.starts_with("tpub")
            && !key_str.starts_with("upub")
            && !key_str.starts_with("vpub")
        {
            continue;
        }

        // Derive child xprv at this path.
        let path_str = format!("m/{}", &cap[2]);
        let path = DerivationPath::from_str(&path_str)
            .map_err(|e| anyhow::anyhow!("Invalid derivation path '{}': {}", path_str, e))?;
        let child_xprv = root_xprv
            .derive_priv(secp, &path)
            .map_err(|e| anyhow::anyhow!("Derivation failed: {}", e))?;

        let full_match = cap.get(0).expect("regex match always has group 0");
        let replacement = format!("[{}/{}]{}", &cap[1], &cap[2], child_xprv);
        replacements.push((full_match.start(), full_match.end(), replacement));
    }

    // Apply replacements in reverse order (preserves byte offsets).
    for (start, end, replacement) in replacements.into_iter().rev() {
        result.replace_range(start..end, &replacement);
    }

    Ok(result)
}

/// Remove the BDK checksum suffix (`#xxxxxxxx`) from a descriptor string.
///
/// Used before feeding a private descriptor into `Wallet::create` because
/// replacing xpub→xprv invalidates the existing checksum and BDK rejects
/// descriptors with an incorrect one.
pub fn strip_descriptor_checksum(desc: &str) -> String {
    match desc.rfind('#') {
        Some(idx) => desc[..idx].to_string(),
        None => desc.to_string(),
    }
}

/// Split a multi-path descriptor into its external and internal variants.
///
/// BDK cannot create a wallet from a descriptor that contains both an xprv
/// and a `<n;m>` multi-path suffix. This function replaces every `/<n;m>/`
/// occurrence with `/<n>/` (external) and `/<m>/` (internal) respectively,
/// producing two single-path descriptors suitable for `Wallet::create`.
pub fn split_multipath_descriptor(desc: &str) -> (String, String) {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| regex::Regex::new(r"/<(\d+);(\d+)>/").expect("static regex"));
    (
        re.replace_all(desc, "/$1/").to_string(),
        re.replace_all(desc, "/$2/").to_string(),
    )
}

/// Extract the account derivation path for a given MFP from a descriptor string.
///
/// Scans the descriptor for `[mfp/path]xpub...` entries and returns the path
/// component (e.g. `"84'/0'/0'"`) for the first entry that matches `mfp`.
///
/// Used by `derive_address_wif` to reconstruct the full derivation path
/// `m/{account_path}/{chain}/{index}` needed to derive a leaf private key.
pub fn extract_account_path_for_mfp(descriptor: &str, mfp: &str) -> Result<String> {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        regex::Regex::new(r"\[([0-9a-fA-F]{8})/([^\]]+)\]([A-Za-z0-9]+)")
            .expect("hard-coded key expression regex is valid")
    });

    let mfp_lower = mfp.to_lowercase();
    for cap in re.captures_iter(descriptor) {
        if cap[1].to_lowercase() == mfp_lower {
            return Ok(cap[2].to_string());
        }
    }
    Err(anyhow::anyhow!(
        "No key entry for MFP {} found in descriptor",
        mfp
    ))
}

/// Derive a root xprv from a stored seed entry's fields.
///
/// Handles both seed types in one place so callers don't repeat the
/// `if seed_type == "mnemonic" { ... } else { ... }` branch.
pub fn seed_entry_to_root_xprv(
    seed_type: &str,
    mnemonic: Option<&str>,
    passphrase: &str,
    xprv: Option<&str>,
    network: Network,
) -> Result<Xpriv> {
    if seed_type == "mnemonic" {
        let words = mnemonic.ok_or_else(|| anyhow::anyhow!("Mnemonic missing for seed entry"))?;
        mnemonic_to_root_xprv(words, passphrase, network)
    } else {
        let xprv_str = xprv.ok_or_else(|| anyhow::anyhow!("xprv missing for seed entry"))?;
        xprv_str_to_root_xprv(xprv_str)
    }
}

#[cfg(test)]
#[path = "seed_tests.rs"]
mod tests;
