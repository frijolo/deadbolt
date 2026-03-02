use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIAbsoluteTimelock, APINetwork, APIPubKey, APIRelativeTimelock, APISpendPath, APISpendPathDef,
    APIWalletType,
};
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
            priority: sp.priority as usize,
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

/// Decode legacy relative timelock consensus value (for database migration)
pub fn decode_legacy_rel_timelock(consensus: u32) -> APIRelativeTimelock {
    APIRelativeTimelock::from_consensus(consensus)
}

/// Decode legacy absolute timelock consensus value (for database migration)
pub fn decode_legacy_abs_timelock(consensus: u32) -> APIAbsoluteTimelock {
    APIAbsoluteTimelock::from_consensus(consensus)
}

/// Calculate spend path rustId from semantic timelock values
/// Used when Flutter needs to compute rustId from type+value storage
pub fn calculate_rustid_from_timelocks(
    threshold: u32,
    mfps: Vec<String>,
    rel_timelock: APIRelativeTimelock,
    abs_timelock: APIAbsoluteTimelock,
) -> Result<u32> {
    let rel_consensus = rel_timelock.to_consensus()?;
    let abs_consensus = abs_timelock.to_consensus()?;

    Ok(spend_path::calculate_spend_path_id(
        threshold as usize,
        &mfps,
        rel_consensus,
        abs_consensus,
    ))
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
        return Err(anyhow::anyhow!(
            "Master fingerprint must be exactly 8 characters"
        ));
    }
    if !mfp.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(anyhow::anyhow!(
            "Master fingerprint must contain only hexadecimal characters (0-9, a-f)"
        ));
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

        let sp = result
            .spend_paths
            .first()
            .ok_or(WalletError::MissingPolicy)?;
        assert_eq!(sp.threshold, 2);
        assert_eq!(sp.mfps.len(), 2);
        assert_eq!((sp.wu_base + sp.wu_in + sp.wu_out) / 4, 149);
        assert_eq!(sp.abs_timelock.value, 0);
        assert_eq!(sp.rel_timelock.value, 0);
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

    #[test]
    fn test_invalid_descriptor_string() {
        // Completely invalid string
        let result = analyze_descriptor("not_a_descriptor".to_string());
        assert!(result.is_err(), "Should fail on invalid descriptor string");

        // Empty string
        let result = analyze_descriptor(String::new());
        assert!(result.is_err(), "Should fail on empty descriptor string");

        // Valid prefix but invalid content
        let result = analyze_descriptor("wsh(garbage_content)".to_string());
        assert!(
            result.is_err(),
            "Should fail on malformed descriptor content"
        );

        // Missing checksum separator (invalid descriptor format)
        let result = analyze_descriptor("pkh(deadbeef)".to_string());
        assert!(result.is_err(), "Should fail on invalid pkh content");
    }

    #[test]
    fn test_network_key_incompatibility() {
        // Mainnet descriptor with testnet key (tpub) — should fail
        let mainnet_wsh_with_tpub = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*,[c61af686/48h/0h/0h/2h]tpubDFZd1aJpE1HkahP7DAA6StKP9ZdgNTDM2qiSfpEvsgBYaeFuh53cccWkz6JVHD57g2nFH84kkVRwvabmPGQY68FqfPwHiftnRbbKNwGkagb/<0;1>/*))";
        let result = analyze_descriptor(mainnet_wsh_with_tpub.to_string());
        // tpub keys are not valid in mainnet wsh context — BDK should reject this
        // or our network detection should flag it as testnet and succeed with testnet analysis
        // Either way, validate_key() would catch incompatibility if validate_key is called
        // The main thing: this should not panic
        let _ = result;

        // Testnet key with mainnet descriptor format using xpub (incompatible versions)
        // validate_key should catch this
        let result = validate_key(
            "c449c5c5".to_string(),
            "48h/0h/0h/2h".to_string(),
            "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba".to_string(),
            APINetwork::Bitcoin, // Mainnet network but testnet key
        );
        assert!(
            result.is_err(),
            "Should fail when testnet key is used with mainnet network"
        );
        assert!(
            result.unwrap_err().to_string().contains("not compatible"),
            "Error should mention network incompatibility"
        );
    }

    #[test]
    fn test_validate_key_errors() {
        // Invalid MFP length (not 8 hex chars)
        let result = validate_key(
            "abc".to_string(),
            "48h/0h/0h/2h".to_string(),
            "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
            APINetwork::Bitcoin,
        );
        assert!(result.is_err(), "Should fail on short MFP");
        assert!(
            result.unwrap_err().to_string().contains("8 characters"),
            "Error should mention 8 character requirement"
        );

        // Non-hex MFP
        let result = validate_key(
            "GGGGGGGG".to_string(),
            "48h/0h/0h/2h".to_string(),
            "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
            APINetwork::Bitcoin,
        );
        assert!(result.is_err(), "Should fail on non-hex MFP");
        assert!(
            result.unwrap_err().to_string().contains("hexadecimal"),
            "Error should mention hexadecimal"
        );

        // Invalid xpub (garbage)
        let result = validate_key(
            "c449c5c5".to_string(),
            "48h/0h/0h/2h".to_string(),
            "not_an_xpub".to_string(),
            APINetwork::Bitcoin,
        );
        assert!(result.is_err(), "Should fail on invalid xpub");
    }

    #[test]
    fn test_build_descriptor_policy_failures() {
        use crate::api::model::{APIAbsoluteTimelock, APIRelativeTimelock, APISpendPathDef};

        // Empty keys list
        let result = build_descriptor(
            APIWalletType::P2WSH,
            vec![],
            vec![APISpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".to_string()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err(), "Should fail with no keys");

        // Empty spend paths list
        let result = build_descriptor(
            APIWalletType::P2WSH,
            vec![crate::api::model::APIPubKey {
                mfp: "c449c5c5".to_string(),
                derivation_path: "48h/0h/0h/2h".to_string(),
                xpub: "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
            }],
            vec![],
        );
        assert!(result.is_err(), "Should fail with no spend paths");

        // MFP referenced in path but not in keys
        let result = build_descriptor(
            APIWalletType::P2WSH,
            vec![crate::api::model::APIPubKey {
                mfp: "c449c5c5".to_string(),
                derivation_path: "48h/0h/0h/2h".to_string(),
                xpub: "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
            }],
            vec![APISpendPathDef {
                threshold: 1,
                mfps: vec!["deadbeef".to_string()], // MFP not in keys
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err(), "Should fail when MFP not found in keys");
    }

    #[test]
    fn test_taproot_without_keypath_roundtrip() -> Result<()> {
        // Descriptor with raw NUMS point (no keypath spend)
        let original_descriptor = "tr(50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0,{pk([c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*),pk([73c5da0a/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*)})#kvpt6nlf";

        // Analyze descriptor
        let result = analyze_descriptor(String::from(original_descriptor))?;

        // Should extract only 2 script path keys (NUMS excluded)
        assert_eq!(result.keys.len(), 2, "Should have only 2 script path keys");

        // No NUMS key should be present
        let nums_key = result.keys.iter().find(|k| k.mfp == "00000000");
        assert!(nums_key.is_none(), "NUMS key should not be in keys list");

        // Convert APISpendPath to APISpendPathDef for rebuild
        let spend_path_defs: Vec<APISpendPathDef> = result
            .spend_paths
            .iter()
            .map(|sp| {
                // Determine if this is a key-path (singlesig with no timelocks at depth 0)
                let is_key_path = sp.threshold == 1
                    && sp.mfps.len() == 1
                    && sp.rel_timelock.value == 0
                    && sp.abs_timelock.value == 0
                    && sp.tr_depth == -1; // tr_depth is 0-1 for keypath

                APISpendPathDef {
                    threshold: sp.threshold,
                    mfps: sp.mfps.clone(),
                    rel_timelock: sp.rel_timelock,
                    abs_timelock: sp.abs_timelock,
                    is_key_path,
                    priority: 0,
                }
            })
            .collect();

        // Rebuild descriptor using extracted keys and spend paths
        let rebuilt = build_descriptor(result.wallet_type, result.keys.clone(), spend_path_defs)?;

        // Rebuilt descriptor should NOT contain raw NUMS point
        assert!(
            !rebuilt.contains("50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"),
            "Rebuilt descriptor should not contain raw NUMS point"
        );

        // Rebuilt descriptor should contain NUMS xpub with wildcard (without fingerprint/derivation)
        // Format: tr(xpub.../<0;1>/*,{...})
        assert!(
            rebuilt.starts_with("tr(xpub") || rebuilt.starts_with("tr(tpub"),
            "Rebuilt descriptor should start with NUMS xpub (no fingerprint)"
        );

        assert!(
            rebuilt.contains("/<0;1>/*,{"),
            "NUMS xpub should have wildcard /<0;1>/*"
        );

        // Re-analyze the rebuilt descriptor to verify it's valid
        let reanalyzed = analyze_descriptor(rebuilt)?;
        assert_eq!(
            reanalyzed.keys.len(),
            2,
            "Reanalyzed should still have 2 keys"
        );
        assert_eq!(
            reanalyzed.spend_paths.len(),
            result.spend_paths.len(),
            "Spend paths should match"
        );

        Ok(())
    }
}
