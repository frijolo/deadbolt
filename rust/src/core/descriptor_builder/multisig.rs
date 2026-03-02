use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::policy::concrete::{DescriptorCtx, Policy as ConcretePolicy};
use bdk_wallet::miniscript::{Legacy, Segwitv0};

use crate::core::error::WalletError;
use crate::core::pubkey::PubKey;

use super::{key_with_derivation, parse_dpk, resolve_key, resolve_key_strings, SpendPathDef};

/// Check if spend paths represent a simple multisig (1 path, no timelocks)
pub fn is_simple_multisig(spend_paths: &[SpendPathDef]) -> bool {
    spend_paths.len() == 1
        && spend_paths[0].rel_timelock.value == 0
        && spend_paths[0].abs_timelock.value == 0
        && spend_paths[0].mfps.len() > 1
}

/// wsh(sortedmulti(...)) or wsh(compiled_policy)
pub fn build_wsh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
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
pub fn build_sh_wsh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
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
pub fn build_sh(keys: &[PubKey], spend_paths: &[SpendPathDef]) -> Result<String> {
    let policy = build_policy(keys, spend_paths)?;
    let descriptor = policy.compile_to_descriptor::<Legacy>(DescriptorCtx::Sh)?;
    Ok(descriptor.to_string())
}

/// Build a concrete policy from spend path definitions.
/// Each key usage gets a distinct derivation pair to avoid duplicate-key errors.
pub fn build_policy(
    keys: &[PubKey],
    spend_paths: &[SpendPathDef],
) -> Result<ConcretePolicy<DescriptorPublicKey>> {
    let mut keys_uses: HashMap<String, usize> = HashMap::new();

    let mut path_policies: Vec<ConcretePolicy<DescriptorPublicKey>> = spend_paths
        .iter()
        .map(|sp| build_path_policy(sp, keys, &mut keys_uses))
        .collect::<Result<Vec<_>>>()?;

    if path_policies.is_empty() {
        return Err(WalletError::BuilderError("No spend paths provided".into()).into());
    }

    if path_policies.len() == 1 {
        Ok(path_policies.remove(0))
    } else {
        Ok(build_balanced_or_tree(path_policies))
    }
}

/// Build a balanced binary tree of OR policies
pub fn build_balanced_or_tree(
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
    policies.remove(0)
}

/// Build a policy for a single spend path
pub fn build_path_policy(
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
        Ok(Arc::try_unwrap(conditions.remove(0)).unwrap_or_else(|arc| (*arc).clone()))
    } else {
        Ok(ConcretePolicy::And(conditions))
    }
}
