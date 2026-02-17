use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

use anyhow::Result;
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::policy::concrete::{DescriptorCtx, Policy as ConcretePolicy};
use bdk_wallet::miniscript::{Legacy, Segwitv0};

use crate::api::model::{APIAbsoluteTimelock, APIRelativeTimelock};
use crate::core::error::WalletError;
use crate::core::pubkey::PubKey;
use crate::core::wallet::WalletType;

/// Definition of a spend path for descriptor building
pub struct SpendPathDef {
    pub threshold: usize,
    pub mfps: Vec<String>,
    pub rel_timelock: APIRelativeTimelock,
    pub abs_timelock: APIAbsoluteTimelock,
    pub is_key_path: bool,
    /// Taproot script tree priority (0 = deepest/least likely, higher = shallower/more likely).
    /// Ignored for non-Taproot descriptors.
    pub priority: usize,
}

/// Build a descriptor string from wallet type, keys, and spend path definitions.
///
/// Each spend path branch uses a distinct derivation pair (<0;1>/*, <2;3>/*, ...)
/// so the same xpub in different branches counts as a different key for the
/// policy compiler, avoiding "duplicate keys" errors.
pub fn build_descriptor(
    wallet_type: WalletType,
    keys: &[PubKey],
    spend_paths: &[SpendPathDef],
) -> Result<String> {
    if keys.is_empty() {
        return Err(WalletError::BuilderError("No keys provided".into()).into());
    }
    if spend_paths.is_empty() {
        return Err(WalletError::BuilderError("No spend paths provided".into()).into());
    }

    match wallet_type {
        WalletType::P2PKH => build_single_key("pkh", keys, spend_paths),
        WalletType::P2WPKH => build_single_key("wpkh", keys, spend_paths),
        WalletType::P2SH_WPKH => build_sh_wpkh(keys, spend_paths),
        WalletType::P2WSH => build_wsh(keys, spend_paths),
        WalletType::P2SH_WSH => build_sh_wsh(keys, spend_paths),
        WalletType::P2TR => build_tr(keys, spend_paths),
        WalletType::P2SH => build_sh(keys, spend_paths),
        WalletType::Unknown => Err(WalletError::BuilderError("Unknown wallet type".into()).into()),
    }
}

// --- Key helpers ---

/// Construct key string with standard multipath wildcard
fn key_with_wildcard(key: &PubKey) -> String {
    format!("{}/<0;1>/*", key)
}

/// Construct key string with an unused derivation pair.
/// Tracks usage by xpub (not MFP) so that two different MFPs sharing the
/// same xpub receive different derivation slots and don't produce duplicates.
fn key_with_derivation(key: &PubKey, keys_uses: &mut HashMap<String, usize>) -> String {
    let xpub_id = key
        .xpub()
        .map(|x| x.to_string())
        .unwrap_or_else(|_| key.to_string());
    let uses: &mut usize = keys_uses.entry(xpub_id).or_insert(0);
    let ext = *uses * 2;
    let int = ext + 1;
    *uses += 1;
    format!("{}/<{};{}>/*", key, ext, int)
}

/// Find a key by its master fingerprint
fn resolve_key<'a>(mfp: &str, keys: &'a [PubKey]) -> Result<&'a PubKey> {
    keys.iter()
        .find(|k| k.mfp().to_string() == mfp)
        .ok_or_else(|| WalletError::BuilderError(format!("Key not found for MFP: {}", mfp)).into())
}

/// Resolve MFPs to key strings with standard <0;1>/* wildcard
fn resolve_key_strings(mfps: &[String], keys: &[PubKey]) -> Result<Vec<String>> {
    mfps.iter()
        .map(|mfp| {
            let key = resolve_key(mfp, keys)?;
            Ok(key_with_wildcard(key))
        })
        .collect()
}

/// Parse a key string into a DescriptorPublicKey
fn parse_dpk(key_str: &str, mfp: &str) -> Result<DescriptorPublicKey> {
    key_str.parse::<DescriptorPublicKey>().map_err(|_| {
        WalletError::BuilderError(format!("Failed to parse key for MFP: {}", mfp)).into()
    })
}

