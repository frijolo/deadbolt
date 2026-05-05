use std::sync::OnceLock;

use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::descriptor::ShInner;
use bdk_wallet::miniscript::Descriptor;
use bdk_wallet::Wallet;
use regex::Regex;

use crate::core::error::WalletError;
use crate::core::wallet::WalletType;

static XPUB_REGEX: OnceLock<Regex> = OnceLock::new();
static SINGLE_PATH_REGEX: OnceLock<Regex> = OnceLock::new();
static XPUB_MFP_KEY_REGEX: OnceLock<Regex> = OnceLock::new();
static XPUB_DERIVATION_REGEX: OnceLock<Regex> = OnceLock::new();

/// Returns true if the descriptor uses a single derivation path (e.g. /0/*) instead of <0;1>/*.
fn is_single_path(descriptor: &str) -> bool {
    let re = SINGLE_PATH_REGEX.get_or_init(|| Regex::new(r"/\d+/\*").expect("static regex"));
    re.is_match(descriptor)
}

/// Returns a compiled regex for matching xpub-like prefixes, compiled once.
fn xpub_regex() -> &'static Regex {
    XPUB_REGEX.get_or_init(|| {
        Regex::new(r"\b([xyztvu]pub[1-9A-HJ-NP-Za-km-z]+)\b").expect("static regex")
    })
}

/// Extract a mfp→xpub map from a descriptor string.
/// Matches `[deadbeef/44'/0'/0']xpub6C...` style key expressions.
pub fn extract_xpub_mfp_map(descriptor: &str) -> std::collections::HashMap<String, String> {
    let re = xpub_mfp_key_regex();
    let mut map = std::collections::HashMap::new();
    for cap in re.captures_iter(descriptor) {
        map.insert(cap[1].to_lowercase(), cap[2].to_string());
    }
    map
}

fn xpub_mfp_key_regex() -> &'static Regex {
    XPUB_MFP_KEY_REGEX.get_or_init(|| {
        Regex::new(r"\[([0-9a-fA-F]{8})[^\]]*\]([A-Za-z]{1,4}pub[A-Za-z0-9]+)")
            .expect("static regex")
    })
}

/// Extract a mfp→derivation map from a descriptor string.
/// Matches `[deadbeef/48h/0h/0h/2h]xpub...` and returns the path suffix after the MFP.
pub fn extract_xpub_derivation_map(descriptor: &str) -> std::collections::HashMap<String, String> {
    let re = xpub_derivation_regex();
    let mut map = std::collections::HashMap::new();
    for cap in re.captures_iter(descriptor) {
        map.entry(cap[1].to_lowercase())
            .or_insert_with(|| cap[2].to_string());
    }
    map
}

fn xpub_derivation_regex() -> &'static Regex {
    XPUB_DERIVATION_REGEX
        .get_or_init(|| Regex::new(r"\[([0-9a-fA-F]{8})/([^\]]+)\]").expect("static regex"))
}

/// Extract `(mfp, xpub, derivation_hint)` triples from a descriptor.
/// Returns an error if the descriptor contains no xpubs.
pub fn xpub_slots_from_descriptor(
    descriptor: &str,
) -> anyhow::Result<Vec<(String, String, String)>> {
    let xpub_map = extract_xpub_mfp_map(descriptor);
    let deriv_map = extract_xpub_derivation_map(descriptor);
    if xpub_map.is_empty() {
        return Err(anyhow::anyhow!(
            "No xpubs found in descriptor for xpub extraction"
        ));
    }
    Ok(xpub_map
        .into_iter()
        .map(|(mfp, xpub)| {
            let derivation = deriv_map.get(&mfp).cloned().unwrap_or_default();
            (mfp, xpub, derivation)
        })
        .collect())
}
/// Lightweight descriptor parser that works without creating wallets
pub struct DescriptorParser {
    descriptor_str: String,
    parsed: Descriptor<DescriptorPublicKey>,
}

impl DescriptorParser {
    /// Parse descriptor from string without creating a wallet
    ///
    /// Uses BDK's built-in descriptor parser. This validates the descriptor
    /// syntax but doesn't require creating a full wallet.
    pub fn parse(descriptor: &str) -> Result<Self> {
        let parsed: Descriptor<DescriptorPublicKey> = descriptor
            .parse()
            .map_err(|_| WalletError::InvalidDescriptorSyntax)?;

        Ok(Self {
            descriptor_str: descriptor.to_string(),
            parsed,
        })
    }

