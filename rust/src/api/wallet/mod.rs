use std::sync::Mutex;

use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIAddress, APIAddressDetails, APIBalance, APICoinControl, APICpfpInfo, APIFiatPrice,
    APIHotKeyInfo, APIImportPsbtResult, APIKeychain, APINetwork, APIPolicyPath, APIProtectionType,
    APIPsbtAnalysis, APIPsbtInfo, APIPsbtSignerStatus, APIRbfInfo, APIRecipient, APIRelatedAddress,
    APIRelatedTx, APIRelatedUtxo, APISecurityLevel, APITransaction, APITransactionPage,
    APITxDetails, APITxMissingFiat, APIUtxo, APIUtxoDetails, APIWalletInfo, APIWalletProtection,
    APIXpubSlot,
};
use crate::core::key_protection::{
    decrypt_bytes, encrypt_bytes, generate_data_key, ProtectionMeta,
};
use crate::core::project_seeds::{
    delete_project_seed_entry, insert_project_seed_entry, list_project_seed_entries,
    open_project_seeds_db, reveal_project_seed_value,
};
use crate::core::wallet::CoreWallet;
use crate::core::wallet_info::{
    add_xpub_slot_to_wallet, build_protection_meta, create_wallet_db, generate_uuid_v4,
    get_wallet_info_from_file, list_wallets_in_dir, refresh_user_password_meta_cache,
    remove_xpub_slot_from_wallet, rename_wallet_in_file, resolve_wallet_key, wallet_needs_password,
    wallet_needs_xpub, wallet_network_hint, WalletProtectionRequest,
};
use crate::core::wallet_meta::{delete_meta, read_meta, write_meta};
use crate::core::wallet_persistence::{
    address_has_explicit_label, clear_fiat_prices as clear_fiat_prices_db, coin_has_explicit_label,
    delete_psbt_row, delete_seed_entry, ensure_unsigned_txs_table, get_address_label_with_flag,
    get_all_address_labels_with_flag, get_all_coin_labels_with_flag, get_all_key_labels,
    get_all_path_labels, get_all_tx_labels_with_flag, get_coin_label_with_flag,
    get_fiat_prices as get_fiat_prices_db, get_psbt_row, get_psbt_row_by_txid,
    get_tx_label_with_flag, insert_psbt, insert_seed_entry, list_psbt_rows, list_seed_entries,
    open_encrypted_connection, read_wallet_info, set_address_label as db_set_address_label,
    set_coin_label as db_set_coin_label, set_key_label as db_set_key_label,
    set_path_label as db_set_path_label, set_tx_label as db_set_tx_label,
    store_fiat_price as store_fiat_price_db, touch_last_synced, tx_has_explicit_label,
    update_psbt_data, update_psbt_label, PsbtRow, WalletInfoRow,
};

mod labels;
mod ops;
mod psbt;
mod queries;

/// A key label entry returned from [APIWallet::get_key_labels].
pub struct APIKeyLabel {
    pub mfp: String,
    pub label: String,
}

/// A spend-path label entry returned from [APIWallet::get_path_labels].
pub struct APIPathLabel {
    pub rust_id: u32,
    pub label: String,
}

const STOP_GAP: usize = 20;
const BATCH_SIZE: usize = 5;

// ---------------------------------------------------------------------------
// Electrum client factory shared by ops, psbt, queries
// ---------------------------------------------------------------------------

use bdk_electrum::{
    electrum_client::{Client, ConfigBuilder, Socks5Config},
    BdkElectrumClient,
};

/// Create a BdkElectrumClient, routing through the local Tor SOCKS5 proxy when
/// Tor is enabled. Fails if Tor is enabled but bootstrap has not yet completed.
fn create_electrum_client(url: &str) -> Result<BdkElectrumClient<Client>> {
    Ok(BdkElectrumClient::new(create_raw_electrum_client(url)?))
}

/// Create a raw Client for callers that need ElectrumApi directly (queries.rs, wif_sweep).
pub(crate) fn create_raw_electrum_client(url: &str) -> Result<Client> {
    if crate::core::tor_manager::is_tor_enabled() {
        let socks_addr = crate::core::tor_manager::tor_socks_addr()
            .ok_or_else(|| anyhow::anyhow!("Tor is enabled but not connected yet"))?;
        let config = ConfigBuilder::new()
            .socks5(Some(Socks5Config::new(&socks_addr)))
            .build();
        Client::from_config(url, config).map_err(|_| {
            // The relay stores the real Tor error before closing the socket,
            // so it is always available here when we catch the electrum error.
            let tor_msg = crate::core::tor_manager::take_tor_connection_error();
            match tor_msg {
                Some(msg) => anyhow::anyhow!("Tor connection failed: {msg}"),
                None => {
                    anyhow::anyhow!("Tor connection failed (check server address and Tor status)")
                }
            }
        })
    } else {
        Client::new(url).map_err(|e| anyhow::anyhow!("Electrum client error: {e}"))
    }
}

/// Resolve a label+flag pair into (explicit_label, effective_label, is_auto).
///
/// - `label`: non-empty and non-auto only (for editing).
/// - `effective_label`: non-empty regardless of auto flag (for display).
/// - `is_auto`: whether the label was auto-propagated.
fn resolve_label(data: Option<(String, bool)>) -> (Option<String>, Option<String>, bool) {
    match data {
        None => (None, None, false),
        Some((l, is_auto)) => {
            if l.is_empty() {
                (None, None, is_auto)
            } else if is_auto {
                (None, Some(l), is_auto)
            } else {
                let effective = l.clone();
                (Some(l), Some(effective), is_auto)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// PSBT helpers
// ---------------------------------------------------------------------------

/// Apply a PSBT's label to its transaction (if not already explicitly labelled).
/// Used when a PSBT is deleted after broadcast (local or external).
fn apply_psbt_label_to_tx(conn: &rusqlite::Connection, row: &PsbtRow) {
    if let Some(label) = &row.label {
        if !label.is_empty() && !tx_has_explicit_label(conn, &row.txid).unwrap_or(false) {
            let _ = db_set_tx_label(conn, &row.txid, label, false, None);
        }
    }
}

// ---------------------------------------------------------------------------
// Base64 helpers (PSBT serialization)
// ---------------------------------------------------------------------------

fn psbt_to_base64(psbt: &bdk_wallet::bitcoin::psbt::Psbt) -> String {
    use base64::{engine::general_purpose, Engine as _};
    general_purpose::STANDARD.encode(psbt.serialize())
}

fn psbt_from_base64(s: &str) -> Result<bdk_wallet::bitcoin::psbt::Psbt> {
    use base64::{engine::general_purpose, Engine as _};
    use bdk_wallet::bitcoin::psbt::Psbt;
    let bytes = general_purpose::STANDARD
        .decode(s)
        .map_err(|e| anyhow::anyhow!("base64 decode: {}", e))?;
    Psbt::deserialize(&bytes).map_err(|e| anyhow::anyhow!("PSBT deserialize: {}", e))
}

/// Extract a mfp→xpub map from a descriptor string.
/// Matches `[deadbeef/44'/0'/0']xpub6C...` style key expressions.
fn extract_xpub_mfp_map(descriptor: &str) -> std::collections::HashMap<String, String> {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        regex::Regex::new(r"\[([0-9a-fA-F]{8})[^\]]*\]([A-Za-z]{1,4}pub[A-Za-z0-9]+)")
            .expect("hard-coded xpub regex is valid")
    });
    let mut map = std::collections::HashMap::new();
    for cap in re.captures_iter(descriptor) {
        map.insert(cap[1].to_lowercase(), cap[2].to_string());
    }
    map
}

/// Extract a mfp→derivation map from a descriptor string.
/// Matches `[deadbeef/48h/0h/0h/2h]xpub...` and returns the path suffix after the MFP.
fn extract_xpub_derivation_map(descriptor: &str) -> std::collections::HashMap<String, String> {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        regex::Regex::new(r"\[([0-9a-fA-F]{8})/([^\]]+)\]")
            .expect("hard-coded derivation regex is valid")
    });
    let mut map = std::collections::HashMap::new();
    for cap in re.captures_iter(descriptor) {
        map.entry(cap[1].to_lowercase())
            .or_insert_with(|| cap[2].to_string());
    }
    map
}