// --- Simple descriptor types (single path, no policy compiler) ---

/// Single-key types: pkh(...), wpkh(...)
fn build_single_key(prefix: &str, keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    let sp = &spend_paths[0];
    if sp.threshold != 1 || sp.mfps.len() != 1 {
        return Err(WalletError::BuilderError(format!(
            "{} requires exactly 1 key with threshold 1",
            prefix
        ))
        .into());
    }
    let key = resolve_key(&sp.mfps[0], keys)?;
    Ok(format!("{}({})", prefix, key_with_wildcard(key)))
}

/// sh(wpkh(...))
fn build_sh_wpkh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    let sp = &spend_paths[0];
    if sp.threshold != 1 || sp.mfps.len() != 1 {
        return Err(WalletError::BuilderError(
            "P2SH-WPKH requires exactly 1 key with threshold 1".into(),
        )
        .into());
    }
    let key = resolve_key(&sp.mfps[0], keys)?;
    Ok(format!("sh(wpkh({}))", key_with_wildcard(key)))
}

/// Check if spend paths represent a simple multisig (1 path, no timelocks)
fn is_simple_multisig(spend_paths: &[SpendPathDef]) -> bool {
    spend_paths.len() == 1 && spend_paths[0].rel_timelock.value == 0 && spend_paths[0].abs_timelock.value == 0 && spend_paths[0].mfps.len() > 1
}

// --- Complex descriptor types (policy compiler) ---

/// wsh(sortedmulti(...)) or wsh(compiled_policy)
fn build_wsh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    if is_simple_multisig(spend_paths) {
        let sp = &spend_paths[0];
        let key_strs = resolve_key_strings(&sp.mfps, keys)?;
        return Ok(format!(
            "wsh(sortedmulti({},{}))",
            sp.threshold,
            key_strs.join(",")
        ));
    }
    let policy = build_policy(keys, spend_paths)?;
    let descriptor = policy.compile_to_descriptor::<Segwitv0>(DescriptorCtx::Wsh)?;
    Ok(descriptor.to_string())
}

/// sh(wsh(sortedmulti(...))) or sh(wsh(compiled_policy))
fn build_sh_wsh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    if is_simple_multisig(spend_paths) {
        let sp = &spend_paths[0];
        let key_strs = resolve_key_strings(&sp.mfps, keys)?;
        return Ok(format!(
            "sh(wsh(sortedmulti({},{})))",
            sp.threshold,
            key_strs.join(",")
        ));
    }
    let policy = build_policy(keys, spend_paths)?;
    let descriptor = policy.compile_to_descriptor::<Segwitv0>(DescriptorCtx::ShWsh)?;
    Ok(descriptor.to_string())
}

/// sh(compiled_policy)
fn build_sh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    let policy = build_policy(keys, spend_paths)?;
    let descriptor = policy.compile_to_descriptor::<Legacy>(DescriptorCtx::Sh)?;
    Ok(descriptor.to_string())
}

