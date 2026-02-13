use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::descriptor::ShInner;
use bdk_wallet::miniscript::Descriptor;
use bdk_wallet::Wallet;
use regex::Regex;

use crate::core::error::WalletError;
use crate::core::wallet::WalletType;

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
        // Extract all xpub-like prefixes from descriptor
        let re = Regex::new(r"\b([xyztvu]pub[1-9A-HJ-NP-Za-km-z]+)\b")
            .map_err(|_| WalletError::NetworkDetectionFailed)?;

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

    /// Detect which testnet variant (Testnet, Signet, Testnet4, Regtest)
    ///
    /// This still requires wallet creation but only tries testnet variants,
    /// reducing from 5 attempts to at most 4.
    fn detect_testnet_variant(&self) -> Result<Network> {
        // Try in order of likelihood
        for network in [
            Network::Testnet,
            Network::Signet,
            Network::Testnet4,
            Network::Regtest,
        ] {
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

    /// Fallback: detect network by trying wallet creation on all networks
    ///
    /// This is the old approach - only used when xpub parsing fails.
    /// Kept for correctness on unusual descriptors.
    fn detect_network_via_wallet(&self) -> Result<Network> {
        for network in [
            Network::Bitcoin,
            Network::Testnet,
            Network::Testnet4,
            Network::Signet,
            Network::Regtest,
        ] {
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

    /// Get wallet type by pattern matching on descriptor enum
    ///
    /// Uses BDK's Descriptor::Pkh/Wpkh/Wsh/Sh/Tr variants.
    /// This works without creating a wallet.
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

    /// Get the original descriptor string
    pub fn descriptor_str(&self) -> &str {
        &self.descriptor_str
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_p2pkh_testnet() -> Result<()> {
        let descriptor = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";
        let parser = DescriptorParser::parse(descriptor)?;

        assert_eq!(parser.wallet_type(), WalletType::P2PKH);
        assert_eq!(parser.detect_network()?, Network::Testnet);
        Ok(())
    }

    #[test]
    fn test_parse_p2wpkh_testnet() -> Result<()> {
        let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)#uxw7vpfc";
        let parser = DescriptorParser::parse(descriptor)?;

        assert_eq!(parser.wallet_type(), WalletType::P2WPKH);
        assert_eq!(parser.detect_network()?, Network::Testnet);
        Ok(())
    }

    #[test]
    fn test_parse_p2wsh_multisig_mainnet() -> Result<()> {
        let descriptor = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
        let parser = DescriptorParser::parse(descriptor)?;

        assert_eq!(parser.wallet_type(), WalletType::P2WSH);
        assert_eq!(parser.detect_network()?, Network::Bitcoin);
        Ok(())
    }

    #[test]
    fn test_parse_invalid_descriptor() {
        let descriptor = "invalid_descriptor";
        let result = DescriptorParser::parse(descriptor);

        assert!(result.is_err());
    }
}