    /// Detect network from descriptor WITHOUT creating wallets
    ///
    /// Strategy: Parse xpub prefixes from the descriptor string
    /// - xpub/ypub/zpub = Bitcoin mainnet
    /// - tpub/upub/vpub = Testnet family (requires further detection)
    ///
    /// This avoids creating up to 5 temporary wallets like the old approach.
    /// Falls back to wallet creation only if ambiguous.
    pub fn detect_network(&self) -> Result<Network> {
        // Single-path descriptors (e.g. /0/*) are not supported — require <0;1>/* format
        if is_single_path(&self.descriptor_str) {
            return Err(WalletError::SinglePathDescriptor.into());
        }

        // Extract all xpub-like prefixes from descriptor (regex compiled once via OnceLock)
        let re = xpub_regex();

        let mainnet_prefixes = ["xpub", "ypub", "zpub"];
        let testnet_prefixes = ["tpub", "upub", "vpub"];

        let mut found_mainnet = false;
        let mut found_testnet = false;

        for cap in re.captures_iter(&self.descriptor_str) {
            if let Some(xpub_match) = cap.get(1) {
                let xpub = xpub_match.as_str();
                if mainnet_prefixes.iter().any(|p| xpub.starts_with(p)) {
                    found_mainnet = true;
                }
                if testnet_prefixes.iter().any(|p| xpub.starts_with(p)) {
                    found_testnet = true;
                }
            }
        }

        match (found_mainnet, found_testnet) {
            (true, false) => Ok(Network::Bitcoin),
            (false, true) => {
                // Could be Testnet, Signet, Testnet4, or Regtest
                // Need to try wallet creation to distinguish
                self.detect_testnet_variant()
            }
            _ => {
                // Ambiguous or no xpubs found, fallback to wallet creation
                self.detect_network_via_wallet()
            }
        }
    }

    /// Try each network in order, returning the first one that parses the descriptor successfully.
    fn try_networks(&self, networks: &[Network]) -> Result<Network> {
        for &network in networks {
            if Wallet::create_from_two_path_descriptor(self.descriptor_str.clone())
                .network(network)
                .create_wallet_no_persist()
                .is_ok()
            {
                return Ok(network);
            }
        }
        Err(WalletError::NetworkDetectionFailed.into())
    }

    /// Detect which testnet variant (Testnet, Signet, Testnet4, Regtest)
    ///
    /// This still requires wallet creation but only tries testnet variants,
    /// reducing from 5 attempts to at most 4.
    fn detect_testnet_variant(&self) -> Result<Network> {
        self.try_networks(&[
            Network::Testnet,
            Network::Signet,
            Network::Testnet4,
            Network::Regtest,
        ])
    }

    /// Fallback: detect network by trying wallet creation on all networks
    ///
    /// This is the old approach - only used when xpub parsing fails.
    /// Kept for correctness on unusual descriptors.
    fn detect_network_via_wallet(&self) -> Result<Network> {
        self.try_networks(&[
            Network::Bitcoin,
            Network::Testnet,
            Network::Testnet4,
            Network::Signet,
            Network::Regtest,
        ])
    }

    /// Get wallet type by pattern matching on descriptor enum
    ///
    /// Uses BDK's Descriptor::Pkh/Wpkh/Wsh/Sh/Tr variants.
    /// This works without creating a wallet.
    /// Validate that this descriptor's keys are compatible with the requested
    /// network family (mainnet vs testnet). Signet/Testnet/Testnet4/Regtest are
    /// all considered the same family for descriptor key prefixes.
    pub fn check_network_compatibility(&self, network: Network) -> Result<()> {
        let detected = self.detect_network()?;
        let descriptor_is_mainnet = detected == Network::Bitcoin;
        let selected_is_mainnet = network == Network::Bitcoin;
        if descriptor_is_mainnet != selected_is_mainnet {
            let descriptor_family = if descriptor_is_mainnet {
                "mainnet"
            } else {
                "testnet"
            };
            let selected_name = match network {
                Network::Bitcoin => "mainnet",
                Network::Testnet => "testnet",
                Network::Testnet4 => "testnet4",
                Network::Signet => "signet",
                Network::Regtest => "regtest",
            };
            return Err(anyhow::anyhow!(
                "Descriptor uses {} keys but '{}' was selected",
                descriptor_family,
                selected_name,
            ));
        }
        Ok(())
    }

    pub fn wallet_type(&self) -> WalletType {
        match &self.parsed {
            Descriptor::Pkh(_) => WalletType::P2PKH,
            Descriptor::Sh(sh) => match sh.as_inner() {
                ShInner::Wsh(_) => WalletType::P2SH_WSH,
                ShInner::Wpkh(_) => WalletType::P2SH_WPKH,
                _ => WalletType::P2SH,
            },
            Descriptor::Wpkh(_) => WalletType::P2WPKH,
            Descriptor::Wsh(_) => WalletType::P2WSH,
            Descriptor::Tr(_) => WalletType::P2TR,
            _ => WalletType::Unknown,
        }
    }

    /// Access to parsed descriptor for further operations
    pub fn descriptor(&self) -> &Descriptor<DescriptorPublicKey> {
        &self.parsed
    }

    /// BDK normalizes hardened paths (h → ') and appends a checksum on serialization.
    pub fn canonical_descriptor_str(&self) -> String {
        self.parsed.to_string()
    }
}

#[cfg(test)]
#[path = "descriptor_parser_tests.rs"]
mod tests;
