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
        descriptor: analyzer.canonical_descriptor_str(),
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

/// Validate that a descriptor's keys are compatible with the requested network.
///
/// A descriptor carrying mainnet keys (xpub/ypub/zpub) cannot be used on any
/// testnet variant, and vice versa. Returns Ok(()) when compatible, or an
/// error with a human-readable explanation.
pub fn validate_descriptor_network(descriptor: String, network: APINetwork) -> Result<()> {
    use bdk_wallet::bitcoin::Network;

    let detected =
        crate::core::descriptor_parser::DescriptorParser::parse(&descriptor)?.detect_network()?;
    let descriptor_is_mainnet = detected == Network::Bitcoin;
    let selected_is_mainnet = network == APINetwork::Bitcoin;

    if descriptor_is_mainnet != selected_is_mainnet {
        let descriptor_family = if descriptor_is_mainnet {
            "mainnet"
        } else {
            "testnet"
        };
        return Err(anyhow::anyhow!(
            "Descriptor uses {} keys but '{}' was selected",
            descriptor_family,
            network.display_name(),
        ));
    }
    Ok(())
}

/// Calculate the weight units (WU) of a transaction output for the given address.
///
/// The result only depends on the scriptPubKey type (P2PKH=136, P2SH=128,
/// P2WPKH=124, P2WSH=172, P2TR=172). Network validation is skipped so
/// mainnet, testnet, signet, and regtest addresses are all accepted.
pub fn address_output_wu(address: String) -> anyhow::Result<u64> {
    crate::core::address::address_output_wu(&address).map_err(Into::into)
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

/// Format a Taproot descriptor for Liana compatibility.
///
/// Liana requires the NUMS unspendable xpub (used as TR internal key when no
/// key-path spend exists) to carry an explicit [00000000] origin fingerprint.
/// The BIP380 standard omits this fingerprint, which is what Deadbolt generates
/// and what Nunchuk/most wallets expect.
///
/// Returns `Some(formatted_descriptor)` when the descriptor is TR with a NUMS
/// xpub internal key (no origin). Returns `None` when the format does not apply
/// (not TR, TR with a real key-path, or NUMS already has an origin).
pub fn format_descriptor_for_liana(descriptor: String) -> Result<Option<String>> {
    use bdk_wallet::keys::DescriptorPublicKey;
    use bdk_wallet::miniscript::Descriptor;

    let parsed: Descriptor<DescriptorPublicKey> = match descriptor.parse() {
        Ok(d) => d,
        Err(_) => return Ok(None),
    };

    let tr = match &parsed {
        Descriptor::Tr(tr) => tr,
        _ => return Ok(None),
    };

    let internal_key = tr.internal_key();

    // Check if the internal key is the NUMS unspendable xpub with no origin
    let is_nums = PubKey::try_from(internal_key.clone())
        .map(|pk| pk.is_unspendable())
        .unwrap_or(false);

    if !is_nums {
        return Ok(None);
    }

    // Check that the internal key has no existing origin (so we don't double-add).
    // BDK uses XPub for simple paths and MultiXPub for multi-path (<0;1>/*) keys.
    let has_origin = match internal_key {
        DescriptorPublicKey::XPub(xkey) => xkey.origin.is_some(),
        DescriptorPublicKey::MultiXPub(xkey) => xkey.origin.is_some(),
        DescriptorPublicKey::Single(_) => false,
    };
    if has_origin {
        return Ok(None);
    }

    // Canonical descriptor string (BDK adds checksum — strip it)
    let desc_str = parsed.to_string();
    let desc_body = match desc_str.rfind('#') {
        Some(idx) => &desc_str[..idx],
        None => &desc_str,
    };

    // Prepend [00000000] origin to the NUMS xpub
    let internal_key_str = internal_key.to_string();
    let liana_key_str = format!("[00000000]{}", internal_key_str);
    let liana_desc = desc_body.replacen(&internal_key_str, &liana_key_str, 1);

    Ok(Some(liana_desc))
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
            APINetwork::from(core_network).display_name(),
            expected_prefix
        ));
    }

    Ok(())
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
#[path = "analyzer_tests.rs"]
mod tests;
