use std::sync::Mutex;

use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIAddress, APIAddressDetails, APIBalance, APICoinControl, APIHotKeyInfo, APIImportPsbtResult,
    APIKeychain, APINetwork, APIPolicyPath, APIProtectionType, APIPsbtAnalysis, APIPsbtInfo,
    APIPsbtSignerStatus, APIRbfInfo, APIRelatedAddress, APIRelatedTx, APIRelatedUtxo,
    APITransaction, APITransactionPage, APITxDetails, APIUtxo, APIUtxoDetails, APIWalletInfo,
    APIWalletProtection,
};
use crate::core::key_protection::{decrypt_bytes, encrypt_bytes, ProtectionMeta};
use crate::core::project_seeds::{
    delete_project_seed_entry, insert_project_seed_entry, list_project_seed_entries,
    open_project_seeds_db, reveal_project_seed_value,
};
use crate::core::wallet::CoreWallet;
use crate::core::wallet_info::{
    create_wallet_db, generate_uuid_v4, get_wallet_info_from_file, list_wallets_in_dir,
    refresh_user_password_meta_cache, rename_wallet_in_file, resolve_wallet_key,
    wallet_needs_password, WalletProtectionRequest,
};
use crate::core::wallet_meta::{delete_meta, read_meta};
use crate::core::wallet_persistence::{
    address_has_explicit_label, coin_has_explicit_label, delete_psbt_row, delete_seed_entry,
    ensure_unsigned_txs_table, get_address_label_with_flag, get_all_address_labels_with_flag,
    get_all_coin_labels_with_flag, get_all_key_labels, get_all_path_labels,
    get_all_tx_labels_with_flag, get_coin_label_with_flag, get_psbt_row, get_psbt_row_by_txid,
    get_tx_label_with_flag, insert_psbt, insert_seed_entry, list_psbt_rows, list_seed_entries,
    open_encrypted_connection, read_wallet_info, set_address_label as db_set_address_label,
    set_coin_label as db_set_coin_label, set_key_label as db_set_key_label,
    set_path_label as db_set_path_label, set_tx_label as db_set_tx_label, touch_last_synced,
    tx_has_explicit_label, update_psbt_data, update_psbt_label, PsbtRow, WalletInfoRow,
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
        regex::Regex::new(r"\[([0-9a-fA-F]{8})[^\]]*\](xpub[A-Za-z0-9]+)").unwrap()
    });
    let mut map = std::collections::HashMap::new();
    for cap in re.captures_iter(descriptor) {
        map.insert(cap[1].to_lowercase(), cap[2].to_string());
    }
    map
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
        fee_sat: row.fee_sat,
        spend_path_id: row.spend_path_id,
        threshold: row.threshold,
        mfps: row.mfps,
        utxo_max_conf_height,
        has_spent_inputs,
    }
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
        Ok(ProtectionMeta::UserPassword { .. }) => APIWalletProtection {
            protection_type: APIProtectionType::UserPassword,
            needs_password: true,
        },
        _ => APIWalletProtection {
            protection_type: APIProtectionType::DeviceKey,
            needs_password: false,
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
    conn.execute(
        "DELETE FROM tx_labels WHERE source_entity = ?1",
        rusqlite::params![source],
    )?;
    conn.execute(
        "DELETE FROM address_labels WHERE source_entity = ?1",
        rusqlite::params![source],
    )?;
    conn.execute(
        "DELETE FROM coin_labels WHERE source_entity = ?1",
        rusqlite::params![source],
    )?;

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
                    if !coin_has_explicit_label(conn, &outpoint_str)? {
                        db_set_coin_label(conn, &outpoint_str, label, true, Some(&source))?;
                    }
                    if !address_has_explicit_label(conn, &address)? {
                        db_set_address_label(conn, &address, label, true, Some(&source))?;
                    }
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
                    if !coin_has_explicit_label(conn, &outpoint_str)? {
                        db_set_coin_label(conn, &outpoint_str, label, true, Some(&source))?;
                    }
                    if !address_has_explicit_label(conn, &address)? {
                        db_set_address_label(conn, &address, label, true, Some(&source))?;
                    }
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
                                if !coin_has_explicit_label(conn, &outpoint_str)? {
                                    db_set_coin_label(
                                        conn,
                                        &outpoint_str,
                                        label,
                                        true,
                                        Some(&source),
                                    )?;
                                }
                                // Label the creating tx.
                                if !tx_has_explicit_label(conn, &txid)? {
                                    db_set_tx_label(conn, &txid, label, true, Some(&source))?;
                                }
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
                            if !tx_has_explicit_label(conn, &spending_txid)? {
                                db_set_tx_label(conn, &spending_txid, label, true, Some(&source))?;
                            }
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
                if !tx_has_explicit_label(conn, txid)? {
                    db_set_tx_label(conn, txid, label, true, Some(&source))?;
                }
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
                                if !address_has_explicit_label(conn, &address)? {
                                    db_set_address_label(
                                        conn,
                                        &address,
                                        label,
                                        true,
                                        Some(&source),
                                    )?;
                                }
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
                                if !tx_has_explicit_label(conn, &spending_txid)? {
                                    db_set_tx_label(
                                        conn,
                                        &spending_txid,
                                        label,
                                        true,
                                        Some(&source),
                                    )?;
                                }
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
    conn.execute(
        "DELETE FROM tx_labels WHERE source_entity = ?1",
        rusqlite::params![source],
    )?;
    conn.execute(
        "DELETE FROM address_labels WHERE source_entity = ?1",
        rusqlite::params![source],
    )?;
    conn.execute(
        "DELETE FROM coin_labels WHERE source_entity = ?1",
        rusqlite::params![source],
    )?;
    Ok(())
}

