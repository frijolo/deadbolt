use std::collections::{BTreeMap, HashMap};

use anyhow::Result;
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::Descriptor;

use crate::core::error::WalletError;
use crate::core::pubkey::PubKey;

use super::multisig::build_path_policy;
use super::{key_with_derivation, resolve_key, SpendPathDef};

/// tr(internal_key, {leaves...})
/// If a spend path is marked as key-path (singlesig, no timelocks), use it as internal key.
/// Otherwise, use NUMS unspendable key and put all paths in script tree.
///
/// Build the descriptor manually by compiling each script path separately and
/// concatenating strings, then validate with BDK parser.
pub fn build_tr(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
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

        if key_path_sp.threshold != 1
            || key_path_sp.mfps.len() != 1
            || key_path_sp.rel_timelock.value != 0
            || key_path_sp.abs_timelock.value != 0
        {
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
            scripts_by_priority
                .entry(sp.priority)
                .or_default()
                .push(script_str);
        }

        let scripts_layered = scripts_by_priority.into_values().collect();

        // Build descriptor string
        let tree_str = build_layered_tree(scripts_layered)?;
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
pub fn build_taproot_script_path(
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

fn join_tree(l: String, r: String) -> String {
    format!("{{{},{}}}", l, r)
}

/// Build a balanced binary taproot tree from script strings.
/// For 2 scripts: {script1,script2}
/// For 3+ scripts: build nested binary tree
pub fn build_taproot_tree(scripts: &[String]) -> Result<String> {
    match scripts.len() {
        0 => Err(WalletError::BuilderError("Cannot build tree with no scripts".into()).into()),
        1 => Ok(scripts[0].clone()),
        2 => Ok(join_tree(scripts[0].clone(), scripts[1].clone())),
        _ => {
            // Split into two halves and recursively build subtrees
            let mid = scripts.len() / 2;
            let left_tree = build_taproot_tree(&scripts[..mid])?;
            let right_tree = build_taproot_tree(&scripts[mid..])?;
            Ok(join_tree(left_tree, right_tree))
        }
    }
}

pub fn build_layered_tree(layered_scripts: Vec<Vec<String>>) -> Result<String> {
    layered_scripts
        .into_iter()
        .try_fold(
            None::<String>,
            |acc, mut current_level| -> Result<Option<String>> {
                if let Some(prev_subtree) = acc {
                    current_level.push(prev_subtree);
                }
                Ok(Some(build_taproot_tree(&current_level)?))
            },
        )?
        .ok_or_else(|| WalletError::BuilderError("Cannot build tree with no scripts".into()).into())
}
