use std::collections::{BTreeSet, HashSet};
use std::fmt;
use std::sync::OnceLock;

use anyhow::Result;
use bdk_wallet::bitcoin::bip32::{ChildNumber, DerivationPath, Fingerprint, Xpub};
use bdk_wallet::bitcoin::hashes::{sha256, Hash, HashEngine};
use bdk_wallet::bitcoin::secp256k1::PublicKey;
use bdk_wallet::bitcoin::{Network, NetworkKind};
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::{Descriptor, ForEachKey};

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
        let bytes = hex::decode(NUMS_PUBKEY_HEX).expect("hardcoded NUMS constant is valid hex");
        PublicKey::from_slice(&bytes)
            .expect("NUMS_PUBKEY_HEX decodes to a valid compressed public key")
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

    /// Validate MFP format (8 hexadecimal characters).
    pub fn validate_mfp_format(mfp: &str) -> Result<()> {
        if mfp.len() != 8 {
            return Err(anyhow::anyhow!(
                "Master fingerprint must be exactly 8 characters"
            ));
        }
        if !mfp.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(anyhow::anyhow!(
                "Master fingerprint must contain only hexadecimal characters (0-9, a-f)"
            ));
        }
        Ok(())
    }

    /// Validate that this key's xpub is compatible with the given network.
    /// Returns an error with the expected key prefix when the network mismatches.
    pub fn validate_network(&self, network: Network) -> Result<()> {
        if self.is_compatible_with_network(network)? {
            return Ok(());
        }
        let expected_prefix = match network {
            Network::Bitcoin => "xpub, ypub, or zpub",
            Network::Testnet => "tpub, upub, or vpub",
            Network::Testnet4 => "tpub (testnet4)",
            Network::Signet => "tpub (signet)",
            Network::Regtest => "tpub (regtest)",
        };
        let network_name = match network {
            Network::Bitcoin => "mainnet",
            Network::Testnet => "testnet",
            Network::Testnet4 => "testnet4",
            Network::Signet => "signet",
            Network::Regtest => "regtest",
        };
        Err(anyhow::anyhow!(
            "Key is not compatible with {} network. Expected {}",
            network_name,
            expected_prefix
        ))
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

        // Collect all pubkeys into a BTreeSet (auto-sorted, deduplicated)
        let mut pubkeys: BTreeSet<Vec<u8>> = BTreeSet::new();
        for key in keys {
            let xpub = key.xpub()?;
            pubkeys.insert(xpub.public_key.serialize().to_vec());
        }

        // Calculate chaincode as SHA256 of concatenated pubkeys (BTreeSet order is stable)
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
}

#[cfg(test)]
#[path = "pubkey_tests.rs"]
mod tests;
