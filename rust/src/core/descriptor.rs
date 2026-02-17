use anyhow::Result;
use bdk_wallet::bitcoin::Network;

use crate::core::descriptor_parser::DescriptorParser;
use crate::core::pubkey::PubKey;
use crate::core::spend_path::SpendPath;
use crate::core::wallet::WalletType;

/// High-level descriptor analysis without wallet creation
///
/// This facade provides a clean API for analyzing descriptors without
/// requiring creation of a full persistent wallet. It orchestrates:
/// - Descriptor parsing and validation
/// - Network detection (with minimal wallet creation)
/// - Wallet type detection
/// - Public key extraction
/// - Spend path analysis (creates temporary wallet for weight calculation)
pub struct DescriptorAnalyzer {
    parser: DescriptorParser,
    network: Network,
}

impl DescriptorAnalyzer {
    /// Analyze descriptor without creating a persistent wallet
    ///
    /// Performs parsing, validation, and network detection.
    /// This is much faster than creating a full wallet.
    ///
    /// Network detection avoids wallet creation for mainnet descriptors
    /// (uses xpub prefix detection). Testnet variants may create 1-4 temporary
    /// wallets for detection, which is still better than the old approach (5 wallets).
    pub fn analyze(descriptor: &str) -> Result<Self> {
        let parser = DescriptorParser::parse(descriptor)?;
        let network = parser.detect_network()?;

        Ok(Self { parser, network })
    }

    /// Get the detected network
    pub fn network(&self) -> Network {
        self.network
    }

    /// Get the wallet type (P2PKH, P2WPKH, P2WSH, etc.)
    ///
    /// This works without any wallet creation, using pattern matching
    /// on the parsed descriptor enum.
    pub fn wallet_type(&self) -> WalletType {
        self.parser.wallet_type()
    }

    /// Extract public keys from descriptor
    ///
    /// Uses the ForEachKey trait directly on the descriptor.
    /// No wallet creation required.
    pub fn public_keys(&self) -> Result<Vec<PubKey>> {
        PubKey::extract_from_descriptor(self.parser.descriptor())
    }

    /// Extract spend paths with weight calculations
    ///
    /// NOTE: This creates a temporary wallet for weight calculation,
    /// which requires actual transaction building via build_tx().
    /// This is unavoidable but acceptable - we create ONE temporary
    /// wallet instead of keeping a persistent wallet.
    pub fn spend_paths(&self) -> Result<Vec<SpendPath>> {
        SpendPath::extract_from_descriptor(self.parser.descriptor(), self.network)
    }

    /// Get the original descriptor string
    pub fn descriptor_str(&self) -> &str {
        self.parser.descriptor_str()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_analyze_p2pkh_testnet() -> Result<()> {
        let descriptor = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";

        let analyzer = DescriptorAnalyzer::analyze(descriptor)?;

        assert_eq!(analyzer.network(), Network::Testnet);
        assert_eq!(analyzer.wallet_type(), WalletType::P2PKH);

        let keys = analyzer.public_keys()?;
        assert_eq!(keys.len(), 1);

        let spend_paths = analyzer.spend_paths()?;
        assert_eq!(spend_paths.len(), 1);
        assert_eq!(spend_paths[0].threshold, 1);

        Ok(())
    }

    #[test]
    fn test_analyze_p2wpkh_testnet() -> Result<()> {
        let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)#uxw7vpfc";

        let analyzer = DescriptorAnalyzer::analyze(descriptor)?;

        assert_eq!(analyzer.network(), Network::Testnet);
        assert_eq!(analyzer.wallet_type(), WalletType::P2WPKH);

        let keys = analyzer.public_keys()?;
        assert_eq!(keys.len(), 1);

        let spend_paths = analyzer.spend_paths()?;
        assert_eq!(spend_paths.len(), 1);

        Ok(())
    }

    #[test]
    fn test_analyze_p2wsh_multisig_mainnet() -> Result<()> {
        let descriptor = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";

        let analyzer = DescriptorAnalyzer::analyze(descriptor)?;

        assert_eq!(analyzer.network(), Network::Bitcoin);
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);

        let keys = analyzer.public_keys()?;
        assert_eq!(keys.len(), 2);

        let spend_paths = analyzer.spend_paths()?;
        assert_eq!(spend_paths.len(), 1);
        assert_eq!(spend_paths[0].threshold, 2);

        Ok(())
    }
}
