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

    /// BDK normalizes hardened paths (h → ') and appends a checksum on serialization.
    /// All descriptors stored in the app must go through this to ensure consistency.
    pub fn canonical_descriptor_str(&self) -> String {
        self.parser.canonical_descriptor_str()
    }
}

#[cfg(test)]
#[path = "descriptor_tests.rs"]
mod tests;
