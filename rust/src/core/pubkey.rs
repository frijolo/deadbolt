use std::collections::HashSet;
use std::fmt;
use std::sync::OnceLock;

use anyhow::Result;
use bdk_wallet::bitcoin::bip32::{ChildNumber, DerivationPath, Fingerprint, Xpub};
use bdk_wallet::bitcoin::hashes::{sha256, Hash, HashEngine};
use bdk_wallet::bitcoin::secp256k1::PublicKey;
use bdk_wallet::bitcoin::{Network, NetworkKind};
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::{Descriptor, ForEachKey};
use bdk_wallet::{KeychainKind, Wallet};

use crate::core::error::WalletError;

/// BIP341 NUMS point as compressed pubkey (02 prefix + x-coordinate)
const NUMS_PUBKEY_HEX: &str = "0250929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0";

/// Singleton NUMS public key (initialized once, thread-safe)
static NUMS_PUBKEY: OnceLock<PublicKey> = OnceLock::new();

/// Get the NUMS public key (BIP341), initializing it lazily on first access
///
/// # Panics
/// Panics if NUMS_PUBKEY_HEX is invalid (should never happen as it's a hardcoded constant)
fn get_nums_pubkey() -> &'static PublicKey {
    NUMS_PUBKEY.get_or_init(|| {
        let bytes = hex::decode(NUMS_PUBKEY_HEX)
            .expect("NUMS_PUBKEY_HEX should be valid hex");
        PublicKey::from_slice(&bytes)
            .expect("NUMS_PUBKEY_HEX should be a valid compressed public key")
    })
}

#[derive(Debug)]
pub struct PubKey {
    inner: DescriptorPublicKey,
    is_unspendable: bool,
}

impl TryFrom<&String> for PubKey {
    type Error = anyhow::Error;

    fn try_from(s: &String) -> Result<Self, Self::Error> {
        Self::try_from(s.as_str())
    }
}

impl TryFrom<&str> for PubKey {
    type Error = anyhow::Error;

    fn try_from(keystr: &str) -> Result<PubKey, Self::Error> {
        let key: DescriptorPublicKey = keystr.parse()?;
        Self::try_from(key)
    }
}

impl TryFrom<DescriptorPublicKey> for PubKey {
    type Error = anyhow::Error;

    fn try_from(key: DescriptorPublicKey) -> Result<PubKey, Self::Error> {
        match &key {
            DescriptorPublicKey::XPub(_) | DescriptorPublicKey::MultiXPub(_) => {
                let is_unspendable = Self::check_is_unspendable(&key)?;
                Ok(PubKey {
                    inner: key,
                    is_unspendable,
                })
            }
            DescriptorPublicKey::Single(_) => Err(WalletError::UnsupportedKey.into()),
        }
    }
}

impl fmt::Display for PubKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.inner)
    }
}

impl PubKey {
    pub fn new(mfp: &str, derivation_path: &str, xpub: &str) -> Result<Self> {
        let keystr = if derivation_path.is_empty() {
            format!("[{}]{}", mfp, xpub)
        } else {
            format!("[{}/{}]{}", mfp, derivation_path, xpub)
        };
        Self::try_from(&keystr)
    }

    pub fn mfp(&self) -> Fingerprint {
        self.inner.master_fingerprint()
    }

    pub fn derivation_path(&self) -> Result<DerivationPath> {
        // Get the origin/master derivation path (the fixed part before wildcards)
        match &self.inner {
            DescriptorPublicKey::XPub(k) => Ok(k
                .origin
                .as_ref()
                .map(|(_, path)| path.clone())
                .unwrap_or_default()),
            DescriptorPublicKey::MultiXPub(k) => Ok(k
                .origin
                .as_ref()
                .map(|(_, path)| path.clone())
                .unwrap_or_default()),
            DescriptorPublicKey::Single(_) => Err(WalletError::UnsupportedKey.into()),
        }
    }

    pub fn xpub(&self) -> Result<Xpub> {
        match &self.inner {
            DescriptorPublicKey::XPub(k) => Ok(k.xkey),
            DescriptorPublicKey::MultiXPub(k) => Ok(k.xkey),
            DescriptorPublicKey::Single(_) => Err(WalletError::UnsupportedKey.into()),
        }
    }

    pub fn is_compatible_with_network(&self, network: Network) -> Result<bool> {
        Ok(self.xpub()?.network == NetworkKind::from(network))
    }

    /// Check if this key is unspendable (NUMS point)
    pub fn is_unspendable(&self) -> bool {
        self.is_unspendable
    }

