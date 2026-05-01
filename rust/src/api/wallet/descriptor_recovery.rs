use std::str::FromStr;

use anyhow::Result;
use bdk_electrum::electrum_client::{Client, ElectrumApi};
use bdk_wallet::bitcoin::bip32::Xpub;
use bdk_wallet::bitcoin::secp256k1::Secp256k1;

use crate::api::model::APINetwork;
use crate::core::key_protection::parse_xpub_credential;
use crate::core::wallet_info::{create_wallet_db, WalletProtectionRequest};

use super::descriptor_backup::{
    anchor_p2tr_address, decrypt_onchain_backup, derive_anchor_key, extract_descriptor_from_reveal,
    participant_triples,
};

// ---------------------------------------------------------------------------
// FRB-exposed return types
// ---------------------------------------------------------------------------

/// A single on-chain descriptor backup found for a given xpub.
pub struct OnchainBackupResponse {
    pub commit_txid: String,
    pub reveal_txid: Option<String>,
    /// Raw on-chain backup payload bytes (use with `import_onchain_backup`).
    pub bytes: Vec<u8>,
    pub wallet_name: Option<String>,
    pub network: Option<String>,
    pub created_at: Option<i64>,
    pub first_address: Option<String>,
    pub wallet_type: Option<crate::api::model::APIWalletType>,
    /// The decrypted descriptor string (present when decryption succeeded).
    pub descriptor: Option<String>,
    pub descriptor_sig_verification: Option<super::nostr_backup::APIDescriptorSigVerification>,
    /// How many anchor addresses derived from the descriptor have TX_COMMIT in their history.
    pub anchors_reachable: u32,
    /// Total number of anchor addresses derived from the descriptor.
    pub anchors_total: u32,
}

/// Return type of `import_onchain_backup`.
pub struct OnchainImportResult {
    pub wallet: crate::api::model::APIWalletInfo,
}

// ---------------------------------------------------------------------------
// Helpers: anchor address derivation
// ---------------------------------------------------------------------------

fn parse_bare_xpub(credential: &str) -> Result<Xpub> {
    let (_, bare) = parse_xpub_credential(credential);
    Xpub::from_str(bare).map_err(|e| anyhow::anyhow!("Invalid xpub: {e}"))
}

fn anchor_spk_for_xpub(
    secp: &Secp256k1<bdk_wallet::bitcoin::secp256k1::All>,
    xpub: &Xpub,
    network: bdk_wallet::bitcoin::Network,
) -> bdk_wallet::bitcoin::ScriptBuf {
    let key = derive_anchor_key(secp, xpub);
    anchor_p2tr_address(secp, &key, network).script_pubkey()
}

// ---------------------------------------------------------------------------
// TX_COMMIT collection
// ---------------------------------------------------------------------------

fn collect_commits(
    client: &Client,
    anchor_spk: &bdk_wallet::bitcoin::ScriptBuf,
    txids: &[bdk_wallet::bitcoin::Txid],
) -> Vec<(bdk_wallet::bitcoin::Txid, bdk_wallet::bitcoin::Transaction)> {
    let mut commits = Vec::new();
    for &txid in txids {
        match client.transaction_get(&txid) {
            Ok(tx) if tx.output.iter().any(|o| o.script_pubkey == *anchor_spk) => {
                commits.push((txid, tx));
            }
            _ => {}
        }
    }
    commits
}

// ---------------------------------------------------------------------------
// Metadata helpers
// ---------------------------------------------------------------------------

struct DescriptorMeta {
    first_address: Option<String>,
    wallet_type: Option<crate::api::model::APIWalletType>,
    network_str: Option<String>,
}

fn descriptor_meta(descriptor: &str) -> DescriptorMeta {
    let Ok(analyzer) = crate::core::descriptor::DescriptorAnalyzer::analyze(descriptor) else {
        return DescriptorMeta {
            first_address: None,
            wallet_type: None,
            network_str: None,
        };
    };
    let network = analyzer.network();
    let network_str = Some(APINetwork::from(network).as_str().to_string());
    let first_address =
        super::discovery::first_address_from_descriptor(descriptor.to_string(), network.into())
            .ok();
    let wallet_type = Some(super::discovery::wallet_type_from_descriptor(descriptor));
    DescriptorMeta {
        first_address,
        wallet_type,
        network_str,
    }
}

// ---------------------------------------------------------------------------
// Anchor health & metadata helpers
// ---------------------------------------------------------------------------