/// Extract `(mfp, xpub, derivation_hint)` triples from a descriptor for XpubKey protection.
/// Returns an error if the descriptor contains no xpubs.
fn xpub_slots_from_descriptor(descriptor: &str) -> Result<Vec<(String, String, String)>> {
    let xpub_map = extract_xpub_mfp_map(descriptor);
    let deriv_map = extract_xpub_derivation_map(descriptor);
    if xpub_map.is_empty() {
        return Err(anyhow::anyhow!(
            "No xpubs found in descriptor for XpubKey protection"
        ));
    }
    Ok(xpub_map
        .into_iter()
        .map(|(mfp, xpub)| {
            let derivation = deriv_map.get(&mfp).cloned().unwrap_or_default();
            (mfp, xpub, derivation)
        })
        .collect())
}

/// Compute the maximum confirmation height of the UTXOs spent by `psbt`.
/// Returns `None` if no input UTXO is confirmed.
fn psbt_max_utxo_conf_height(
    wallet: &bdk_wallet::Wallet,
    psbt: &bdk_wallet::bitcoin::psbt::Psbt,
) -> Option<i64> {
    psbt.unsigned_tx
        .input
        .iter()
        .filter_map(|txin| wallet.get_utxo(txin.previous_output))
        .filter_map(|utxo| {
            if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } = utxo.chain_position
            {
                Some(anchor.block_id.height as i64)
            } else {
                None
            }
        })
        .reduce(i64::max)
}

/// True when `recipient` is one of this wallet's own addresses (self-transfer).
fn is_psbt_self_transfer(wallet: &bdk_wallet::Wallet, recipient: &str) -> bool {
    use bdk_wallet::bitcoin::Address;
    use std::str::FromStr;
    let Ok(addr) = Address::from_str(recipient) else {
        return false;
    };
    let Ok(addr) = addr.require_network(wallet.network()) else {
        return false;
    };
    wallet
        .spk_index()
        .index_of_spk(addr.script_pubkey())
        .is_some()
}

/// Compute the effective display label for a PSBT.
/// Own label takes priority; falls back to the recipient address label.
fn psbt_effective_label(
    own_label: &Option<String>,
    recipient: &str,
    address_labels: &std::collections::HashMap<String, (String, bool)>,
) -> (Option<String>, bool) {
    match own_label.as_deref().filter(|l| !l.is_empty()) {
        Some(lbl) => (Some(lbl.to_string()), false),
        None => {
            let (_, el, ia) = resolve_label(address_labels.get(recipient).cloned());
            (el, ia)
        }
    }
}

/// Build the set of outpoints that are still "live": either unspent or being
/// spent by an unconfirmed (mempool) wallet transaction.  Any PSBT input
/// absent from this set has been confirmed-spent by another transaction and
/// can no longer be broadcast.
fn build_valid_outpoints(
    wallet: &bdk_wallet::Wallet,
) -> std::collections::HashSet<bdk_wallet::bitcoin::OutPoint> {
    use bdk_wallet::chain::ChainPosition;
    let mut valid = std::collections::HashSet::new();
    for utxo in wallet.list_unspent() {
        valid.insert(utxo.outpoint);
    }
    for tx in wallet.transactions() {
        if matches!(tx.chain_position, ChainPosition::Unconfirmed { .. }) {
            for txin in &tx.tx_node.tx.input {
                if !txin.previous_output.is_null() {
                    valid.insert(txin.previous_output);
                }
            }
        }
    }
    valid
}

fn row_to_api_psbt(
    row: PsbtRow,
    wallet: &bdk_wallet::Wallet,
    address_labels: &std::collections::HashMap<String, (String, bool)>,
    valid_outpoints: &std::collections::HashSet<bdk_wallet::bitcoin::OutPoint>,
) -> APIPsbtInfo {
    let parsed_psbt = psbt_from_base64(&row.psbt).ok();
    let utxo_max_conf_height = parsed_psbt
        .as_ref()
        .and_then(|psbt| psbt_max_utxo_conf_height(wallet, psbt));
    let has_spent_inputs = parsed_psbt
        .map(|psbt| {
            psbt.unsigned_tx.input.iter().any(|txin| {
                !txin.previous_output.is_null() && !valid_outpoints.contains(&txin.previous_output)
            })
        })
        .unwrap_or(false);
    let (effective_label, is_auto) =
        psbt_effective_label(&row.label, &row.recipient, address_labels);
    let is_self_transfer = is_psbt_self_transfer(wallet, &row.recipient);
    // Deserialize recipients from JSON; fall back to single-recipient for old rows.
    let recipients: Vec<crate::api::model::APIRecipient> = row
        .recipients_json
        .as_deref()
        .and_then(|json| serde_json::from_str(json).ok())
        .unwrap_or_else(|| {
            vec![crate::api::model::APIRecipient {
                address: row.recipient.clone(),
                amount_sat: row.amount_sat,
            }]
        });
    APIPsbtInfo {
        id: row.id,
        psbt_base64: row.psbt,
        txid: row.txid,
        label: row.label,
        effective_label,
        is_auto,
        is_self_transfer,
        created_at: row.created_at,
        recipient: row.recipient,
        amount_sat: row.amount_sat,
        recipients,
        fee_sat: row.fee_sat,
        spend_path_id: row.spend_path_id,
        threshold: row.threshold,
        mfps: row.mfps,
        utxo_max_conf_height,
        has_spent_inputs,
    }
}

/// Load addr_labels and valid_outpoints from `conn`/`wallet`, then convert a single `PsbtRow`.
/// Use this for one-shot conversions; for bulk `list_psbts`, load the context once manually.
pub(super) fn row_to_api_psbt_loaded(
    row: PsbtRow,
    conn: &rusqlite::Connection,
    wallet: &bdk_wallet::Wallet,
) -> APIPsbtInfo {
    let addr_labels = get_all_address_labels_with_flag(conn).unwrap_or_default();
    let valid_outpoints = build_valid_outpoints(wallet);
    row_to_api_psbt(row, wallet, &addr_labels, &valid_outpoints)
}

fn row_to_api_info(wallet_path: String, row: WalletInfoRow) -> Result<APIWalletInfo> {
    let network = APINetwork::try_from(row.network.as_str())?;
    let protection = protection_for_path(&wallet_path);
    Ok(APIWalletInfo {
        wallet_path,
        name: row.name,
        descriptor: row.descriptor,
        network,
        created_at: row.created_at,
        last_synced_at: row.last_synced_at,
        protection,
    })
}

fn protection_for_path(wallet_path: &str) -> APIWalletProtection {
    match read_meta(wallet_path) {
        Ok(ProtectionMeta::UserPassword { m_cost, .. }) => APIWalletProtection {
            protection_type: APIProtectionType::UserPassword,
            needs_password: true,
            security_level: APISecurityLevel::from_m_cost(m_cost),
        },
        Ok(ProtectionMeta::XpubKey { ref slots, .. }) => {
            let m_cost = slots
                .first()
                .map(|s| s.m_cost)
                .unwrap_or(APISecurityLevel::Standard.m_cost());
            APIWalletProtection {
                protection_type: APIProtectionType::XpubKey,
                needs_password: true,
                security_level: APISecurityLevel::from_m_cost(m_cost),
            }
        }
        _ => APIWalletProtection {
            protection_type: APIProtectionType::DeviceKey,
            needs_password: false,
            security_level: APISecurityLevel::Standard,
        },
    }
}

// ---------------------------------------------------------------------------
// Label propagation helpers
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum EntityType {
    Tx,
    Address,
    Coin,
}

/// Build a canonical source_entity identifier for the given entity type and id.
/// Format: `"tx:{txid}"`, `"addr:{address}"`, or `"coin:{txid}:{vout}"`.
fn source_entity_id(source_type: EntityType, source_id: &str) -> String {
    match source_type {
        EntityType::Tx => format!("tx:{}", source_id),
        EntityType::Address => format!("addr:{}", source_id),
        EntityType::Coin => format!("coin:{}", source_id),
    }
}

/// Set a coin auto-label only if the coin has no explicit label.
fn set_coin_if_none(
    conn: &rusqlite::Connection,
    outpoint: &str,
    label: &str,
    source: &str,
) -> Result<()> {
    if !coin_has_explicit_label(conn, outpoint)? {
        db_set_coin_label(conn, outpoint, label, true, Some(source))?;
    }
    Ok(())
}

/// Set an address auto-label only if the address has no explicit label.
fn set_address_if_none(
    conn: &rusqlite::Connection,
    address: &str,
    label: &str,
    source: &str,
) -> Result<()> {
    if !address_has_explicit_label(conn, address)? {
        db_set_address_label(conn, address, label, true, Some(source))?;
    }
    Ok(())
}

