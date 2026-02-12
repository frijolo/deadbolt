use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::api::model::{APINetwork, APIPubKey, APISpendPath, APISpendPathDef, APIWalletType};
use crate::core::descriptor::DescriptorAnalyzer;
use crate::core::descriptor_builder::{self, SpendPathDef};
use crate::core::pubkey::PubKey;
use crate::core::spend_path;

pub struct APIAnalysisResult {
    pub descriptor: String,
    pub network: APINetwork,
    pub wallet_type: APIWalletType,
    pub keys: Vec<APIPubKey>,
    pub spend_paths: Vec<APISpendPath>,
}

pub fn analyze_descriptor(descriptor: String) -> Result<APIAnalysisResult> {
    let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;

    let keys: Vec<APIPubKey> = analyzer
        .public_keys()?
        .iter()
        .map(|k| APIPubKey {
            mfp: k.mfp().to_string(),
            derivation_path: k
                .derivation_path()
                .map(|dp| dp.to_string())
                .unwrap_or_default(),
            xpub: k.xpub().map(|x| x.to_string()).unwrap_or_default(),
        })
        .collect();

    let spend_paths_core = analyzer.spend_paths()?;
    let spend_paths = APISpendPath::from_sorted(&spend_paths_core)?;

    Ok(APIAnalysisResult {
        descriptor,
        network: APINetwork::from(analyzer.network()),
        wallet_type: APIWalletType::from(analyzer.wallet_type()),
        keys,
        spend_paths,
    })
}

pub fn build_descriptor(
    wallet_type: APIWalletType,
    keys: Vec<APIPubKey>,
    spend_paths: Vec<APISpendPathDef>,
) -> Result<String> {
    let core_keys: Vec<PubKey> = keys
        .iter()
        .map(|k| PubKey::new(&k.mfp, &k.derivation_path, &k.xpub))
        .collect::<Result<Vec<_>>>()?;

    let core_paths: Vec<SpendPathDef> = spend_paths
        .iter()
        .map(|sp| SpendPathDef {
            threshold: sp.threshold as usize,
            mfps: sp.mfps.clone(),
            rel_timelock: sp.rel_timelock,
            abs_timelock: sp.abs_timelock,
            is_key_path: sp.is_key_path,
        })
        .collect();

    descriptor_builder::build_descriptor(wallet_type.into(), &core_keys, &core_paths)
}

/// Calculate the deterministic rustId for a spend path
/// Delegates to core::spend_path::calculate_spend_path_id (single source of truth)
pub fn calculate_spend_path_id(
    threshold: i32,
    mfps: Vec<String>,
    rel_timelock: u32,
    abs_timelock: u32,
) -> u32 {
    spend_path::calculate_spend_path_id(threshold as usize, &mfps, rel_timelock, abs_timelock)
}

/// Validate a key and check network compatibility
///
/// Returns Ok(()) if the key is valid and compatible with the network,
/// or Err with a descriptive message if validation fails.
pub fn validate_key(
    mfp: String,
    derivation_path: String,
    xpub: String,
    network: APINetwork,
) -> Result<()> {
    use bdk_wallet::bitcoin::Network;

    // Validate MFP format (8 hex characters)
    if mfp.len() != 8 {
        return Err(anyhow::anyhow!("Master fingerprint must be exactly 8 characters"));
    }
    if !mfp.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(anyhow::anyhow!("Master fingerprint must contain only hexadecimal characters (0-9, a-f)"));
    }

    // Try to create the PubKey (validates format)
    let pubkey = PubKey::new(&mfp, &derivation_path, &xpub)
        .map_err(|e| anyhow::anyhow!("Invalid key format: {}", e))?;

    // Check network compatibility
    let core_network: Network = network.into();
    if !pubkey.is_compatible_with_network(core_network)? {
        let expected_prefix = match core_network {
            Network::Bitcoin => "xpub, ypub, or zpub",
            Network::Testnet => "tpub, upub, or vpub",
            Network::Testnet4 => "tpub (testnet4)",
            Network::Signet => "tpub (signet)",
            Network::Regtest => "tpub (regtest)",
            _ => "appropriate prefix for this network",
        };
        return Err(anyhow::anyhow!(
            "Key is not compatible with {} network. Expected {}",
            network_display_name(core_network),
            expected_prefix
        ));
    }

    Ok(())
}

fn network_display_name(network: bdk_wallet::bitcoin::Network) -> &'static str {
    use bdk_wallet::bitcoin::Network;
    match network {
        Network::Bitcoin => "mainnet",
        Network::Testnet => "testnet",
        Network::Testnet4 => "testnet4",
        Network::Signet => "signet",
        Network::Regtest => "regtest",
        _ => "unknown",
    }
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::error::WalletError;

    #[test]
    fn test_mainnet() -> Result<()> {
        let descriptor = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
        let result = analyze_descriptor(String::from(descriptor))?;

        assert_eq!(result.network, APINetwork::Bitcoin);
        assert_eq!(result.wallet_type, APIWalletType::P2WSH);
        assert_eq!(result.keys.len(), 2);
        assert_eq!(result.spend_paths.len(), 1);

        assert_eq!(result.keys[0].mfp, "c449c5c5");
        assert_eq!(result.keys[1].mfp, "c61af686");

        let sp = result.spend_paths.first().ok_or(WalletError::MissingPolicy)?;
        assert_eq!(sp.threshold, 2);
        assert_eq!(sp.mfps.len(), 2);
        assert_eq!((sp.wu_base + sp.wu_in + sp.wu_out) / 4, 149);
        assert_eq!(sp.abs_timelock, 0);
        assert_eq!(sp.rel_timelock, 0);
        assert_eq!(sp.tr_depth, -1);

        Ok(())
    }

    #[test]
    fn test_testnet_single_key() -> Result<()> {
        let descriptor = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";
        let result = analyze_descriptor(String::from(descriptor))?;

        assert_eq!(result.network, APINetwork::Testnet);
        assert_eq!(result.wallet_type, APIWalletType::P2PKH);
        assert_eq!(result.keys.len(), 1);
        assert_eq!(result.keys[0].mfp, "73c5da0a");
        assert_eq!(result.spend_paths.len(), 1);

        Ok(())
    }
}