/// Return all wallets found in wallets_dir, sorted newest-first.
pub fn list_wallets(wallets_dir: String, encryption_key_hex: String) -> Result<Vec<APIWalletInfo>> {
    let raw = list_wallets_in_dir(&wallets_dir, &encryption_key_hex);
    raw.into_iter()
        .map(|(path, row)| row_to_api_info(path, row))
        .collect()
}

/// Create a new wallet .db file and return its info.
pub fn create_wallet(
    wallets_dir: String,
    name: String,
    descriptor: String,
    network: APINetwork,
    device_key_hex: String,
    protection_type: APIProtectionType,
    password: Option<String>,
) -> Result<APIWalletInfo> {
    let protection = match protection_type {
        APIProtectionType::DeviceKey => WalletProtectionRequest::DeviceKey,
        APIProtectionType::UserPassword => {
            let pwd = password
                .ok_or_else(|| anyhow::anyhow!("Password required for UserPassword protection"))?;
            WalletProtectionRequest::UserPassword { password: pwd }
        }
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

/// Check whether a wallet requires a password to open.
pub fn wallet_requires_password(wallet_path: String) -> bool {
    wallet_needs_password(&wallet_path)
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

        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let passphrase = passphrase.unwrap_or_default();
        let network: bdk_wallet::bitcoin::Network = {
            let info = read_wallet_info(&core.conn)?;
            APINetwork::try_from(info.network.as_str())?.into()
        };

        let secp = Secp256k1::new();
        let root_xprv = mnemonic_to_root_xprv(&mnemonic, &passphrase, network)?;
        let mfp = root_xprv_to_mfp(&root_xprv, &secp);

        insert_seed_entry(
            &core.conn,
            &mfp,
            "mnemonic",
            Some(&mnemonic),
            &passphrase,
            None,
        )?;

        // Retrieve created_at timestamp we just inserted
        let created_at: i64 = core.conn.query_row(
            "SELECT created_at FROM seed_entries WHERE mfp = ?1",
            rusqlite::params![mfp],
            |row| row.get(0),
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

        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let secp = Secp256k1::new();
        let root_xprv = xprv_str_to_root_xprv(&xprv)?;
        let mfp = root_xprv_to_mfp(&root_xprv, &secp);

        insert_seed_entry(&core.conn, &mfp, "xprv", None, "", Some(&xprv))?;

        let created_at: i64 = core.conn.query_row(
            "SELECT created_at FROM seed_entries WHERE mfp = ?1",
            rusqlite::params![mfp],
            |row| row.get(0),
        )?;

        Ok(APIHotKeyInfo {
            mfp,
            seed_type: "xprv".to_string(),
            created_at,
        })
    }

    /// List all hot signing keys stored in this wallet (never exposes the seed).
    #[frb(sync)]
    pub fn list_hot_keys(&self) -> Result<Vec<APIHotKeyInfo>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

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
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        delete_seed_entry(&core.conn, &mfp)
    }

    /// Reveal the stored seed phrase or xprv for a hot signing key.
    ///
    /// The SQLCipher layer already protects this data at rest; this function
    /// exposes it in plaintext for display purposes only. Call only when the
    /// user explicitly requests it and after showing an appropriate disclaimer.
    #[frb(sync)]
    pub fn reveal_hot_key(&self, mfp: String) -> Result<String> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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
/// `derivation_path` may include or omit the leading `m/`.
/// Returns a string suitable for use in a Bitcoin descriptor.
pub fn derive_keyspec(
    mnemonic: String,
    passphrase: Option<String>,
    derivation_path: String,
    network: APINetwork,
) -> Result<String> {
    use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
    use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpub};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use std::str::FromStr;

    let passphrase = passphrase.unwrap_or_default();
    let net: bdk_wallet::bitcoin::Network = network.into();
    let secp = Secp256k1::new();
    let root = mnemonic_to_root_xprv(&mnemonic, &passphrase, net)?;
    let mfp = root_xprv_to_mfp(&root, &secp);

    let path_str = if derivation_path.starts_with("m/") {
        derivation_path.clone()
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

/// Derive a public keyspec `[mfp/path]xpub` from a master xprv and derivation path.
///
/// `xprv_str` must be a depth-0 master key.
/// `derivation_path` may include or omit the leading `m/`.
pub fn derive_keyspec_from_xprv(xprv_str: String, derivation_path: String) -> Result<String> {
    use crate::core::seed::{root_xprv_to_mfp, xprv_str_to_root_xprv};
    use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpub};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use std::str::FromStr;

    let secp = Secp256k1::new();
    let root = xprv_str_to_root_xprv(&xprv_str)?;
    let mfp = root_xprv_to_mfp(&root, &secp);

    let path_str = if derivation_path.starts_with("m/") {
        derivation_path.clone()
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
    insert_project_seed_entry(
        &conn,
        project_id,
        &mfp,
        "mnemonic",
        Some(&mnemonic),
        &passphrase,
        None,
    )?;

    let created_at: i64 = conn.query_row(
        "SELECT created_at FROM project_seed_entries WHERE project_id = ?1 AND mfp = ?2",
        rusqlite::params![project_id, mfp],
        |row| row.get(0),
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
    insert_project_seed_entry(&conn, project_id, &mfp, "xprv", None, "", Some(&xprv))?;

    let created_at: i64 = conn.query_row(
        "SELECT created_at FROM project_seed_entries WHERE project_id = ?1 AND mfp = ?2",
        rusqlite::params![project_id, mfp],
        |row| row.get(0),
    )?;

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

/// Export a wallet to a self-contained encrypted `.deadbolt` backup.
///
/// The backup is always encrypted with `export_password` via Argon2id, so it is
/// portable regardless of the original protection type.
///
/// The returned bytes should be saved as a `.deadbolt` file.
pub fn export_wallet_backup(
    wallet_path: String,
    device_key_hex: String,
    open_password: Option<String>,
    export_password: String,
) -> Result<Vec<u8>> {
    use crate::core::key_protection::{
        derive_key_from_password, generate_salt, DEFAULT_M_COST, DEFAULT_P_COST, DEFAULT_T_COST,
    };
    use base64::{engine::general_purpose, Engine as _};

    // Resolve the data key to verify access
    let data_key = resolve_wallet_key(&wallet_path, &device_key_hex, open_password.as_deref())?;

    // Read wallet info for metadata
    let conn = open_encrypted_connection(&wallet_path, &data_key)?;
    let row = read_wallet_info(&conn)?;
    drop(conn);

    // Read raw DB bytes (SQLCipher-encrypted with data_key)
    let db_bytes = std::fs::read(&wallet_path)?;

    // Derive export key from export_password
    let salt = generate_salt();
    let export_key = derive_key_from_password(
        &export_password,
        &salt,
        DEFAULT_M_COST,
        DEFAULT_T_COST,
        DEFAULT_P_COST,
    )?;

    // Encrypt raw DB bytes with export_key
    let encrypted_db = encrypt_bytes(&export_key, &db_bytes)?;
    let data_b64 = general_purpose::STANDARD.encode(&encrypted_db);

    // Wrap data_key with export_key so the importer can re-key the DB
    let data_key_bytes = hex::decode(&data_key)?;
    let encrypted_data_key = encrypt_bytes(&export_key, &data_key_bytes)?;
    let data_key_wrapped = hex::encode(&encrypted_data_key);

    let backup = serde_json::json!({
        "version": 1,
        "wallet_name": row.name,
        "network": row.network,
        "created_at": row.created_at,
        "protection": {
            "type": 1,
            "salt": salt,
            "m_cost": DEFAULT_M_COST,
            "t_cost": DEFAULT_T_COST,
            "p_cost": DEFAULT_P_COST
        },
        "data_key_wrapped": data_key_wrapped,
        "data": data_b64
    });

    Ok(serde_json::to_vec(&backup)?)
}

/// Import a `.deadbolt` backup and add it as a new wallet in `wallets_dir`.
///
/// Returns the `APIWalletInfo` of the restored wallet.
pub fn import_wallet_backup(
    backup_bytes: Vec<u8>,
    import_password: String,
    device_key_hex: String,
    wallets_dir: String,
) -> Result<APIWalletInfo> {
    use crate::core::key_protection::{
        derive_key_from_password, generate_data_key, wrap_key, ProtectionMeta,
    };
    use crate::core::wallet_meta::write_meta;
    use base64::{engine::general_purpose, Engine as _};

    let backup: serde_json::Value = serde_json::from_slice(&backup_bytes)
        .map_err(|e| anyhow::anyhow!("Invalid backup format: {}", e))?;

    let version = backup["version"]
        .as_u64()
        .ok_or_else(|| anyhow::anyhow!("Missing version in backup"))?;
    if version != 1 {
        return Err(anyhow::anyhow!("Unsupported backup version: {}", version));
    }

    let protection = &backup["protection"];
    let salt = protection["salt"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing salt in backup"))?;
    let m_cost = protection["m_cost"].as_u64().unwrap_or(65536) as u32;
    let t_cost = protection["t_cost"].as_u64().unwrap_or(3) as u32;
    let p_cost = protection["p_cost"].as_u64().unwrap_or(1) as u32;

    let data_b64 = backup["data"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing data in backup"))?;
    let data_key_wrapped_hex = backup["data_key_wrapped"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing data_key_wrapped in backup"))?;

    // Derive import key
    let import_key = derive_key_from_password(&import_password, salt, m_cost, t_cost, p_cost)?;

    // Unwrap the original data_key
    let data_key_encrypted = hex::decode(data_key_wrapped_hex)?;
    let data_key_bytes = decrypt_bytes(&import_key, &data_key_encrypted)?;
    let data_key = hex::encode(&data_key_bytes);

    // Decrypt raw DB bytes
    let encrypted_db = general_purpose::STANDARD
        .decode(data_b64)
        .map_err(|e| anyhow::anyhow!("base64 decode: {}", e))?;
    let db_bytes = decrypt_bytes(&import_key, &encrypted_db)?;

    // Write restored DB to wallets_dir with a new UUID filename
    std::fs::create_dir_all(&wallets_dir)?;
    let uuid = generate_uuid_v4();
    let path = std::path::Path::new(&wallets_dir)
        .join(format!("{}.db", uuid))
        .to_string_lossy()
        .to_string();

    // Write raw DB bytes (SQLCipher-encrypted with original data_key)
    std::fs::write(&path, &db_bytes)?;

    // Re-key to a fresh data_key and create DeviceKey meta
    let new_data_key = generate_data_key();
    crate::core::wallet_persistence::rekey_database(&path, &data_key, &new_data_key)?;

    let wrapped_key = wrap_key(&new_data_key, &device_key_hex)?;
    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key,
    };
    write_meta(&path, &meta)?;

    // Read info from the restored wallet
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
    Ok(if ptype == 1 {
        APIProtectionType::UserPassword
    } else {
        APIProtectionType::DeviceKey
    })
}

/// Strip non-essential fields from a PSBT to reduce QR code size.
///
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
        )?;
        create_wallet(
            wallets_dir.clone(),
            "W2".to_string(),
            MAINNET_DESC.to_string(),
            APINetwork::Bitcoin,
            KEY_HEX.to_string(),
            APIProtectionType::DeviceKey,
            None,
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
