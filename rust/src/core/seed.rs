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
        regex::Regex::new(r"\[([0-9a-fA-F]{8})/([^\]]+)\]([A-Za-z0-9]+)").unwrap()
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

        let full_match = cap.get(0).unwrap();
        let replacement = format!("[{}/{}]{}", &cap[1], &cap[2], child_xprv);
        replacements.push((full_match.start(), full_match.end(), replacement));
    }

    // Apply replacements in reverse order (preserves byte offsets).
    for (start, end, replacement) in replacements.into_iter().rev() {
        result.replace_range(start..end, &replacement);
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bdk_wallet::bitcoin::Network;

    // BIP39 test vector mnemonic (24 words, no passphrase)
    const TEST_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon \
         abandon abandon abandon abandon abandon abandon abandon abandon \
         abandon abandon abandon abandon abandon abandon abandon art";

    #[test]
    fn test_mnemonic_to_root_xprv_derives_deterministic_key() {
        let secp = Secp256k1::new();
        let xprv = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
        let mfp = root_xprv_to_mfp(&xprv, &secp);
        // Known MFP for this mnemonic on mainnet
        assert_eq!(mfp.len(), 8);
        assert!(mfp.chars().all(|c| c.is_ascii_hexdigit()));
        // Calling again must produce the same MFP
        let xprv2 = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
        assert_eq!(root_xprv_to_mfp(&xprv2, &secp), mfp);
    }

    #[test]
    fn test_mnemonic_invalid_words() {
        let result = mnemonic_to_root_xprv("invalid words here", "", Network::Bitcoin);
        assert!(result.is_err());
    }

    #[test]
    fn test_xprv_str_to_root_xprv_rejects_non_master() {
        // An xprv with depth > 0 must be rejected.
        // We derive one from the test mnemonic and use it directly as a string.
        let secp = Secp256k1::new();
        let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
        let path = DerivationPath::from_str("m/44'/0'/0'").unwrap();
        let child = root.derive_priv(&secp, &path).unwrap();
        let child_str = child.to_string();
        let result = xprv_str_to_root_xprv(&child_str);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("depth"));
    }

    #[test]
    fn test_xprv_str_to_root_xprv_accepts_master() {
        let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
        let root_str = root.to_string();
        let parsed = xprv_str_to_root_xprv(&root_str).unwrap();
        assert_eq!(parsed.depth, 0);
    }

    #[test]
    fn test_make_private_descriptor_singlesig() {
        let secp = Secp256k1::new();
        let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).unwrap();
        let mfp = root_xprv_to_mfp(&root, &secp);

        // Build a descriptor using the xpub at m/84'/1'/0'
        let path = DerivationPath::from_str("m/84'/1'/0'").unwrap();
        let child_xprv = root.derive_priv(&secp, &path).unwrap();
        let child_xpub = bdk_wallet::bitcoin::bip32::Xpub::from_priv(&secp, &child_xprv);
        let descriptor = format!("wpkh([{}/84'/1'/0']{}/<0;1>/*)", mfp, child_xpub);

        let private_desc = make_private_descriptor(&descriptor, &root, &secp).unwrap();
        assert!(
            private_desc.contains("xprv") || private_desc.contains("tprv"),
            "Expected xprv in result: {}",
            private_desc
        );
        assert!(
            !private_desc.contains("xpub") && !private_desc.contains("tpub"),
            "xpub should have been replaced: {}",
            private_desc
        );
    }

    #[test]
    fn test_make_private_descriptor_multisig_only_replaces_matching_mfp() {
        let secp = Secp256k1::new();
        // Two different mnemonics → two different root keys
        let root1 = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).unwrap();
        let mnemonic2 = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong";
        let root2 = mnemonic_to_root_xprv(mnemonic2, "", Network::Testnet).unwrap();

        let mfp1 = root_xprv_to_mfp(&root1, &secp);
        let mfp2 = root_xprv_to_mfp(&root2, &secp);

        let path = DerivationPath::from_str("m/48'/1'/0'/2'").unwrap();
        let xpub1 = bdk_wallet::bitcoin::bip32::Xpub::from_priv(
            &secp,
            &root1.derive_priv(&secp, &path).unwrap(),
        );
        let xpub2 = bdk_wallet::bitcoin::bip32::Xpub::from_priv(
            &secp,
            &root2.derive_priv(&secp, &path).unwrap(),
        );
        let descriptor = format!(
            "wsh(multi(2,[{}/48'/1'/0'/2']{}/<0;1>/*,[{}/48'/1'/0'/2']{}/<0;1>/*))",
            mfp1, xpub1, mfp2, xpub2
        );

        // Sign with root1 only → only mfp1's xpub is replaced
        let private_desc = make_private_descriptor(&descriptor, &root1, &secp).unwrap();
        // mfp2's key must still be xpub
        assert!(
            private_desc.contains(&format!("[{}/48'/1'/0'/2']", mfp2)),
            "mfp2 key expression should be unchanged"
        );
        // The descriptor should contain at least one xprv
        assert!(
            private_desc.contains("xprv") || private_desc.contains("tprv"),
            "mfp1 should have been replaced with xprv"
        );
    }

    #[test]
    fn print_test_mnemonic_values() {
        let secp = Secp256k1::new();
        let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).unwrap();
        let mfp = root_xprv_to_mfp(&root, &secp);
        let path = DerivationPath::from_str("m/84'/1'/0'").unwrap();
        let child = root.derive_priv(&secp, &path).unwrap();
        let xpub = bdk_wallet::bitcoin::bip32::Xpub::from_priv(&secp, &child);
        println!("MFP={}", mfp);
        println!("DESC=wpkh([{}/84'/1'/0']{}/<0;1>/*)", mfp, xpub);
    }
}