/// Set a tx auto-label only if the tx has no explicit label.
fn set_tx_if_none(
    conn: &rusqlite::Connection,
    txid: &str,
    label: &str,
    source: &str,
) -> Result<()> {
    if !tx_has_explicit_label(conn, txid)? {
        db_set_tx_label(conn, txid, label, true, Some(source))?;
    }
    Ok(())
}

/// Delete all auto-labels that were propagated from `source` across all three label tables.
fn clear_source_labels(conn: &rusqlite::Connection, source: &str) -> Result<()> {
    for table in ["tx_labels", "address_labels", "coin_labels"] {
        conn.execute(
            &format!("DELETE FROM {table} WHERE source_entity = ?1"),
            rusqlite::params![source],
        )?;
    }
    Ok(())
}

/// Propagate a label to related entities as auto-generated labels.
/// Clears any stale auto-labels previously propagated by this source first,
/// then writes new ones — skipping targets that already have an explicit label.
fn propagate_label(
    conn: &rusqlite::Connection,
    wallet: &bdk_wallet::Wallet,
    source_type: EntityType,
    source_id: &str,
    label: &str,
) -> Result<()> {
    let source = source_entity_id(source_type, source_id);

    // Remove stale auto-labels from this source before re-propagating.
    clear_source_labels(conn, &source)?;

    match source_type {
        EntityType::Tx => {
            let txid = source_id;
            let spk_index = wallet.spk_index();
            // Find the tx and propagate to all wallet-owned inputs and outputs.
            if let Some(canonical_tx) = wallet
                .transactions()
                .find(|t| t.tx_node.txid.to_string() == txid)
            {
                let tx_ref = &canonical_tx.tx_node.tx;
                // Outputs owned by our wallet.
                for (vout_idx, output) in tx_ref.output.iter().enumerate() {
                    let Some((keychain, derivation_index)) =
                        spk_index.index_of_spk(output.script_pubkey.clone())
                    else {
                        continue;
                    };
                    let address = wallet
                        .peek_address(*keychain, *derivation_index)
                        .address
                        .to_string();
                    let outpoint_str = format!("{}:{}", txid, vout_idx);
                    set_coin_if_none(conn, &outpoint_str, label, &source)?;
                    set_address_if_none(conn, &address, label, &source)?;
                }
                // Inputs from our wallet (spent coins).
                for input in tx_ref.input.iter() {
                    let prev_out = input.previous_output;
                    let Some(prev_txout) = wallet.tx_graph().get_txout(prev_out) else {
                        continue;
                    };
                    let Some((keychain, derivation_index)) =
                        spk_index.index_of_spk(prev_txout.script_pubkey.clone())
                    else {
                        continue;
                    };
                    let address = wallet
                        .peek_address(*keychain, *derivation_index)
                        .address
                        .to_string();
                    let outpoint_str = format!("{}:{}", prev_out.txid, prev_out.vout);
                    set_coin_if_none(conn, &outpoint_str, label, &source)?;
                    set_address_if_none(conn, &address, label, &source)?;
                }
            }
        }
        EntityType::Address => {
            use bdk_wallet::KeychainKind;
            let address = source_id;
            let spk_index = wallet.spk_index();
            // Find keychain + index for this address.
            let maybe_info = [KeychainKind::External, KeychainKind::Internal]
                .iter()
                .find_map(|&k| {
                    spk_index
                        .revealed_keychain_spks(k)
                        .find(|(i, _)| wallet.peek_address(k, *i).address.to_string() == address)
                        .map(|(i, _)| (k, i))
                });
            if let Some((keychain, idx)) = maybe_info {
                // Collect all outpoints at this address (creating txs + coins).
                let mut our_outpoints: std::collections::HashSet<(String, u32)> =
                    std::collections::HashSet::new();
                for canonical_tx in wallet.transactions() {
                    for (vout_idx, output) in canonical_tx.tx_node.tx.output.iter().enumerate() {
                        if let Some((k, i)) = spk_index.index_of_spk(output.script_pubkey.clone()) {
                            if *k == keychain && *i == idx {
                                let txid = canonical_tx.tx_node.txid.to_string();
                                our_outpoints.insert((txid.clone(), vout_idx as u32));
                                // Label the coin.
                                let outpoint_str = format!("{}:{}", txid, vout_idx);
                                set_coin_if_none(conn, &outpoint_str, label, &source)?;
                                // Label the creating tx.
                                set_tx_if_none(conn, &txid, label, &source)?;
                            }
                        }
                    }
                }
                // Also label any tx that spends our outpoints.
                for canonical_tx in wallet.transactions() {
                    for input in canonical_tx.tx_node.tx.input.iter() {
                        let prev = (
                            input.previous_output.txid.to_string(),
                            input.previous_output.vout,
                        );
                        if our_outpoints.contains(&prev) {
                            let spending_txid = canonical_tx.tx_node.txid.to_string();
                            set_tx_if_none(conn, &spending_txid, label, &source)?;
                        }
                    }
                }
            }
        }
        EntityType::Coin => {
            let outpoint = source_id;
            let parts: Vec<&str> = outpoint.split(':').collect();
            if parts.len() == 2 {
                let txid = parts[0];
                // Label the creating tx.
                set_tx_if_none(conn, txid, label, &source)?;
                if let Ok(vout) = parts[1].parse::<u32>() {
                    let spk_index = wallet.spk_index();
                    // Find the address via tx_graph (works for both spent and unspent).
                    use bdk_wallet::bitcoin::OutPoint;
                    use std::str::FromStr;
                    if let Ok(txid_bitcoin) = bdk_wallet::bitcoin::Txid::from_str(txid) {
                        let target_outpoint = OutPoint::new(txid_bitcoin, vout);
                        if let Some(prev_txout) = wallet.tx_graph().get_txout(target_outpoint) {
                            if let Some((keychain, derivation_index)) =
                                spk_index.index_of_spk(prev_txout.script_pubkey.clone())
                            {
                                let address = wallet
                                    .peek_address(*keychain, *derivation_index)
                                    .address
                                    .to_string();
                                set_address_if_none(conn, &address, label, &source)?;
                            }
                        }
                        // Label any tx that spends this coin.
                        for canonical_tx in wallet.transactions() {
                            if canonical_tx
                                .tx_node
                                .tx
                                .input
                                .iter()
                                .any(|i| i.previous_output == target_outpoint)
                            {
                                let spending_txid = canonical_tx.tx_node.txid.to_string();
                                set_tx_if_none(conn, &spending_txid, label, &source)?;
                            }
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

/// Cascade delete: remove all auto-labels that were propagated from the given entity.
/// Uses source_entity matching — safe even when multiple entities share the same label text.
fn cascade_delete_label(
    conn: &rusqlite::Connection,
    source_type: EntityType,
    source_id: &str,
) -> Result<()> {
    let source = source_entity_id(source_type, source_id);
    clear_source_labels(conn, &source)
}

/// Return all wallets found in wallets_dir, sorted newest-first.
pub fn list_wallets(wallets_dir: String, encryption_key_hex: String) -> Result<Vec<APIWalletInfo>> {
    let raw = list_wallets_in_dir(&wallets_dir, &encryption_key_hex);
    raw.into_iter()
        .map(|(path, row)| row_to_api_info(path, row))
        .collect()
}

/// Create a new wallet .db file and return its info.
#[allow(clippy::too_many_arguments)]
pub fn create_wallet(
    wallets_dir: String,
    name: String,
    descriptor: String,
    network: APINetwork,
    device_key_hex: String,
    protection_type: APIProtectionType,
    password: Option<String>,
    security_level: APISecurityLevel,
) -> Result<APIWalletInfo> {
    let m_cost = security_level.m_cost();
    let t_cost = security_level.t_cost();
    let protection = match protection_type {
        APIProtectionType::DeviceKey => WalletProtectionRequest::DeviceKey,
        APIProtectionType::UserPassword => {
            let pwd = password
                .ok_or_else(|| anyhow::anyhow!("Password required for UserPassword protection"))?;
            WalletProtectionRequest::UserPassword {
                password: pwd,
                m_cost,
                t_cost,
            }
        }
        APIProtectionType::XpubKey => WalletProtectionRequest::XpubKey {
            xpub_slots: xpub_slots_from_descriptor(&descriptor)?,
            m_cost,
            t_cost,
        },
    };
    let (path, row) = create_wallet_db(
        &wallets_dir,
        &name,
        &descriptor,
        network.as_str(),
        &device_key_hex,
        protection,
    )?;
    row_to_api_info(path, row)
}

/// Read metadata from an existing wallet file.
/// Pass `password` for UserPassword wallets, `None` for DeviceKey wallets.
pub fn get_wallet_info(
    wallet_path: String,
    device_key_hex: String,
    password: Option<String>,
) -> Result<APIWalletInfo> {
    let row = get_wallet_info_from_file(&wallet_path, &device_key_hex, password.as_deref())?;
    row_to_api_info(wallet_path, row)
}

/// Rename a wallet (updates wallet_info.name in the file).
/// Pass `password` for UserPassword wallets, `None` for DeviceKey wallets.
pub fn rename_wallet(
    wallet_path: String,
    name: String,
    device_key_hex: String,
    password: Option<String>,
) -> Result<()> {
    rename_wallet_in_file(&wallet_path, &name, &device_key_hex, password.as_deref())
}

/// Delete a wallet's .db, .db-wal, .db-shm, and .db.meta files.
pub fn delete_wallet(wallet_path: String) -> Result<()> {
    delete_meta(&wallet_path);
    for suffix in ["", "-wal", "-shm"] {
        let p = format!("{}{}", wallet_path, suffix);
        if std::path::Path::new(&p).exists() {
            std::fs::remove_file(&p)?;
        }
    }
    Ok(())
}

/// Open a wallet once and hold the live handle for repeated operations.
///
/// Reads descriptor and network from wallet_info inside the encrypted file,
/// then opens the BDK wallet in a single SQLite connection.
/// Pass `password` for UserPassword wallets, `None` for DeviceKey wallets.
pub fn open_wallet(
    wallet_path: String,
    device_key_hex: String,
    password: Option<String>,
) -> Result<APIWallet> {
    let data_key = resolve_wallet_key(&wallet_path, &device_key_hex, password.as_deref())?;
    let (descriptor, network, api_network, last_synced_at) = {
        let conn = open_encrypted_connection(&wallet_path, &data_key)?;
        let row = read_wallet_info(&conn)?;
        let api_network = APINetwork::try_from(row.network.as_str())?;
        let bdk_network: bdk_wallet::bitcoin::Network = api_network.into();
        (row.descriptor, bdk_network, api_network, row.last_synced_at)
    };
    // Refresh cached metadata in the .meta sidecar for UserPassword wallets so
    // the wallet list shows the correct network and last-synced date while locked.
    if wallet_needs_password(&wallet_path) {
        refresh_user_password_meta_cache(&wallet_path, api_network, last_synced_at);
    }
    let core = CoreWallet::open(&wallet_path, &descriptor, network, &data_key)?;
    Ok(APIWallet {
        inner: Mutex::new(core),
        path: wallet_path,
        electrum_url: Mutex::new(String::new()),
    })
}

/// Check whether a wallet requires a credential (password or xpub) to open.
pub fn wallet_requires_password(wallet_path: String) -> bool {
    wallet_needs_password(&wallet_path)
}

/// Check whether a wallet is XpubKey protected.
pub fn wallet_requires_xpub(wallet_path: String) -> bool {
    wallet_needs_xpub(&wallet_path)
}

/// Return the network stored in the wallet meta sidecar without opening the DB.
/// Returns None for DeviceKey wallets or when the meta cannot be read.
pub fn get_wallet_network_hint(wallet_path: String) -> Option<String> {
    wallet_network_hint(&wallet_path)
}

/// Add a new xpub slot to a XpubKey-protected wallet.
/// `current_xpub` is any already-registered xpub (used to derive the data key).
/// `new_mfp` and `new_xpub` identify the slot to add.
/// Derivation is looked up from the wallet descriptor automatically.
pub fn add_xpub_slot(
    wallet_path: String,
    new_mfp: String,
    new_xpub: String,
    device_key_hex: String,
    current_xpub: String,
) -> Result<()> {
    let data_key = resolve_wallet_key(&wallet_path, &device_key_hex, Some(&current_xpub))?;
    // Read the descriptor to find the derivation path for new_mfp.
    let conn = open_encrypted_connection(&wallet_path, &data_key)?;
    let row = read_wallet_info(&conn)?;
    drop(conn);
    let deriv_map = extract_xpub_derivation_map(&row.descriptor);
    let derivation = deriv_map
        .get(&new_mfp.to_lowercase())
        .cloned()
        .unwrap_or_default();
    add_xpub_slot_to_wallet(&wallet_path, &new_mfp, &new_xpub, &data_key, &derivation)
}

/// Remove an xpub slot by MFP from a XpubKey-protected wallet.
/// Fails if it would leave the wallet with zero slots.
pub fn remove_xpub_slot(wallet_path: String, mfp: String) -> Result<()> {
    remove_xpub_slot_from_wallet(&wallet_path, &mfp)
}

/// List all registered xpub slots for a XpubKey-protected wallet, including derivation hints.
pub fn list_xpub_slots(wallet_path: String) -> Result<Vec<APIXpubSlot>> {
    use crate::core::wallet_meta::read_meta;
    match read_meta(&wallet_path)? {
        ProtectionMeta::XpubKey { slots, .. } => Ok(slots
            .into_iter()
            .map(|s| APIXpubSlot {
                mfp: s.mfp,
                derivation_hint: s.derivation,
            })
            .collect()),
        _ => Ok(vec![]),
    }
}

/// Live wallet handle. Open once with [open_wallet], then call methods directly.
///
/// Holds the BDK wallet and its SQLite connection in memory — no file re-open per call.
pub struct APIWallet {
    inner: Mutex<CoreWallet>,
    pub path: String,
    /// Last Electrum URL used for sync/rescan/broadcast. Updated on every network call.
    electrum_url: Mutex<String>,
}

impl APIWallet {
    pub(super) fn lock_wallet(&self) -> Result<std::sync::MutexGuard<'_, CoreWallet>> {
        self.inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))
    }

    // -----------------------------------------------------------------------
    // Protection management
    // -----------------------------------------------------------------------

    /// Change the wallet's encryption protection scheme.
    ///
    /// Generates a fresh SQLCipher data key and re-encrypts the database
    /// in-place via `PRAGMA rekey` — the existing connection stays open and
    /// operational throughout. The `.meta` sidecar is then rewritten with the
    /// new scheme. No export/import required.
    ///
    /// After this call the Dart layer must update its credential cache:
    /// - `DeviceKey` → evict any cached password (automatic unlock).
    /// - `UserPassword` → cache `new_password`.
    /// - `XpubKey` → evict any cached password (user enters xpub on next open).
    pub fn change_protection(
        &self,
        device_key_hex: String,
        new_protection_type: APIProtectionType,
        new_password: Option<String>,
        security_level: APISecurityLevel,
    ) -> Result<()> {
        let mut core = self.lock_wallet()?;

        // 1. Generate a fresh data key for forward secrecy.
        let new_data_key = generate_data_key();

        // 2. Re-encrypt the database on the EXISTING connection — no close needed.
        core.rekey(&new_data_key)?;

        // 3. Build the protection request (XpubKey: auto-extract from descriptor).
        let row = read_wallet_info(&core.conn)?;
        let m_cost = security_level.m_cost();
        let t_cost = security_level.t_cost();
        let protection = match new_protection_type {
            APIProtectionType::DeviceKey => WalletProtectionRequest::DeviceKey,
            APIProtectionType::UserPassword => {
                let pwd = new_password
                    .ok_or_else(|| anyhow::anyhow!("Password required for UserPassword"))?;
                WalletProtectionRequest::UserPassword {
                    password: pwd,
                    m_cost,
                    t_cost,
                }
            }
            APIProtectionType::XpubKey => WalletProtectionRequest::XpubKey {
                xpub_slots: xpub_slots_from_descriptor(&row.descriptor)?,
                m_cost,
                t_cost,
            },
        };

        // 4. Build and write the new .meta sidecar.
        let meta = build_protection_meta(
            &new_data_key,
            &device_key_hex,
            protection,
            Some(&row.name),
            Some(&row.network),
        )?;
        write_meta(&self.path, &meta)?;

        Ok(())
    }

    // -----------------------------------------------------------------------
    // Hot key (seed) management
    // -----------------------------------------------------------------------

    /// Import a mnemonic phrase as a signing key. Validates the words, computes
    /// the MFP, and stores the seed in the encrypted wallet database.
    #[frb(sync)]
    pub fn add_mnemonic_key(
        &self,
        mnemonic: String,
        passphrase: Option<String>,
    ) -> Result<APIHotKeyInfo> {
        use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;

        let core = self.lock_wallet()?;

        let passphrase = passphrase.unwrap_or_default();
        let info = read_wallet_info(&core.conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();

        let secp = Secp256k1::new();
        let root_xprv = mnemonic_to_root_xprv(&mnemonic, &passphrase, network)?;
        let mfp = root_xprv_to_mfp(&root_xprv, &secp);

        let created_at = insert_seed_entry(
            &core.conn,
            &mfp,
            "mnemonic",
            Some(&mnemonic),
            &passphrase,
            None,
        )?;

        Ok(APIHotKeyInfo {
            mfp,
            seed_type: "mnemonic".to_string(),
            created_at,
        })
    }

    /// Import a master xprv (depth=0 only) as a signing key.
    #[frb(sync)]
    pub fn add_xprv_key(&self, xprv: String) -> Result<APIHotKeyInfo> {
        use crate::core::seed::{root_xprv_to_mfp, xprv_str_to_root_xprv};
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;

        let core = self.lock_wallet()?;

        let secp = Secp256k1::new();
        let root_xprv = xprv_str_to_root_xprv(&xprv)?;
        let mfp = root_xprv_to_mfp(&root_xprv, &secp);

        let created_at = insert_seed_entry(&core.conn, &mfp, "xprv", None, "", Some(&xprv))?;

        Ok(APIHotKeyInfo {
            mfp,
            seed_type: "xprv".to_string(),
            created_at,
        })
    }

    /// List all hot signing keys stored in this wallet (never exposes the seed).
    #[frb(sync)]
    pub fn list_hot_keys(&self) -> Result<Vec<APIHotKeyInfo>> {
        let core = self.lock_wallet()?;

        let entries = list_seed_entries(&core.conn)?;
        Ok(entries
            .into_iter()
            .map(|e| APIHotKeyInfo {
                mfp: e.mfp,
                seed_type: e.seed_type,
                created_at: e.created_at,
            })
            .collect())
    }

    /// Remove a hot signing key by MFP.
    #[frb(sync)]
    pub fn delete_hot_key(&self, mfp: String) -> Result<()> {
        let core = self.lock_wallet()?;
        delete_seed_entry(&core.conn, &mfp)
    }

    /// Derive the WIF-encoded private key for a specific address in this wallet.
    ///
    /// Looks up the address in the wallet's SPK index to find its keychain and
    /// derivation index, then combines that with the account path extracted from
    /// the wallet descriptor and the stored seed to produce the leaf private key,
    /// serialized in Wallet Import Format (WIF).
    ///
    /// Only valid for single-sig hot wallets. Call only after showing an
    /// appropriate security disclaimer — WIF exposes a spendable private key.
    #[frb(sync)]
    pub fn derive_address_wif(&self, address: String, mfp: String) -> Result<String> {
        use crate::core::seed::{extract_account_path_for_mfp, seed_entry_to_root_xprv};
        use bdk_wallet::bitcoin::bip32::DerivationPath;
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        use bdk_wallet::bitcoin::Address;
        use bdk_wallet::KeychainKind;
        use std::str::FromStr;

        let core = self.lock_wallet()?;
        let info = read_wallet_info(&core.conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();
        let secp = Secp256k1::new();

        // Resolve address string → script_pubkey.
        let addr = Address::from_str(&address)
            .map_err(|e| anyhow::anyhow!("Invalid address '{}': {}", address, e))?
            .require_network(network)
            .map_err(|_| anyhow::anyhow!("Address '{}' does not match wallet network", address))?;
        let spk = addr.script_pubkey();

        // Find (keychain, derivation_index) via the wallet's SPK index.
        let (keychain, addr_index) = core
            .wallet
            .spk_index()
            .index_of_spk(spk)
            .ok_or_else(|| anyhow::anyhow!("Address '{}' not found in this wallet", address))?;

        // Load the seed entry for this MFP.
        let seeds = list_seed_entries(&core.conn)?;
        let seed = seeds
            .iter()
            .find(|s| s.mfp == mfp)
            .ok_or_else(|| anyhow::anyhow!("No signing key with MFP {} found", mfp))?;

        let root_xprv = seed_entry_to_root_xprv(
            &seed.seed_type,
            seed.mnemonic.as_deref(),
            &seed.passphrase,
            seed.xprv.as_deref(),
            network,
        )?;

        // Extract the account path (e.g. "84'/0'/0'") from the wallet descriptor.
        let account_path = extract_account_path_for_mfp(&info.descriptor, &mfp)?;
        let chain_index = match keychain {
            KeychainKind::External => 0u32,
            KeychainKind::Internal => 1u32,
        };
        let full_path_str = format!("m/{}/{}/{}", account_path, chain_index, addr_index);
        let full_path = DerivationPath::from_str(&full_path_str)
            .map_err(|e| anyhow::anyhow!("Invalid derivation path '{}': {}", full_path_str, e))?;

        // Derive the leaf child key and serialize to WIF.
        let child_xprv = root_xprv.derive_priv(&secp, &full_path).map_err(|e| {
            anyhow::anyhow!("Derivation failed for path '{}': {}", full_path_str, e)
        })?;

        let private_key = bdk_wallet::bitcoin::PrivateKey {
            compressed: true,
            network: network.into(),
            inner: child_xprv.private_key,
        };
        Ok(private_key.to_wif())
    }

    /// Reveal the stored seed phrase or xprv for a hot signing key.
    ///
    /// The SQLCipher layer already protects this data at rest; this function
    /// exposes it in plaintext for display purposes only. Call only when the
    /// user explicitly requests it and after showing an appropriate disclaimer.
    #[frb(sync)]
    pub fn reveal_hot_key(&self, mfp: String) -> Result<String> {
        let core = self.lock_wallet()?;
        let result: rusqlite::Result<(Option<String>, Option<String>)> = core.conn.query_row(
            "SELECT mnemonic, xprv FROM seed_entries WHERE mfp = ?1",
            rusqlite::params![mfp],
            |row| Ok((row.get(0)?, row.get(1)?)),
        );
        let (mnemonic, xprv) =
            result.map_err(|_| anyhow::anyhow!("No signing key with MFP {} found", mfp))?;
        mnemonic
            .or(xprv)
            .ok_or_else(|| anyhow::anyhow!("Signing key entry for MFP {} has no seed data", mfp))
    }
}

/// Validate a mnemonic phrase and return its MFP without storing anything.
pub fn validate_mnemonic(
    mnemonic: String,
    passphrase: Option<String>,
    network: APINetwork,
) -> Result<APIHotKeyInfo> {
    use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;

    let passphrase = passphrase.unwrap_or_default();
    let net: bdk_wallet::bitcoin::Network = network.into();
    let secp = Secp256k1::new();
    let root_xprv = mnemonic_to_root_xprv(&mnemonic, &passphrase, net)?;
    let mfp = root_xprv_to_mfp(&root_xprv, &secp);
    Ok(APIHotKeyInfo {
        mfp,
        seed_type: "mnemonic".to_string(),
        created_at: 0,
    })
}

/// Derive a public keyspec `[mfp/path]xpub` from a mnemonic and derivation path.
///
/// Shared implementation: derive a child xpub from `root` and `derivation_path`,
/// returning a descriptor keyspec string `[mfp/path]xpub`.
///
/// `derivation_path` may include or omit the leading `m/`.
fn derive_and_format_keyspec(
    root: &bdk_wallet::bitcoin::bip32::Xpriv,
    mfp: &str,
    derivation_path: &str,
) -> Result<String> {
    use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpub};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use std::str::FromStr;

    let secp = Secp256k1::new();
    let path_str = if derivation_path.starts_with("m/") {
        derivation_path.to_string()
    } else {
        format!("m/{}", derivation_path)
    };
    let path = DerivationPath::from_str(&path_str)
        .map_err(|e| anyhow::anyhow!("Invalid derivation path '{}': {}", path_str, e))?;
    let child_xprv = root
        .derive_priv(&secp, &path)
        .map_err(|e| anyhow::anyhow!("Derivation failed: {}", e))?;
    let child_xpub = Xpub::from_priv(&secp, &child_xprv);
    let path_display = path_str.trim_start_matches("m/");
    Ok(format!("[{}/{}]{}", mfp, path_display, child_xpub))
}

/// `derivation_path` may include or omit the leading `m/`.
/// Returns a string suitable for use in a Bitcoin descriptor.
pub fn derive_keyspec(
    mnemonic: String,
    passphrase: Option<String>,
    derivation_path: String,
    network: APINetwork,
) -> Result<String> {
    use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;

    let passphrase = passphrase.unwrap_or_default();
    let net: bdk_wallet::bitcoin::Network = network.into();
    let secp = Secp256k1::new();
    let root = mnemonic_to_root_xprv(&mnemonic, &passphrase, net)?;
    let mfp = root_xprv_to_mfp(&root, &secp);
    derive_and_format_keyspec(&root, &mfp, &derivation_path)
}

/// Derive a public keyspec `[mfp/path]xpub` from a master xprv and derivation path.
///
/// `xprv_str` must be a depth-0 master key.
/// `derivation_path` may include or omit the leading `m/`.
pub fn derive_keyspec_from_xprv(xprv_str: String, derivation_path: String) -> Result<String> {
    use crate::core::seed::{root_xprv_to_mfp, xprv_str_to_root_xprv};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;

    let secp = Secp256k1::new();
    let root = xprv_str_to_root_xprv(&xprv_str)?;
    let mfp = root_xprv_to_mfp(&root, &secp);
    derive_and_format_keyspec(&root, &mfp, &derivation_path)
}

// ---------------------------------------------------------------------------
// Project hot-key (seed) functions
// ---------------------------------------------------------------------------

/// Store a mnemonic as a signing key for a project.
///
/// Validates the mnemonic, computes the MFP, and persists it in the
/// shared `project_seeds.db` (SQLCipher, device-key protected).
#[frb(sync)]
pub fn add_project_mnemonic_key(
    app_support_dir: String,
    project_id: i64,
    mnemonic: String,
    passphrase: Option<String>,
    network: APINetwork,
    device_key_hex: String,
) -> Result<APIHotKeyInfo> {
    use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;

    let passphrase = passphrase.unwrap_or_default();
    let net: bdk_wallet::bitcoin::Network = network.into();
    let secp = Secp256k1::new();
    let root_xprv = mnemonic_to_root_xprv(&mnemonic, &passphrase, net)?;
    let mfp = root_xprv_to_mfp(&root_xprv, &secp);

    let conn = open_project_seeds_db(&app_support_dir, &device_key_hex)?;
    let created_at = insert_project_seed_entry(
        &conn,
        project_id,
        &mfp,
        "mnemonic",
        Some(&mnemonic),
        &passphrase,
        None,
    )?;

    Ok(APIHotKeyInfo {
        mfp,
        seed_type: "mnemonic".to_string(),
        created_at,
    })
}

/// Store a master xprv (depth-0 only) as a signing key for a project.
#[frb(sync)]
pub fn add_project_xprv_key(
    app_support_dir: String,
    project_id: i64,
    xprv: String,
    device_key_hex: String,
) -> Result<APIHotKeyInfo> {
    use crate::core::seed::{root_xprv_to_mfp, xprv_str_to_root_xprv};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;

    let secp = Secp256k1::new();
    let root_xprv = xprv_str_to_root_xprv(&xprv)?;
    let mfp = root_xprv_to_mfp(&root_xprv, &secp);

    let conn = open_project_seeds_db(&app_support_dir, &device_key_hex)?;
    let created_at =
        insert_project_seed_entry(&conn, project_id, &mfp, "xprv", None, "", Some(&xprv))?;

    Ok(APIHotKeyInfo {
        mfp,
        seed_type: "xprv".to_string(),
        created_at,
    })
}

/// List all project signing keys (never exposes the seed itself).
#[frb(sync)]
pub fn list_project_hot_keys(
    app_support_dir: String,
    project_id: i64,
    device_key_hex: String,
) -> Result<Vec<APIHotKeyInfo>> {
    let conn = open_project_seeds_db(&app_support_dir, &device_key_hex)?;
    let entries = list_project_seed_entries(&conn, project_id)?;
    Ok(entries
        .into_iter()
        .map(|e| APIHotKeyInfo {
            mfp: e.mfp,
            seed_type: e.seed_type,
            created_at: e.created_at,
        })
        .collect())
}

/// Remove a project signing key by MFP.
#[frb(sync)]
pub fn delete_project_hot_key(
    app_support_dir: String,
    project_id: i64,
    mfp: String,
    device_key_hex: String,
) -> Result<()> {
    let conn = open_project_seeds_db(&app_support_dir, &device_key_hex)?;
    delete_project_seed_entry(&conn, project_id, &mfp)
}

/// Reveal the stored seed phrase or xprv for a project signing key.
///
/// Call only after showing an appropriate warning to the user.
#[frb(sync)]
pub fn reveal_project_seed(
    app_support_dir: String,
    project_id: i64,
    mfp: String,
    device_key_hex: String,
) -> Result<String> {
    let conn = open_project_seeds_db(&app_support_dir, &device_key_hex)?;
    reveal_project_seed_value(&conn, project_id, &mfp)
}

/// Copy all signing keys from a project's encrypted seeds DB into a wallet.
///
/// Returns the number of keys copied.
#[frb(sync)]
pub fn copy_project_keys_to_wallet(
    app_support_dir: String,
    project_id: i64,
    wallet_path: String,
    device_key_hex: String,
    wallet_password: Option<String>,
) -> Result<u32> {
    let proj_conn = open_project_seeds_db(&app_support_dir, &device_key_hex)?;
    let entries = list_project_seed_entries(&proj_conn, project_id)?;

    let wallet_key = resolve_wallet_key(&wallet_path, &device_key_hex, wallet_password.as_deref())?;
    let wallet_conn = open_encrypted_connection(&wallet_path, &wallet_key)?;

    let mut copied = 0u32;
    for entry in &entries {
        insert_seed_entry(
            &wallet_conn,
            &entry.mfp,
            &entry.seed_type,
            entry.mnemonic.as_deref(),
            &entry.passphrase,
            entry.xprv.as_deref(),
        )?;
        copied += 1;
    }
    Ok(copied)
}

// ---------------------------------------------------------------------------
// Backup functions (.deadbolt format)
// ---------------------------------------------------------------------------
//
// Format v1:
// {
//   "version": 1,
//   "wallet_name": "...",
//   "network": "bitcoin",
//   "created_at": 1234567890,
//   "protection": { "type": 1, "salt": "<hex>", "m_cost": 65536, "t_cost": 3, "p_cost": 1 },
//   "data_key_wrapped": "<hex(nonce||AES-GCM(export_key, data_key_bytes))>",
//   "data": "<base64(nonce||AES-GCM(export_key, raw_sqlcipher_db_bytes))>"
// }
//
// The backup password always protects both the raw DB file and the data_key.
// On import: derive export_key → unwrap data_key → decrypt DB → re-key to new data_key.

/// Export a wallet to a self-contained encrypted `.deadbolt` backup (v2 format).
///
/// `export_protection` must be `UserPassword` or `XpubKey`.
/// - `UserPassword`: provide `export_password`; the credential is protected with Argon2id.
/// - `XpubKey`: xpubs are auto-extracted from the descriptor; each gets its own slot.
///
/// `security_level` controls the Argon2id parameters for the export credential slots.
/// The returned bytes should be saved as a `.deadbolt` file.
pub fn export_wallet_backup(
    wallet_path: String,
    device_key_hex: String,
    open_password: Option<String>,
    export_protection: APIProtectionType,
    export_password: Option<String>,
    security_level: APISecurityLevel,
) -> Result<Vec<u8>> {
    use crate::core::key_protection::{
        derive_key_from_password, generate_salt, wrap_with_xpub, DEFAULT_P_COST,
    };
    use base64::{engine::general_purpose, Engine as _};

    if matches!(export_protection, APIProtectionType::DeviceKey) {
        return Err(anyhow::anyhow!(
            "DeviceKey protection cannot be used for backup export"
        ));
    }

    let wallet_data_key =
        resolve_wallet_key(&wallet_path, &device_key_hex, open_password.as_deref())?;
    let row = {
        let conn = open_encrypted_connection(&wallet_path, &wallet_data_key)?;
        read_wallet_info(&conn)?
    };

    // Read a complete, consistent snapshot of the database by using VACUUM INTO,
    // which consolidates the WAL into the destination file atomically.  Reading
    // the raw .db file directly would miss any writes still pending in the WAL.
    // The destination file is encrypted with the same key as the source because
    // SQLCipher applies its codec at the pager level during VACUUM INTO.
    let temp_path = format!("{}.export_tmp", wallet_path);
    // Remove any leftover temp file from a previously aborted export.
    let _ = std::fs::remove_file(&temp_path);
    let db_bytes = {
        let conn = open_encrypted_connection(&wallet_path, &wallet_data_key)?;
        conn.execute(
            &format!("VACUUM INTO '{}'", temp_path.replace('\'', "''")),
            [],
        )?;
        drop(conn);
        let bytes = std::fs::read(&temp_path);
        let _ = std::fs::remove_file(&temp_path);
        bytes?
    };
    let export_data_key = generate_data_key();
    let m_cost = security_level.m_cost();
    let t_cost = security_level.t_cost();

    let (ptype, slots): (u64, Vec<serde_json::Value>) = match export_protection {
        APIProtectionType::UserPassword => {
            let password = export_password
                .ok_or_else(|| anyhow::anyhow!("Export password required for UserPassword"))?;
            let salt = generate_salt();
            let wrapping_key =
                derive_key_from_password(&password, &salt, m_cost, t_cost, DEFAULT_P_COST)?;
            let wrapped_key =
                crate::core::key_protection::wrap_key(&export_data_key, &wrapping_key)?;
            let slot = serde_json::json!({
                "mfp": "",
                "salt": salt,
                "m_cost": m_cost,
                "t_cost": t_cost,
                "p_cost": DEFAULT_P_COST,
                "wrapped_key": wrapped_key
            });
            (1, vec![slot])
        }
        APIProtectionType::XpubKey => {
            let map = extract_xpub_mfp_map(&row.descriptor);
            if map.is_empty() {
                return Err(anyhow::anyhow!(
                    "No xpubs found in descriptor for XpubKey export"
                ));
            }
            let slots = map
                .iter()
                .map(|(mfp, xpub)| {
                    let slot = wrap_with_xpub(mfp, xpub, &export_data_key, m_cost, t_cost, "")?;
                    serde_json::to_value(&slot).map_err(|e| anyhow::anyhow!(e))
                })
                .collect::<Result<Vec<_>>>()?;
            (2, slots)
        }
        APIProtectionType::DeviceKey => unreachable!(),
    };

    let encrypted_db = encrypt_bytes(&export_data_key, &db_bytes)?;
    let data_b64 = general_purpose::STANDARD.encode(&encrypted_db);

    let wallet_data_key_bytes = hex::decode(&wallet_data_key)?;
    let encrypted_wallet_key = encrypt_bytes(&export_data_key, &wallet_data_key_bytes)?;
    let data_key_wrapped = hex::encode(&encrypted_wallet_key);

    let backup = serde_json::json!({
        "version": 2,
        "wallet_name": row.name,
        "network": row.network,
        "created_at": row.created_at,
        "protection": {
            "type": ptype,
            "slots": slots
        },
        "data_key_wrapped": data_key_wrapped,
        "data": data_b64
    });

    Ok(serde_json::to_vec(&backup)?)
}

/// Import a `.deadbolt` backup (v1 or v2) and add it as a new wallet in `wallets_dir`.
///
/// `import_credential`: password for UserPassword backups, xpub or keyspec for XpubKey backups.
/// Returns the `APIWalletInfo` of the restored wallet.
pub fn import_wallet_backup(
    backup_bytes: Vec<u8>,
    import_credential: String,
    device_key_hex: String,
    wallets_dir: String,
) -> Result<APIWalletInfo> {
    use crate::core::key_protection::{
        derive_key_from_password, generate_data_key, resolve_xpub_data_key, wrap_key,
        ProtectionMeta, XpubSlot,
    };
    use crate::core::wallet_meta::write_meta;
    use base64::{engine::general_purpose, Engine as _};

    let backup: serde_json::Value = serde_json::from_slice(&backup_bytes)
        .map_err(|e| anyhow::anyhow!("Invalid backup format: {}", e))?;

    let version = backup["version"]
        .as_u64()
        .ok_or_else(|| anyhow::anyhow!("Missing version in backup"))?;

    let data_b64 = backup["data"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing data in backup"))?;
    let data_key_wrapped_hex = backup["data_key_wrapped"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing data_key_wrapped in backup"))?;

    // Resolve export_data_key from whichever version/protection format is present.
    let export_data_key = if version == 1 {
        // v1: protection has salt/m_cost/t_cost/p_cost directly; import_credential is a password.
        let protection = &backup["protection"];
        let salt = protection["salt"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing salt in v1 backup"))?;
        let m_cost = protection["m_cost"].as_u64().unwrap_or(65536) as u32;
        let t_cost = protection["t_cost"].as_u64().unwrap_or(3) as u32;
        let p_cost = protection["p_cost"].as_u64().unwrap_or(1) as u32;
        // In v1, export_key = Argon2id(password, salt) and data_key_wrapped was encrypted
        // with export_key directly (there is no intermediate export_data_key).
        // Re-use the same path: derive the key and treat it as export_data_key.
        derive_key_from_password(&import_credential, salt, m_cost, t_cost, p_cost)?
    } else if version == 2 {
        // v2: protection has type + slots array.
        let protection = &backup["protection"];
        let ptype = protection["type"].as_u64().unwrap_or(0);
        let slots = protection["slots"]
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("Missing slots in v2 backup"))?;

        // Deserialize all slots (same XpubSlot format for both ptype=1 and ptype=2).
        let xpub_slots: Vec<XpubSlot> = slots
            .iter()
            .map(|s| serde_json::from_value(s.clone()))
            .collect::<Result<_, _>>()
            .map_err(|e| anyhow::anyhow!("Invalid slot in v2 backup: {}", e))?;

        if ptype == 1 {
            // UserPassword: single slot, credential is the password.
            let slot = xpub_slots
                .first()
                .ok_or_else(|| anyhow::anyhow!("No slots in v2 UserPassword backup"))?;
            let wrapping_key = derive_key_from_password(
                &import_credential,
                &slot.salt,
                slot.m_cost,
                slot.t_cost,
                slot.p_cost,
            )?;
            crate::core::key_protection::unwrap_key(&slot.wrapped_key, &wrapping_key)?
        } else if ptype == 2 {
            // XpubKey: try each slot with the provided xpub/keyspec credential.
            resolve_xpub_data_key(&import_credential, &xpub_slots)
                .map_err(|_| anyhow::anyhow!("xpub does not match any slot in backup"))?
        } else {
            return Err(anyhow::anyhow!("Unknown backup protection type: {}", ptype));
        }
    } else {
        return Err(anyhow::anyhow!("Unsupported backup version: {}", version));
    };

    let wallet_key_encrypted = hex::decode(data_key_wrapped_hex)?;
    let wallet_data_key_bytes = decrypt_bytes(&export_data_key, &wallet_key_encrypted)?;
    let wallet_data_key = hex::encode(&wallet_data_key_bytes);

    let encrypted_db = general_purpose::STANDARD
        .decode(data_b64)
        .map_err(|e| anyhow::anyhow!("base64 decode: {}", e))?;
    let db_bytes = decrypt_bytes(&export_data_key, &encrypted_db)?;

    std::fs::create_dir_all(&wallets_dir)?;
    let uuid = generate_uuid_v4();
    let path = std::path::Path::new(&wallets_dir)
        .join(format!("{}.db", uuid))
        .to_string_lossy()
        .to_string();
    std::fs::write(&path, &db_bytes)?;

    let new_data_key = generate_data_key();
    crate::core::wallet_persistence::rekey_database(&path, &wallet_data_key, &new_data_key)?;

    let wrapped_key = wrap_key(&new_data_key, &device_key_hex)?;
    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key,
    };
    write_meta(&path, &meta)?;

    let conn = crate::core::wallet_persistence::open_encrypted_connection(&path, &new_data_key)?;
    let row = crate::core::wallet_persistence::read_wallet_info(&conn)?;
    drop(conn);

    row_to_api_info(path, row)
}

/// Inspect a `.deadbolt` backup and return its protection type without decrypting it.
pub fn inspect_wallet_backup(backup_bytes: Vec<u8>) -> Result<APIProtectionType> {
    let backup: serde_json::Value = serde_json::from_slice(&backup_bytes)
        .map_err(|e| anyhow::anyhow!("Invalid backup format: {}", e))?;
    let ptype = backup["protection"]["type"].as_u64().unwrap_or(0);
    Ok(match ptype {
        1 => APIProtectionType::UserPassword,
        2 => APIProtectionType::XpubKey,
        _ => APIProtectionType::DeviceKey,
    })
}

/// Strip non-essential fields from a PSBT to reduce QR code size.
///
/// Returns the BIP39 English wordlist (2048 words, alphabetically sorted).
#[frb(sync)]
pub fn bip39_wordlist() -> Vec<String> {
    bdk_wallet::keys::bip39::Language::English
        .word_list()
        .iter()
        .map(|w| w.to_string())
        .collect()
}

/// Returns all BIP39 words that, when appended to `partial_words`, produce a valid
/// mnemonic of a supported BIP39 length (12, 15, 18, 21, or 24 words) and start
/// with `prefix`.
///
/// `partial_words` must contain exactly (target_length - 1) words, e.g. 11 words
/// for a 12-word mnemonic. Returns an empty list if the count is wrong.
#[frb(sync)]
pub fn bip39_valid_last_words(partial_words: String, prefix: String) -> Vec<String> {
    use bdk_wallet::keys::bip39::{Language, Mnemonic};

    let count = partial_words.split_whitespace().count();
    // Accept positions 11, 14, 17, 20, 23 (one before each valid length)
    const VALID_POSITIONS: [usize; 5] = [11, 14, 17, 20, 23];
    if !VALID_POSITIONS.contains(&count) {
        return vec![];
    }

    let wordlist = Language::English.word_list();
    let prefix_lower = prefix.to_lowercase();
    let base = partial_words.trim();

    wordlist
        .iter()
        .filter(|&&word| word.starts_with(prefix_lower.as_str()))
        .filter_map(|&word| {
            let candidate = format!("{base} {word}");
            if Mnemonic::parse(&candidate).is_ok() {
                Some(word.to_string())
            } else {
                None
            }
        })
        .collect()
}

/// Removes `non_witness_utxo` (full previous transaction, ~200-500 B per input)
/// when `witness_utxo` is present (segwit/taproot inputs), plus all `proprietary`
/// and `unknown` fields from global, inputs, and outputs.
///
/// The stored PSBT is never modified — this is only used for QR export.
pub fn strip_psbt_for_hw(psbt_base64: String) -> Result<String> {
    let mut psbt = psbt_from_base64(&psbt_base64)?;

    psbt.proprietary.clear();
    psbt.unknown.clear();

    for input in psbt.inputs.iter_mut() {
        if input.witness_utxo.is_some() {
            input.non_witness_utxo = None;
        }
        input.proprietary.clear();
        input.unknown.clear();
    }

    for output in psbt.outputs.iter_mut() {
        output.proprietary.clear();
        output.unknown.clear();
    }

    Ok(psbt_to_base64(&psbt))
}

// ───────────────────────────────────────────────────────────────────────────
// Test-only helpers on APIWallet
// ───────────────────────────────────────────────────────────────────────────

#[cfg(test)]
impl APIWallet {
    /// Inject a transaction into the wallet graph as **unconfirmed** (seen_at=1).
    /// Used by unit tests to set up wallet state without a real Electrum sync.
    pub(crate) fn inject_unconfirmed_tx(&self, tx: bdk_wallet::bitcoin::Transaction) -> Result<()> {
        use bdk_wallet::chain::TxUpdate;
        use bdk_wallet::Update;
        use std::sync::Arc;
        let txid = tx.compute_txid();
        let mut core = self.lock_wallet()?;
        let mut tx_update = TxUpdate::default();
        tx_update.txs = vec![Arc::new(tx)];
        tx_update.seen_ats = [(txid, 1_000_000_u64)].into();
        core.wallet.apply_update(Update {
            tx_update,
            ..Default::default()
        })?;
        Ok(())
    }

    /// Inject a transaction into the wallet graph with **no chain position**
    /// (not confirmed, not seen as unconfirmed). The tx is only present in the
    /// graph for txout lookups — it does NOT appear in `wallet.transactions()`.
    pub(crate) fn inject_graph_tx(&self, tx: bdk_wallet::bitcoin::Transaction) -> Result<()> {
        use bdk_wallet::chain::TxUpdate;
        use bdk_wallet::Update;
        use std::sync::Arc;
        let mut core = self.lock_wallet()?;
        let mut tx_update = TxUpdate::default();
        tx_update.txs = vec![Arc::new(tx)];
        core.wallet.apply_update(Update {
            tx_update,
            ..Default::default()
        })?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    fn make_wallet(dir: &tempfile::TempDir) -> Result<APIWalletInfo> {
        let wallets_dir = dir.path().to_string_lossy().to_string();
        create_wallet(
            wallets_dir,
            "Test Wallet".to_string(),
            MAINNET_DESC.to_string(),
            APINetwork::Bitcoin,
            KEY_HEX.to_string(),
            APIProtectionType::DeviceKey,
            None,
            APISecurityLevel::Standard,
        )
    }

    #[test]
    fn test_create_wallet_returns_info() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        assert_eq!(info.name, "Test Wallet");
        assert_eq!(info.network, APINetwork::Bitcoin);
        assert!(info.wallet_path.ends_with(".db"));
        assert!(std::path::Path::new(&info.wallet_path).exists());
        Ok(())
    }

    #[test]
    fn test_open_wallet_get_balance() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None)?;
        let balance = handle.get_balance()?;

        assert_eq!(balance.confirmed, 0);
        assert_eq!(balance.trusted_pending, 0);
        assert_eq!(balance.untrusted_pending, 0);
        assert_eq!(balance.immature, 0);
        Ok(())
    }

    #[test]
    fn test_open_wallet_get_transactions_empty() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None)?;
        let page = handle.get_transactions(0, 20)?;

        assert_eq!(page.total_count, 0);
        assert!(page.transactions.is_empty());
        assert!(!page.has_more);
        Ok(())
    }

    #[test]
    fn test_open_wallet_get_transactions_page_beyond_total() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None)?;
        let page = handle.get_transactions(10, 20)?;

        assert_eq!(page.total_count, 0);
        assert!(page.transactions.is_empty());
        assert!(!page.has_more);
        Ok(())
    }

    #[test]
    fn test_open_wallet_balance_consistent_across_calls() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None)?;
        let b1 = handle.get_balance()?;
        let b2 = handle.get_balance()?;

        assert_eq!(b1.confirmed, b2.confirmed);
        Ok(())
    }

    #[test]
    fn test_open_wallet_get_info() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        let handle = open_wallet(info.wallet_path.clone(), KEY_HEX.to_string(), None)?;
        let fetched = handle.get_info()?;

        assert_eq!(fetched.name, "Test Wallet");
        assert_eq!(fetched.network, APINetwork::Bitcoin);
        assert_eq!(fetched.wallet_path, info.wallet_path);
        Ok(())
    }

    #[test]
    fn test_list_wallets() -> Result<()> {
        let dir = tempdir()?;
        let wallets_dir = dir.path().to_string_lossy().to_string();

        create_wallet(
            wallets_dir.clone(),
            "W1".to_string(),
            MAINNET_DESC.to_string(),
            APINetwork::Bitcoin,
            KEY_HEX.to_string(),
            APIProtectionType::DeviceKey,
            None,
            APISecurityLevel::Standard,
        )?;
        create_wallet(
            wallets_dir.clone(),
            "W2".to_string(),
            MAINNET_DESC.to_string(),
            APINetwork::Bitcoin,
            KEY_HEX.to_string(),
            APIProtectionType::DeviceKey,
            None,
            APISecurityLevel::Standard,
        )?;

        let list = list_wallets(wallets_dir, KEY_HEX.to_string())?;
        assert_eq!(list.len(), 2);
        Ok(())
    }

    #[test]
    fn test_rename_wallet() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        rename_wallet(
            info.wallet_path.clone(),
            "Renamed".to_string(),
            KEY_HEX.to_string(),
            None,
        )?;

        let updated = get_wallet_info(info.wallet_path, KEY_HEX.to_string(), None)?;
        assert_eq!(updated.name, "Renamed");
        Ok(())
    }

    #[test]
    fn test_delete_wallet_removes_file() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;
        let path = info.wallet_path.clone();

        assert!(std::path::Path::new(&path).exists());

        delete_wallet(path.clone())?;

        assert!(!std::path::Path::new(&path).exists());
        Ok(())
    }
}