/// tr(internal_key, {leaves...})
/// If a spend path is marked as key-path (singlesig, no timelocks), use it as internal key.
/// Otherwise, use NUMS unspendable key and put all paths in script tree.
///
/// Build the descriptor manually by compiling each script path separately and
/// concatenating strings, then validate with BDK parser.
fn build_tr(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    use bdk_wallet::miniscript::Descriptor;

    // Check if there's exactly one key-path marked
    let key_path_indices: Vec<usize> = spend_paths
        .iter()
        .enumerate()
        .filter(|(_, sp)| sp.is_key_path)
        .map(|(i, _)| i)
        .collect();

    if key_path_indices.len() > 1 {
        return Err(WalletError::BuilderError(
            "Only one spend path can be marked as key-path".into(),
        )
        .into());
    }

    let mut keys_uses: HashMap<String, usize> = HashMap::new();
    let internal_key_str: String;
    let script_paths: Vec<&SpendPathDef>;

    if let Some(&key_path_idx) = key_path_indices.first() {
        // Validate key-path constraints
        let key_path_sp = &spend_paths[key_path_idx];

        if key_path_sp.threshold != 1 || key_path_sp.mfps.len() != 1 || key_path_sp.rel_timelock.value != 0 || key_path_sp.abs_timelock.value != 0 {
            return Err(WalletError::BuilderError(
                "Key-path must be singlesig with no timelocks".into(),
            )
            .into());
        }

        // Use the key-path's key as internal key
        let key = resolve_key(&key_path_sp.mfps[0], keys)?;
        internal_key_str = key_with_derivation(key, &mut keys_uses);

        // All other paths go to script tree
        script_paths = spend_paths
            .iter()
            .enumerate()
            .filter(|(i, _)| *i != key_path_idx)
            .map(|(_, sp)| sp)
            .collect();
    } else {
        // No key-path: generate NUMS xpub from script path keys
        // Infer network from first key
        use crate::core::pubkey::PubKey;
        use bdk_wallet::bitcoin::{Network, NetworkKind};

        let network_kind = keys[0].xpub()?.network;
        let network = match network_kind {
            NetworkKind::Main => Network::Bitcoin,
            NetworkKind::Test => Network::Testnet,
        };

        // Generate NUMS xpub (without fingerprint/derivation path, but with wildcard)
        let nums_xpub = PubKey::generate_unspendable_xpub(keys, network)?;
        internal_key_str = format!("{}/<0;1>/*", nums_xpub);
        script_paths = spend_paths.iter().collect();
    }

    if script_paths.is_empty() {
        // Key-path only: tr(key)
        let descriptor_str = format!("tr({})", internal_key_str);

        // Validate by parsing and return with checksum
        let validated: Descriptor<DescriptorPublicKey> = descriptor_str
            .parse()
            .map_err(|e| WalletError::BuilderError(format!("Invalid descriptor: {}", e)))?;

        Ok(validated.to_string())
    } else {
        // Build each script path separately and group by priority
        let mut scripts_by_priority: BTreeMap<usize, Vec<String>> = BTreeMap::new();
        for sp in script_paths.iter() {
            let script_str = build_taproot_script_path(sp, keys, &mut keys_uses)?;
            scripts_by_priority.entry(sp.priority).or_default().push(script_str);
        }

        let scripts_layered = scripts_by_priority.into_values().collect();

        // Build descriptor string
        let tree_str = build_layered_tree(scripts_layered);
        let descriptor_str = format!("tr({},{})", internal_key_str, tree_str);

        // Validate by parsing with BDK and return with checksum
        let validated: Descriptor<DescriptorPublicKey> = descriptor_str
            .parse()
            .map_err(|e| WalletError::BuilderError(format!("Invalid descriptor: {}", e)))?;

        Ok(validated.to_string())
    }
}

/// Build a single Taproot script path as a miniscript string.
/// Each key usage gets a unique derivation index to avoid duplicate key errors.
fn build_taproot_script_path(
    sp: &SpendPathDef,
    keys: &[PubKey],
    keys_uses: &mut HashMap<String, usize>,
) -> Result<String> {
    use bdk_wallet::miniscript::{Miniscript, Tap};

    // Build policy for this single path
    let policy = build_path_policy(sp, keys, keys_uses)?;

    // Compile to miniscript using Tap context for Taproot
    let miniscript: Miniscript<DescriptorPublicKey, Tap> = policy
        .compile()
        .map_err(|e| WalletError::BuilderError(format!("Failed to compile script path: {}", e)))?;

    Ok(miniscript.to_string())
}

/// Build a balanced binary taproot tree from script strings.
/// For 2 scripts: {script1,script2}
/// For 3+ scripts: build nested binary tree
fn build_taproot_tree(scripts: &[String]) -> String {
    match scripts.len() {
        0 => panic!("Cannot build tree with no scripts"),
        1 => scripts[0].clone(),
        2 => format!("{{{},{}}}", scripts[0], scripts[1]),
        _ => {
            // Split into two halves and recursively build subtrees
            let mid = scripts.len() / 2;
            let left_tree = build_taproot_tree(&scripts[..mid]);
            let right_tree = build_taproot_tree(&scripts[mid..]);
            format!("{{{},{}}}", left_tree, right_tree)
        }
    }
}