    /// Check if a descriptor public key uses the NUMS point (private helper)
    fn check_is_unspendable(key: &DescriptorPublicKey) -> Result<bool> {
        let xpub = match key {
            DescriptorPublicKey::XPub(k) => k.xkey,
            DescriptorPublicKey::MultiXPub(k) => k.xkey,
            DescriptorPublicKey::Single(_) => return Ok(false),
        };

        // Compare with NUMS pubkey (singleton)
        Ok(xpub.public_key == *get_nums_pubkey())
    }

    /// Generate an unspendable xpub
    ///
    /// Creates an xpub with:
    /// - pubkey: BIP341 NUMS point
    /// - chaincode: SHA256(sorted and deduplicated pubkeys from all keys)
    /// - depth/parent_fingerprint/child_number: 0
    pub fn generate_unspendable_xpub(keys: &[PubKey], network: Network) -> Result<Xpub> {
        if keys.is_empty() {
            return Err(WalletError::BuilderError("No keys provided".into()).into());
        }

        // Collect all pubkeys
        let mut pubkeys: Vec<Vec<u8>> = Vec::new();
        for key in keys {
            let xpub = key.xpub()?;
            pubkeys.push(xpub.public_key.serialize().to_vec());
        }

        // Sort and deduplicate
        pubkeys.sort();
        pubkeys.dedup();

        // Calculate chaincode as SHA256 of concatenated pubkeys
        let mut hasher = sha256::Hash::engine();
        for pubkey in &pubkeys {
            hasher.input(pubkey);
        }
        let chain_code_hash = sha256::Hash::from_engine(hasher);

        // Create xpub with NUMS pubkey (singleton)
        let xpub = Xpub {
            network: NetworkKind::from(network),
            depth: 0,
            parent_fingerprint: Fingerprint::default(),
            child_number: ChildNumber::from_normal_idx(0)?,
            public_key: *get_nums_pubkey(),
            chain_code: chain_code_hash.to_byte_array().into(),
        };

        Ok(xpub)
    }

    /// Extract public keys from descriptor directly without requiring a wallet
    ///
    /// This is the new preferred method that avoids wallet creation.
    /// Uses the ForEachKey trait directly on the descriptor.
    /// Filters out unspendable (NUMS) keys and unsupported key types.
    ///
    /// Special case: For Taproot descriptors without keypath spend (internal_key is NUMS),
    /// generates a deterministic NUMS xpub and includes it in the results.
    pub fn extract_from_descriptor(
        descriptor: &Descriptor<DescriptorPublicKey>,
    ) -> Result<Vec<PubKey>> {
        let mut keys: Vec<&DescriptorPublicKey> = Vec::new();
        let mut seen_mfps: HashSet<Fingerprint> = HashSet::new();

        descriptor.for_each_key(|k| {
            if seen_mfps.insert(k.master_fingerprint()) {
                keys.push(k);
            }
            true
        });

        let mut pub_keys: Vec<PubKey> = Vec::new();

        for key in keys {
            // Skip unsupported key types (e.g., Single/raw keys like NUMS points)
            if let Ok(pubkey) = Self::try_from(key.clone()) {
                // Skip unspendable (NUMS) keys from script paths
                if !pubkey.is_unspendable() {
                    pub_keys.push(pubkey);
                }
            }
        }

        // Do NOT include NUMS keys (internal keys for Taproot without keypath)
        // The descriptor builder will generate the NUMS xpub automatically
        Ok(pub_keys)
    }

