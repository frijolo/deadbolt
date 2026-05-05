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
    crate::core::descriptor_parser::DescriptorParser::parse(&descriptor)?
        .check_network_compatibility(network.into())
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
    PubKey::validate_mfp_format(&mfp)?;
    let pubkey = PubKey::new(&mfp, &derivation_path, &xpub)
        .map_err(|e| anyhow::anyhow!("Invalid key format: {}", e))?;
    pubkey.validate_network(network.into())
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // Install the default TLS CryptoProvider once at startup. electrum-client 0.24
    // checks get_default().is_none() before installing, but two concurrent Electrum
    // connections can both pass that check and the second install_default() fails.
    // Installing here — before any connections — makes the check always return Some.
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
}

#[cfg(test)]
#[path = "analyzer_tests.rs"]
mod tests;