fn build_layered_tree(layered_scripts: Vec<Vec<String>>) -> String {
    layered_scripts
        .into_iter()
        .fold(None, |acc, mut current_level| {
            if let Some(prev_subtree) = acc {
                current_level.push(prev_subtree);
            }
            Some(build_taproot_tree(&current_level))
        })
        .expect("Cannot build tree with no scripts")
}

/// Build a concrete policy from spend path definitions.
/// Each key usage gets a distinct derivation pair to avoid duplicate-key errors.
fn build_policy(
    keys: &[PubKey],
    spend_paths: &[SpendPathDef],
) -> Result<ConcretePolicy<DescriptorPublicKey>> {
    let mut keys_uses: HashMap<String, usize> = HashMap::new();

    let path_policies: Vec<ConcretePolicy<DescriptorPublicKey>> = spend_paths
        .iter()
        .map(|sp| build_path_policy(sp, keys, &mut keys_uses))
        .collect::<Result<Vec<_>>>()?;

    if path_policies.is_empty() {
        return Err(WalletError::BuilderError("No spend paths provided".into()).into());
    }

    if path_policies.len() == 1 {
        Ok(path_policies.into_iter().next().unwrap())
    } else {
        Ok(build_balanced_or_tree(path_policies))
    }
}

/// Build a balanced binary tree of OR policies
fn build_balanced_or_tree(
    mut policies: Vec<ConcretePolicy<DescriptorPublicKey>>,
) -> ConcretePolicy<DescriptorPublicKey> {
    while policies.len() > 1 {
        let mut next_level = Vec::new();
        let mut i = 0;
        while i < policies.len() {
            if i + 1 < policies.len() {
                // Pair up two policies
                let or_policy = ConcretePolicy::Or(vec![
                    (1usize, Arc::new(policies[i].clone())),
                    (1usize, Arc::new(policies[i + 1].clone())),
                ]);
                next_level.push(or_policy);
                i += 2;
            } else {
                // Odd one out, carry to next level
                next_level.push(policies[i].clone());
                i += 1;
            }
        }
        policies = next_level;
    }
    policies.into_iter().next().unwrap()
}