fn compute_anchor_health(
    client: &Client,
    descriptor: &str,
    commit_txid: bdk_wallet::bitcoin::Txid,
    network: bdk_wallet::bitcoin::Network,
) -> (u32, u32) {
    let secp = Secp256k1::new();
    let triples = participant_triples(descriptor);
    let total = triples.len() as u32;

    let mut reachable = 0u32;
    for (_, xpub_str, _) in &triples {
        if let Ok(xpub) = Xpub::from_str(xpub_str) {
            let anchor_key = derive_anchor_key(&secp, &xpub);
            let anchor_addr = anchor_p2tr_address(&secp, &anchor_key, network);
            if let Ok(history) = client.script_get_history(anchor_addr.script_pubkey().as_script())
            {
                if history.iter().any(|h| h.tx_hash == commit_txid) {
                    reachable += 1;
                }
            }
        }
    }

    (reachable, total)
}

fn get_block_timestamp(client: &Client, block_height: usize) -> Option<i64> {
    let header = client.block_header(block_height).ok()?;
    Some(header.time as i64)
}

// ---------------------------------------------------------------------------
// Public FRB functions
// ---------------------------------------------------------------------------

/// Scan on-chain for all descriptor backups published by the given xpub.
pub async fn fetch_onchain_backup(
    xpub_credential: String,
    electrum_url: String,
    network_hint: String,
) -> Result<Vec<OnchainBackupResponse>> {
    let network: bdk_wallet::bitcoin::Network = APINetwork::try_from(network_hint.as_str())?.into();
    let xpub = parse_bare_xpub(&xpub_credential)?;

    let secp = Secp256k1::new();
    let anchor_spk = anchor_spk_for_xpub(&secp, &xpub, network);

    let client = super::create_raw_electrum_client(&electrum_url)?;

    let anchor_txids: Vec<bdk_wallet::bitcoin::Txid> = client
        .script_get_history(anchor_spk.as_script())
        .map_err(|e| anyhow::anyhow!("anchor history lookup: {e}"))?
        .into_iter()
        .map(|h| h.tx_hash)
        .collect();

    if anchor_txids.is_empty() {
        return Ok(vec![]);
    }

    let commits = collect_commits(&client, &anchor_spk, &anchor_txids);
    let mut results: Vec<OnchainBackupResponse> = Vec::new();

    for (commit_txid, commit_tx) in &commits {
        // The vault output position is not fixed — exclude the known anchor and
        // try each remaining output to locate TX_REVEAL.
        let Some((reveal_txid, reveal_tx, reveal_height)) =
            super::descriptor_backup::find_reveal_tx_for_commit(
                &client,
                commit_tx,
                *commit_txid,
                std::slice::from_ref(&anchor_spk),
            )
        else {
            continue;
        };

        let (descriptor, raw_bytes, inner_json) =
            match extract_descriptor_from_reveal(&reveal_tx, &xpub_credential) {
                Ok(triple) => triple,
                Err(_) => continue,
            };

        let meta = descriptor_meta(&descriptor);

        let (anchors_reachable, anchors_total) =
            compute_anchor_health(&client, &descriptor, *commit_txid, network);
        let created_at = (reveal_height > 0)
            .then(|| get_block_timestamp(&client, reveal_height))
            .flatten();

        let wallet_name = inner_json["wallet_name"].as_str().map(String::from);

        results.push(OnchainBackupResponse {
            commit_txid: commit_txid.to_string(),
            reveal_txid: Some(reveal_txid.to_string()),
            bytes: raw_bytes,
            wallet_name,
            network: meta.network_str,
            created_at,
            first_address: meta.first_address,
            wallet_type: meta.wallet_type,
            descriptor: Some(descriptor),
            descriptor_sig_verification: None,
            anchors_reachable,
            anchors_total,
        });
    }

    Ok(results)
}

/// Import an on-chain backup payload (from `fetch_onchain_backup.bytes`) as a new wallet.
pub async fn import_onchain_backup(
    backup_bytes: Vec<u8>,
    xpub_credential: String,
    device_key_hex: String,
    wallets_dir: String,
    network_hint: String,
) -> Result<OnchainImportResult> {
    let (inner_bytes, descriptor) = decrypt_onchain_backup(&backup_bytes, &xpub_credential)?;
    let wallet_name = serde_json::from_slice::<serde_json::Value>(&inner_bytes)
        .ok()
        .and_then(|inner| inner["wallet_name"].as_str().map(String::from));

    // Prefer the caller's network hint (from the discovery phase) and fall back
    // to detecting from the descriptor itself.
    let network_str = APINetwork::try_from(network_hint.as_str())
        .map(|n| n.as_str().to_string())
        .unwrap_or_else(|_| {
            descriptor_meta(&descriptor)
                .network_str
                .unwrap_or_else(|| "bitcoin".to_string())
        });

    let name = wallet_name.as_deref().unwrap_or("Restored Wallet");
    let (path, row) = create_wallet_db(
        &wallets_dir,
        name,
        &descriptor,
        &network_str,
        &device_key_hex,
        WalletProtectionRequest::DeviceKey,
    )?;

    let wallet = super::row_to_api_info(path, row)?;
    Ok(OnchainImportResult { wallet })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
#[path = "descriptor_recovery_tests.rs"]
mod tests;