    /// Extract public keys from wallet (backward compatibility)
    ///
    /// This method is kept for backward compatibility with existing code
    /// that uses APIWallet. Internally delegates to extract_from_descriptor().
    pub fn extract_pub_keys(wallet: &Wallet) -> Result<Vec<PubKey>> {
        let descriptor = wallet.public_descriptor(KeychainKind::External);
        Self::extract_from_descriptor(descriptor)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key() -> Result<()> {
        let keystr = "[73c5da0a/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba";

        let pk = PubKey::try_from(keystr)?;

        assert_eq!(pk.mfp().to_string(), "73c5da0a");
        assert_eq!(pk.derivation_path()?.to_string(), "44'/1'/0'");
        assert_eq!(pk.xpub()?.to_string(), "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba");

        let reskey = pk.to_string();
        assert_eq!(&keystr, &reskey);

        let pk = PubKey::new(
            "73c5da0a",
            "44'/1'/0'",
            "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
        )?;

        let reskey = pk.to_string();
        assert_eq!(&keystr, &reskey);

        let compatible_with_mainnet = pk.is_compatible_with_network(Network::Bitcoin)?;
        assert_eq!(compatible_with_mainnet, false);
        let compatible_with_signet = pk.is_compatible_with_network(Network::Signet)?;
        assert_eq!(compatible_with_signet, true);

        Ok(())
    }

    #[test]
    fn test_key_without_derivation_path() -> Result<()> {
        // Test key without derivation path (root xpub)
        let pk = PubKey::new(
            "73c5da0a",
            "",
            "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
        )?;

        assert_eq!(pk.mfp().to_string(), "73c5da0a");
        let expected = "[73c5da0a]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba";
        assert_eq!(pk.to_string(), expected);

        Ok(())
    }

    #[test]
    fn test_key_with_wildcard_preserves_origin_path() -> Result<()> {
        // Test that keys with wildcards preserve the origin derivation path
        let keystr = "[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*";
        let pk = PubKey::try_from(keystr)?;

        assert_eq!(pk.mfp().to_string(), "c449c5c5");
        // BDK converts 'h' notation to apostrophe notation
        assert_eq!(pk.derivation_path()?.to_string(), "48'/0'/0'/2'");
        assert_eq!(pk.xpub()?.to_string(), "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn");

        Ok(())
    }

    #[test]
    fn test_generate_and_detect_nums_xpub() -> Result<()> {
        // Create some test keys
        let key1 = PubKey::try_from(
            "[73c5da0a/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
        )?;
        let key2 = PubKey::try_from(
            "[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn"
        )?;

        let keys = vec![key1, key2];

        // Generate NUMS xpub
        let nums_xpub = PubKey::generate_unspendable_xpub(&keys, Network::Signet)?;

        // Verify NUMS pubkey is used (singleton)
        assert_eq!(nums_xpub.public_key, *get_nums_pubkey());

        // Verify other fields
        assert_eq!(nums_xpub.depth, 0);
        assert_eq!(nums_xpub.parent_fingerprint, Fingerprint::default());
        assert_eq!(nums_xpub.child_number, ChildNumber::from_normal_idx(0)?);

        // Create a PubKey from the NUMS xpub and verify it's detected as unspendable
        let nums_key_str = format!("[00000000]{}", nums_xpub.to_string());
        let nums_key = PubKey::try_from(nums_key_str.as_str())?;
        assert!(nums_key.is_unspendable(), "NUMS key should be detected as unspendable");

        Ok(())
    }

    #[test]
    fn test_regular_key_not_unspendable() -> Result<()> {
        // Regular keys should not be detected as unspendable
        let regular_key = PubKey::try_from(
            "[73c5da0a/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
        )?;
        assert!(!regular_key.is_unspendable(), "Regular key should not be unspendable");

        Ok(())
    }

    #[test]
    fn test_nums_keys_excluded_from_descriptor() -> Result<()> {
        use bdk_wallet::keys::DescriptorPublicKey;
        use bdk_wallet::miniscript::Descriptor;

        // Descriptor with raw NUMS point as internal key
        let descriptor_str = "tr(50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0,{pk([c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*),pk([73c5da0a/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*)})#kvpt6nlf";

        let descriptor: Descriptor<DescriptorPublicKey> = descriptor_str.parse()?;

        // Extract keys - should NOT include NUMS
        let extracted_keys = PubKey::extract_from_descriptor(&descriptor)?;

        // Should have only 2 script path keys, NUMS excluded
        assert_eq!(extracted_keys.len(), 2, "Should extract only 2 script keys, NUMS excluded");

        // No keys should be unspendable
        let nums_count = extracted_keys.iter().filter(|k| k.is_unspendable()).count();
        assert_eq!(nums_count, 0, "Should have no NUMS keys");

        Ok(())
    }

    #[test]
    fn test_taproot_without_keypath_excludes_nums() -> Result<()> {
        use bdk_wallet::keys::DescriptorPublicKey;
        use bdk_wallet::miniscript::Descriptor;

        // Taproot descriptor without keypath (using raw NUMS point)
        let descriptor_str = "tr(50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0,{pk([c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*),pk([73c5da0a/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*)})#kvpt6nlf";

        let descriptor: Descriptor<DescriptorPublicKey> = descriptor_str.parse()?;

        // Extract keys - should only include script path keys, NOT NUMS
        let extracted_keys = PubKey::extract_from_descriptor(&descriptor)?;

        // Should have only 2 keys (script paths), NUMS excluded
        assert_eq!(extracted_keys.len(), 2, "Should extract only 2 script keys, NUMS excluded");

        // No unspendable keys
        let nums_count = extracted_keys.iter().filter(|k| k.is_unspendable()).count();
        assert_eq!(nums_count, 0, "Should have no NUMS keys");

        // Both keys should be regular keys
        assert_eq!(extracted_keys[0].mfp().to_string(), "c449c5c5");
        assert_eq!(extracted_keys[1].mfp().to_string(), "73c5da0a");

        Ok(())
    }
}