/// Build a policy for a single spend path
fn build_path_policy(
    sp: &SpendPathDef,
    keys: &[PubKey],
    keys_uses: &mut HashMap<String, usize>,
) -> Result<ConcretePolicy<DescriptorPublicKey>> {
    // Parse keys with unique derivation
    let key_policies: Vec<Arc<ConcretePolicy<DescriptorPublicKey>>> = sp
        .mfps
        .iter()
        .map(|mfp| {
            let key = resolve_key(mfp, keys)?;
            let dpk = parse_dpk(&key_with_derivation(key, keys_uses), mfp)?;
            Ok(Arc::new(ConcretePolicy::Key(dpk)))
        })
        .collect::<Result<Vec<_>>>()?;

    // Build key threshold
    let threshold = bdk_wallet::miniscript::Threshold::new(sp.threshold, key_policies)
        .map_err(|e| WalletError::BuilderError(format!("Invalid threshold: {}", e)))?;
    let keys_policy = ConcretePolicy::Thresh(threshold);

    // Combine with timelocks using AND
    let mut conditions: Vec<Arc<ConcretePolicy<DescriptorPublicKey>>> = vec![Arc::new(keys_policy)];

    let rel_consensus = sp.rel_timelock.to_consensus()?;
    let abs_consensus = sp.abs_timelock.to_consensus()?;

    if rel_consensus > 0 {
        let rel = bdk_wallet::miniscript::RelLockTime::from_consensus(rel_consensus)
            .map_err(|e| WalletError::BuilderError(format!("Invalid relative timelock: {}", e)))?;
        conditions.push(Arc::new(ConcretePolicy::Older(rel)));
    }

    if abs_consensus > 0 {
        let abs = bdk_wallet::miniscript::AbsLockTime::from_consensus(abs_consensus)
            .map_err(|e| WalletError::BuilderError(format!("Invalid absolute timelock: {}", e)))?;
        conditions.push(Arc::new(ConcretePolicy::After(abs)));
    }

    if conditions.len() == 1 {
        Ok(Arc::try_unwrap(conditions.into_iter().next().unwrap())
            .unwrap_or_else(|arc| (*arc).clone()))
    } else {
        Ok(ConcretePolicy::And(conditions))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::descriptor::DescriptorAnalyzer;

    fn mainnet_keys() -> Vec<PubKey> {
        vec![
            PubKey::new(
                "c449c5c5",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )
            .unwrap(),
            PubKey::new(
                "c61af686",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )
            .unwrap(),
        ]
    }

    #[test]
    fn test_build_simple_wsh_multisig() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 2,
            mfps: vec!["c449c5c5".into(), "c61af686".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
                priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh(sortedmulti(2,"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);
        assert_eq!(analyzer.public_keys()?.len(), 2);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 2);

        Ok(())
    }

    #[test]
    fn test_build_wsh_with_timelock() -> Result<()> {
        let keys = mainnet_keys();
        // Primary: 2-of-2, Recovery: 1-of-1 with timelock (same key c449c5c5 in both)
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 2);

        Ok(())
    }

    #[test]
    fn test_build_taproot() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;
        assert!(paths.len() >= 2);

        Ok(())
    }

    #[test]
    fn test_build_single_key_wpkh() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
                priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2WPKH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wpkh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WPKH);
        assert_eq!(analyzer.public_keys()?.len(), 1);

        Ok(())
    }

    #[test]
    fn test_build_sh_wsh_multisig() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 2,
            mfps: vec!["c449c5c5".into(), "c61af686".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
                priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2SH_WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("sh(wsh(sortedmulti(2,"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2SH_WSH);
        assert_eq!(analyzer.public_keys()?.len(), 2);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 2);

        Ok(())
    }

    #[test]
    fn test_build_3of5_multisig() -> Result<()> {
        let keys = vec![
            PubKey::new(
                "aabbccdd",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
            PubKey::new(
                "bbccddee",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )?,
            PubKey::new(
                "ccddeeff",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
            PubKey::new(
                "ddeeff00",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )?,
            PubKey::new(
                "eeff0011",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
        ];

        let spend_paths = vec![SpendPathDef {
            threshold: 3,
            mfps: vec![
                "aabbccdd".into(),
                "bbccddee".into(),
                "ccddeeff".into(),
                "ddeeff00".into(),
                "eeff0011".into(),
            ],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
                priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh(sortedmulti(3,"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);
        assert_eq!(analyzer.public_keys()?.len(), 5);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 3);
        assert_eq!(paths[0].mfps.len(), 5);

        Ok(())
    }

    #[test]
    fn test_build_complex_recovery_setup() -> Result<()> {
        let keys = mainnet_keys();
        // Scenario: 2-of-2 immediate, 1-of-2 after 1 day, 1-of-1 after 1 week
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144), // ~1 day
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(1008), // ~1 week
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 3);

        // Verify paths are sorted by timelock (no timelock first)
        assert_eq!(paths[0].rel_timelock, 0);
        assert!(paths[1].rel_timelock > 0);
        assert!(paths[2].rel_timelock > paths[1].rel_timelock);

        Ok(())
    }

    #[test]
    fn test_build_with_absolute_timelock() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(800000), // Block height
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 2);

        // Find the path with absolute timelock
        let timelocked_path = paths.iter().find(|p| p.abs_timelock > 0).unwrap();
        assert_eq!(timelocked_path.abs_timelock, 800000);
        assert_eq!(timelocked_path.threshold, 1);

        Ok(())
    }

    #[test]
    fn test_build_roundtrip() -> Result<()> {
        // Test: build → analyze → rebuild → should produce equivalent descriptor
        let keys = mainnet_keys();
        let original_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        // Build original descriptor
        let descriptor1 = build_descriptor(WalletType::P2WSH, &keys, &original_paths)?;

        // Analyze it
        let analyzer = DescriptorAnalyzer::analyze(&descriptor1)?;
        let analyzed_paths = analyzer.spend_paths()?;

        // Reconstruct spend path defs from analysis
        let reconstructed_paths: Vec<SpendPathDef> = analyzed_paths
            .iter()
            .map(|sp| SpendPathDef {
                threshold: sp.threshold,
                mfps: sp.mfps.clone(),
                rel_timelock: APIRelativeTimelock::from_consensus(sp.rel_timelock),
                abs_timelock: APIAbsoluteTimelock::from_consensus(sp.abs_timelock),
                is_key_path: false,
                priority: 0,
            })
            .collect();

        // Rebuild descriptor
        let descriptor2 = build_descriptor(WalletType::P2WSH, &keys, &reconstructed_paths)?;

        // Both descriptors should analyze to the same structure
        let analyzer2 = DescriptorAnalyzer::analyze(&descriptor2)?;
        let paths2 = analyzer2.spend_paths()?;

        assert_eq!(paths2.len(), analyzed_paths.len());
        for (p1, p2) in analyzed_paths.iter().zip(paths2.iter()) {
            assert_eq!(p1.threshold, p2.threshold);
            assert_eq!(p1.rel_timelock, p2.rel_timelock);
            assert_eq!(p1.abs_timelock, p2.abs_timelock);
        }

        Ok(())
    }

    #[test]
    fn test_build_sh_wpkh() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
                priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2SH_WPKH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("sh(wpkh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2SH_WPKH);
        assert_eq!(analyzer.public_keys()?.len(), 1);

        Ok(())
    }

    #[test]
    fn test_build_pkh() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
                priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2PKH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("pkh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2PKH);
        assert_eq!(analyzer.public_keys()?.len(), 1);

        Ok(())
    }

    #[test]
    fn test_build_taproot_with_keypath() -> Result<()> {
        let keys = mainnet_keys();

        // Scenario: key-path for immediate 1-of-1, script path for recovery 1-of-1 with timelock
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true, // Mark as key-path
            priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));

        // Verify the key-path key is used (not NUMS)
        assert!(descriptor.contains("c449c5c5"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;
        // Should have 2 paths: key-path (trDepth=-1) + script path (trDepth>=0)
        assert_eq!(paths.len(), 2);

        // One should be key-path (no timelocks, trDepth=-1)
        let key_path = paths
            .iter()
            .find(|p| p.rel_timelock == 0 && p.abs_timelock == 0);
        assert!(key_path.is_some());

        // One should be script path with timelock
        let script_path = paths.iter().find(|p| p.rel_timelock == 144);
        assert!(script_path.is_some());

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_only() -> Result<()> {
        let keys = mainnet_keys();

        // Taproot with only key-path, no script tree
        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: true,
                priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));

        // Should be tr(key) format without script tree
        assert!(!descriptor.contains("{{"));
        assert!(descriptor.contains("c449c5c5"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;
        // Should have only 1 path: the key-path
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 1);

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_errors() {
        let keys = mainnet_keys();

        // Error: Multiple paths marked as key-path
        let result = build_descriptor(
            WalletType::P2TR,
            &keys,
            &vec![
                SpendPathDef {
                    threshold: 1,
                    mfps: vec!["c449c5c5".into()],
                    rel_timelock: APIRelativeTimelock::from_consensus(0),
                    abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                    is_key_path: true,
                priority: 0,
                },
                SpendPathDef {
                    threshold: 1,
                    mfps: vec!["c61af686".into()],
                    rel_timelock: APIRelativeTimelock::from_consensus(0),
                    abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                    is_key_path: true, // Second key-path - error
                priority: 0,
                },
            ],
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Only one"));

        // Error: Key-path with multisig
        let result = build_descriptor(
            WalletType::P2TR,
            &keys,
            &vec![SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true, // Multisig cannot be key-path
            priority: 0,
            }],
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("singlesig"));

        // Error: Key-path with timelock
        let result = build_descriptor(
            WalletType::P2TR,
            &keys,
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true, // Timelock cannot be key-path
            priority: 0,
            }],
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("no timelocks"));
    }

    #[test]
    fn test_build_taproot_two_singlesig_no_timelocks() -> Result<()> {
        let keys = mainnet_keys();

        // Scenario: Two different singlesig paths without timelocks (both as script paths)
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false, // Script path
            priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false, // Script path
            priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        // Check how many paths we get back
        assert!(paths.len() > 0);

        Ok(())
    }

    #[test]
    fn test_build_errors() {
        let keys = mainnet_keys();

        // Error: no keys provided
        let result = build_descriptor(
            WalletType::P2WSH,
            &[],
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());

        // Error: no spend paths provided
        let result = build_descriptor(WalletType::P2WSH, &keys, &[]);
        assert!(result.is_err());

        // Error: WPKH requires exactly 1 key with threshold 1
        let result = build_descriptor(
            WalletType::P2WPKH,
            &keys,
            &vec![SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());

        // Error: Unknown wallet type
        let result = build_descriptor(
            WalletType::Unknown,
            &keys,
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());

        // Error: MFP not found in keys
        let result = build_descriptor(
            WalletType::P2WSH,
            &keys,
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["deadbeef".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_build_taproot_nums_only_script_paths() -> Result<()> {
        let keys = mainnet_keys();

        // No key-path marked → should use NUMS unspendable key
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        // Should use NUMS xpub with wildcard, without fingerprint/derivation
        assert!(descriptor.starts_with("tr(xpub") || descriptor.starts_with("tr(tpub"),
            "Should start with NUMS xpub without fingerprint");

        // Should contain wildcard after NUMS xpub
        assert!(descriptor.contains("/<0;1>/*,{"),
            "NUMS xpub should have wildcard /<0;1>/*");

        // Should NOT contain raw NUMS point
        assert!(!descriptor.contains("50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"),
            "Should not contain raw NUMS point");

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;

        // Should have 2 script paths (no key-path because NUMS is unspendable)
        assert_eq!(paths.len(), 2);

        // All paths should be script paths (tr_depth > 0, not 0 which is key-path)
        for path in &paths {
            assert!(
                path.tr_depth > 0,
                "All paths should be script paths with NUMS"
            );
        }

        // Verify we have both keys represented
        let has_key1 = paths
            .iter()
            .any(|p| p.mfps.contains(&"c449c5c5".to_string()));
        let has_key2 = paths
            .iter()
            .any(|p| p.mfps.contains(&"c61af686".to_string()));
        assert!(has_key1, "Should have path with key c449c5c5");
        assert!(has_key2, "Should have path with key c61af686");

        Ok(())
    }

    #[test]
    fn test_build_taproot_multiple_singlesig_no_timelocks() -> Result<()> {
        let keys = mainnet_keys();

        // Multiple singlesig paths without timelocks, no key-path
        // This was the problematic case - ensure all paths are preserved
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        // CRITICAL: Should have 2 paths, not lose any
        assert_eq!(paths.len(), 2, "Should preserve all input paths");

        // Both should be singlesig
        for path in &paths {
            assert_eq!(path.threshold, 1, "All paths should be singlesig");
            assert_eq!(path.mfps.len(), 1, "All paths should have 1 key");
        }

        // Verify both original keys are present
        let mfps: Vec<String> = paths.iter().flat_map(|p| p.mfps.clone()).collect();
        assert!(
            mfps.contains(&"c449c5c5".to_string()),
            "Should have key c449c5c5"
        );
        assert!(
            mfps.contains(&"c61af686".to_string()),
            "Should have key c61af686"
        );

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_plus_singlesig_no_timelocks() -> Result<()> {
        let keys = mainnet_keys();

        // THE CRITICAL TEST: key-path + singlesig script paths without timelocks
        // This was causing data loss before the fix
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true, // Explicit key-path
            priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false, // Singlesig script path, no timelock
            priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        // Should use the key-path key (c449c5c5), NOT NUMS
        assert!(
            descriptor.contains("c449c5c5"),
            "Should use explicit key-path key"
        );
        assert!(
            !descriptor
                .contains("50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"),
            "Should NOT use NUMS when key-path is specified"
        );

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        // CRITICAL: Should have 2 paths - key-path + script path
        assert_eq!(paths.len(), 2, "Should have both key-path and script path");

        // One should be key-path (tr_depth = 0 in core, becomes -1 in API)
        let key_path = paths.iter().find(|p| p.tr_depth == 0);
        assert!(key_path.is_some(), "Should have a key-path (tr_depth=0)");
        let key_path = key_path.unwrap();
        assert_eq!(key_path.threshold, 1);
        assert_eq!(key_path.mfps.len(), 1);
        assert_eq!(key_path.mfps[0], "c449c5c5", "Key-path should use c449c5c5");

        // One should be script path (tr_depth > 0)
        let script_path = paths.iter().find(|p| p.tr_depth > 0);
        assert!(
            script_path.is_some(),
            "Should have a script path (trDepth>=0)"
        );
        let script_path = script_path.unwrap();
        assert_eq!(script_path.threshold, 1);
        assert_eq!(script_path.mfps.len(), 1);
        assert_eq!(
            script_path.mfps[0], "c61af686",
            "Script path should use c61af686"
        );

        Ok(())
    }

    #[test]
    fn test_build_taproot_complex_multisig_plus_singlesig() -> Result<()> {
        let keys = mainnet_keys();

        // Complex scenario: key-path + 2-of-2 multisig + singlesig with timelock
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true,
                priority: 0,
            },
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(1008), // ~1 week
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        // Should have 3 paths
        assert_eq!(paths.len(), 3, "Should have all 3 paths");

        // Verify key-path (tr_depth = 0)
        let key_path = paths.iter().find(|p| p.tr_depth == 0);
        assert!(key_path.is_some());
        assert_eq!(key_path.unwrap().mfps[0], "c449c5c5");

        // Verify 2-of-2 multisig path
        let multisig = paths.iter().find(|p| p.threshold == 2);
        assert!(multisig.is_some());
        assert_eq!(multisig.unwrap().mfps.len(), 2);

        // Verify timelock path
        let timelock = paths.iter().find(|p| p.rel_timelock == 1008);
        assert!(timelock.is_some());
        assert_eq!(timelock.unwrap().threshold, 1);

        Ok(())
    }

    #[test]
    fn test_build_taproot_three_singlesig_no_timelocks() -> Result<()> {
        let keys = vec![
            PubKey::new(
                "aaaaaaaa",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
            PubKey::new(
                "bbbbbbbb",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )?,
            PubKey::new(
                "cccccccc",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
        ];

        // Three different singlesig paths, no timelocks, no key-path
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["aaaaaaaa".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["bbbbbbbb".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["cccccccc".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        // CRITICAL: All 3 paths should be preserved
        assert_eq!(paths.len(), 3, "All 3 singlesig paths should be preserved");

        // All should be singlesig
        for path in &paths {
            assert_eq!(path.threshold, 1);
            assert_eq!(path.mfps.len(), 1);
        }

        // Verify all 3 keys are present
        let all_mfps: Vec<String> = paths.iter().flat_map(|p| p.mfps.clone()).collect();
        assert!(all_mfps.contains(&"aaaaaaaa".to_string()));
        assert!(all_mfps.contains(&"bbbbbbbb".to_string()));
        assert!(all_mfps.contains(&"cccccccc".to_string()));

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_preserves_exact_key() -> Result<()> {
        let keys = mainnet_keys();

        // 3 paths: one marked as key-path, two singlesig script paths
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true, // THIS is the key-path
            priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        // The key-path should be c61af686, NOT c449c5c5
        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        // Should have 3 paths total
        assert_eq!(paths.len(), 3);

        // Find the key-path (tr_depth = 0)
        let key_path = paths.iter().find(|p| p.tr_depth == 0);
        assert!(key_path.is_some(), "Should have key-path");

        // CRITICAL: Key-path must be c61af686, the one we marked
        assert_eq!(
            key_path.unwrap().mfps[0],
            "c61af686",
            "Key-path should be c61af686 as explicitly marked, not arbitrarily chosen"
        );

        // Should have 2 script paths (tr_depth > 0)
        let script_paths: Vec<_> = paths.iter().filter(|p| p.tr_depth > 0).collect();
        assert_eq!(script_paths.len(), 2);

        Ok(())
    }
}
