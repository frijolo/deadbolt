use std::collections::HashSet;
use std::fmt;

use anyhow::Result;
use bdk_wallet::bitcoin::bip32::{DerivationPath, Fingerprint, Xpub};
use bdk_wallet::bitcoin::{Network, NetworkKind};
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::{Descriptor, ForEachKey};
use bdk_wallet::{KeychainKind, Wallet};

use crate::core::error::WalletError;

#[derive(Debug)]
pub struct PubKey {
    inner: DescriptorPublicKey,
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
        match key {
            DescriptorPublicKey::XPub(_) => Ok(PubKey { inner: key }),
            DescriptorPublicKey::MultiXPub(_) => Ok(PubKey { inner: key }),
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
            DescriptorPublicKey::XPub(k) => {
                Ok(k.origin.as_ref().map(|(_, path)| path.clone()).unwrap_or_default())
            }
            DescriptorPublicKey::MultiXPub(k) => {
                Ok(k.origin.as_ref().map(|(_, path)| path.clone()).unwrap_or_default())
            }
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

    /// Extract public keys from descriptor directly without requiring a wallet
    ///
    /// This is the new preferred method that avoids wallet creation.
    /// Uses the ForEachKey trait directly on the descriptor.
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
                pub_keys.push(pubkey);
            }
        }

        Ok(pub_keys)
    }

    /// Extract public keys from wallet (backward compatibility)
    ///
    /// This method is kept for backward compatibility with existing code
    /// that uses APIWallet. Internally delegates to extract_from_descriptor().
    pub fn extract_pub_keys(wallet: &Wallet) -> Result<Vec<PubKey>> {
        let descriptor = wallet.public_descriptor(KeychainKind::External);
        Self::extract_from_descriptor(&descriptor)
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
}
