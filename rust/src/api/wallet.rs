use std::sync::Mutex;

use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIAddress, APIAddressDetails, APIBalance, APICoinControl, APIImportPsbtResult, APIKeychain,
    APINetwork, APIPolicyPath, APIPsbtAnalysis, APIPsbtInfo, APIPsbtSignerStatus, APIRbfInfo,
    APIRelatedAddress, APIRelatedTx, APIRelatedUtxo, APITransaction, APITransactionPage,
    APITxDetails, APIUtxo, APIUtxoDetails, APIWalletInfo,
};
use crate::core::wallet::CoreWallet;
use crate::core::wallet_info::{
    create_wallet_db, get_wallet_info_from_file, list_wallets_in_dir, rename_wallet_in_file,
};
use crate::core::wallet_persistence::{
    address_has_explicit_label, coin_has_explicit_label, delete_psbt_row,
    ensure_unsigned_txs_table, get_address_label_with_flag, get_all_address_labels_with_flag,
    get_all_coin_labels_with_flag, get_all_key_labels, get_all_path_labels,
    get_all_tx_labels_with_flag, get_coin_label_with_flag, get_psbt_row, get_psbt_row_by_txid,
    get_tx_label_with_flag, insert_psbt, list_psbt_rows, open_encrypted_connection,
    read_wallet_info, set_address_label as db_set_address_label,
    set_coin_label as db_set_coin_label, set_key_label as db_set_key_label,
    set_path_label as db_set_path_label, set_tx_label as db_set_tx_label, touch_last_synced,
    tx_has_explicit_label, update_psbt_data, update_psbt_label, PsbtRow, WalletInfoRow,
};

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
    let label = data
        .as_ref()
        .filter(|(l, a)| !a && !l.is_empty())
        .map(|(l, _)| l.clone());
    let effective_label = data
        .as_ref()
        .filter(|(l, _)| !l.is_empty())
        .map(|(l, _)| l.clone());
    let is_auto = data.as_ref().map(|(_, a)| *a).unwrap_or(false);
    (label, effective_label, is_auto)
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
    Ok(APIWalletInfo {
        wallet_path,
        name: row.name,
        descriptor: row.descriptor,
        network,
        source_project_id: row.source_project_id,
        created_at: row.created_at,
        last_synced_at: row.last_synced_at,
    })
}

// ---------------------------------------------------------------------------
// Label propagation helpers
// ---------------------------------------------------------------------------

/// Build a map txid → Vec<(address, addr_label, coin_label)> from all unspent outputs.
#[allow(clippy::type_complexity)]
fn build_tx_utxo_map(
    wallet: &bdk_wallet::Wallet,
    address_labels: &std::collections::HashMap<String, String>,
    coin_labels: &std::collections::HashMap<String, String>,
) -> std::collections::HashMap<String, Vec<(String, Option<String>, Option<String>)>> {
    let mut map: std::collections::HashMap<String, Vec<_>> = std::collections::HashMap::new();
    for utxo in wallet.list_unspent() {
        let address = wallet
            .peek_address(utxo.keychain, utxo.derivation_index)
            .address
            .to_string();
        let outpoint_key = format!("{}:{}", utxo.outpoint.txid, utxo.outpoint.vout);
        let addr_label = address_labels
            .get(&address)
            .filter(|l| !l.is_empty())
            .cloned();
        let coin_label = coin_labels
            .get(&outpoint_key)
            .filter(|l| !l.is_empty())
            .cloned();
        map.entry(utxo.outpoint.txid.to_string())
            .or_default()
            .push((address, addr_label, coin_label));
    }
    map
}

/// Build a map address → Vec<(txid, tx_label, coin_label)> from all unspent outputs.
#[allow(clippy::type_complexity)]
fn build_addr_utxo_map(
    wallet: &bdk_wallet::Wallet,
    tx_labels: &std::collections::HashMap<String, String>,
    coin_labels: &std::collections::HashMap<String, String>,
) -> std::collections::HashMap<String, Vec<(String, Option<String>, Option<String>)>> {
    let mut map: std::collections::HashMap<String, Vec<_>> = std::collections::HashMap::new();
    for utxo in wallet.list_unspent() {
        let address = wallet
            .peek_address(utxo.keychain, utxo.derivation_index)
            .address
            .to_string();
        let outpoint_key = format!("{}:{}", utxo.outpoint.txid, utxo.outpoint.vout);
        let txid = utxo.outpoint.txid.to_string();
        let tx_label = tx_labels.get(&txid).filter(|l| !l.is_empty()).cloned();
        let coin_label = coin_labels
            .get(&outpoint_key)
            .filter(|l| !l.is_empty())
            .cloned();
        map.entry(address)
            .or_default()
            .push((txid, tx_label, coin_label));
    }
    map
}

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
            let tx_utxo_map = build_tx_utxo_map(
                wallet,
                &std::collections::HashMap::new(),
                &std::collections::HashMap::new(),
            );
            if let Some(utxos) = tx_utxo_map.get(txid) {
                for (address, _, _) in utxos {
                    if !address_has_explicit_label(conn, address)? {
                        db_set_address_label(conn, address, label, true, Some(&source))?;
                    }
                }
            }
        }
        EntityType::Address => {
            let address = source_id;
            let addr_utxo_map = build_addr_utxo_map(
                wallet,
                &std::collections::HashMap::new(),
                &std::collections::HashMap::new(),
            );
            if let Some(utxos) = addr_utxo_map.get(address) {
                for (txid, _, _) in utxos {
                    if !tx_has_explicit_label(conn, txid)? {
                        db_set_tx_label(conn, txid, label, true, Some(&source))?;
                    }
                }
            }
            for utxo in wallet.list_unspent() {
                let utxo_address = wallet
                    .peek_address(utxo.keychain, utxo.derivation_index)
                    .address
                    .to_string();
                if utxo_address == address {
                    let outpoint = format!("{}:{}", utxo.outpoint.txid, utxo.outpoint.vout);
                    if !coin_has_explicit_label(conn, &outpoint)? {
                        db_set_coin_label(conn, &outpoint, label, true, Some(&source))?;
                    }
                }
            }
        }
        EntityType::Coin => {
            let outpoint = source_id;
            let parts: Vec<&str> = outpoint.split(':').collect();
            if parts.len() == 2 {
                let txid = parts[0];
                if !tx_has_explicit_label(conn, txid)? {
                    db_set_tx_label(conn, txid, label, true, Some(&source))?;
                }
                if let Ok(vout) = parts[1].parse::<u32>() {
                    if let Some(address_info) = wallet
                        .list_unspent()
                        .find(|u| u.outpoint.txid.to_string() == txid && u.outpoint.vout == vout)
                    {
                        let address = wallet
                            .peek_address(address_info.keychain, address_info.derivation_index)
                            .address
                            .to_string();
                        if !address_has_explicit_label(conn, &address)? {
                            db_set_address_label(conn, &address, label, true, Some(&source))?;
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
    source_project_id: Option<i64>,
    encryption_key_hex: String,
) -> Result<APIWalletInfo> {
    let (path, row) = create_wallet_db(
        &wallets_dir,
        &name,
        &descriptor,
        network.as_str(),
        source_project_id,
        &encryption_key_hex,
    )?;
    row_to_api_info(path, row)
}

/// Read metadata from an existing wallet file.
pub fn get_wallet_info(wallet_path: String, encryption_key_hex: String) -> Result<APIWalletInfo> {
    let row = get_wallet_info_from_file(&wallet_path, &encryption_key_hex)?;
    row_to_api_info(wallet_path, row)
}

/// Rename a wallet (updates wallet_info.name in the file).
pub fn rename_wallet(wallet_path: String, name: String, encryption_key_hex: String) -> Result<()> {
    rename_wallet_in_file(&wallet_path, &name, &encryption_key_hex)
}

/// Delete a wallet's .db, .db-wal, and .db-shm files. No encryption key needed.
pub fn delete_wallet(wallet_path: String) -> Result<()> {
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
pub fn open_wallet(wallet_path: String, encryption_key_hex: String) -> Result<APIWallet> {
    let (descriptor, network) = {
        let conn = open_encrypted_connection(&wallet_path, &encryption_key_hex)?;
        let row = read_wallet_info(&conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(row.network.as_str())?.into();
        (row.descriptor, network)
    };
    let core = CoreWallet::open(&wallet_path, &descriptor, network, &encryption_key_hex)?;
    Ok(APIWallet {
        inner: Mutex::new(core),
        path: wallet_path,
        electrum_url: Mutex::new(String::new()),
    })
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
    /// Return the cached balance (no network call).
    pub fn get_balance(&self) -> Result<APIBalance> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let balance = core.wallet.balance();
        Ok(APIBalance {
            confirmed: balance.confirmed.to_sat(),
            trusted_pending: balance.trusted_pending.to_sat(),
            untrusted_pending: balance.untrusted_pending.to_sat(),
            immature: balance.immature.to_sat(),
        })
    }

    /// Return a paginated page of transactions, sorted newest-first (no network call).
    pub fn get_transactions(&self, page: u32, page_size: u32) -> Result<APITransactionPage> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let mut txs: Vec<_> = wallet.transactions().collect();
        txs.sort_by(|a, b| {
            // Unconfirmed txs have no height (None). Treat them as u32::MAX so they
            // sort before all confirmed transactions (newest-first order).
            let ha = a
                .chain_position
                .confirmation_height_upper_bound()
                .unwrap_or(u32::MAX);
            let hb = b
                .chain_position
                .confirmation_height_upper_bound()
                .unwrap_or(u32::MAX);
            hb.cmp(&ha)
        });

        let total_count = txs.len() as u32;
        let start = (page * page_size) as usize;
        let end = (start + page_size as usize).min(txs.len());
        let has_more = end < txs.len();

        let tx_labels = get_all_tx_labels_with_flag(&core.conn).unwrap_or_default();

        let page_txs: Vec<APITransaction> = if start < txs.len() {
            txs[start..end]
                .iter()
                .map(|canonical_tx| {
                    let tx = &canonical_tx.tx_node.tx;
                    let txid = canonical_tx.tx_node.txid.to_string();

                    let (confirmation_height, confirmation_time) =
                        if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                            &canonical_tx.chain_position
                        {
                            (Some(anchor.block_id.height), Some(anchor.confirmation_time))
                        } else {
                            (None, None)
                        };

                    let (sent, received) = wallet.sent_and_received(tx);
                    let fee = wallet.calculate_fee(tx).ok().map(|f| f.to_sat());

                    let (label, effective_label, is_auto) =
                        resolve_label(tx_labels.get(&txid).cloned());

                    APITransaction {
                        txid,
                        received: received.to_sat(),
                        sent: sent.to_sat(),
                        fee,
                        confirmation_height,
                        confirmation_time,
                        label,
                        effective_label,
                        is_auto,
                    }
                })
                .collect()
        } else {
            vec![]
        };

        Ok(APITransactionPage {
            transactions: page_txs,
            total_count,
            has_more,
        })
    }

    /// Store the Electrum URL so it can be used by detail queries (e.g. fetching
    /// unknown input transactions). Call this before sync if you want it available
    /// immediately without waiting for sync to complete.
    #[frb(sync)]
    pub fn set_electrum_url(&self, url: String) {
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = url;
        }
    }

    /// Sync with Electrum, persist, and update last_synced_at.
    ///
    /// Uses full_scan on first sync (last_synced_at is None) to discover all addresses
    /// up to the stop gap. Uses incremental sync on subsequent calls to only check
    /// already-revealed script pubkeys, which is much faster.
    pub async fn sync(&self, electrum_url: String) -> Result<()> {
        use bdk_electrum::electrum_client;
        use bdk_electrum::BdkElectrumClient;

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let is_first_sync = read_wallet_info(&core.conn)?.last_synced_at.is_none();

        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);

        if is_first_sync {
            let request = core.wallet.start_full_scan();
            let update = client.full_scan(request, STOP_GAP, BATCH_SIZE, false)?;
            core.wallet.apply_update(update)?;
        } else {
            let request = core.wallet.start_sync_with_revealed_spks();
            let update = client.sync(request, BATCH_SIZE, false)?;
            core.wallet.apply_update(update)?;
        }

        core.persist()?;
        touch_last_synced(&core.conn)?;

        // Auto-delete PSBTs whose transaction is now known to the wallet
        // (broadcast externally and seen by Electrum during this sync).
        // The txid is stored at creation time — no need to re-decode the PSBT.
        if let Ok(rows) = list_psbt_rows(&core.conn) {
            for row in rows {
                if row.txid.is_empty() {
                    continue;
                }
                if let Ok(txid) = row.txid.parse::<bdk_wallet::bitcoin::Txid>() {
                    if core.wallet.tx_graph().get_tx(txid).is_some() {
                        apply_psbt_label_to_tx(&core.conn, &row);
                        let _ = delete_psbt_row(&core.conn, row.id);
                    }
                }
            }
        }

        drop(core);
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(())
    }

    /// Force a full scan regardless of sync history (re-discovers all addresses).
    pub async fn rescan(&self, electrum_url: String) -> Result<()> {
        use bdk_electrum::electrum_client;
        use bdk_electrum::BdkElectrumClient;

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);
        let request = core.wallet.start_full_scan();
        let update = client.full_scan(request, STOP_GAP, BATCH_SIZE, false)?;
        core.wallet.apply_update(update)?;
        core.persist()?;
        touch_last_synced(&core.conn)?;

        // Auto-delete PSBTs whose transaction is now known after rescan.
        if let Ok(rows) = list_psbt_rows(&core.conn) {
            for row in rows {
                if row.txid.is_empty() {
                    continue;
                }
                if let Ok(txid) = row.txid.parse::<bdk_wallet::bitcoin::Txid>() {
                    if core.wallet.tx_graph().get_tx(txid).is_some() {
                        apply_psbt_label_to_tx(&core.conn, &row);
                        let _ = delete_psbt_row(&core.conn, row.id);
                    }
                }
            }
        }

        drop(core);
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(())
    }

    /// Persist a label for a transaction. Pass an empty string to remove it.
    /// Automatically propagates to related entities (addresses and UTXOs).
    /// Clearing an inherited (auto) label is a no-op.
    #[frb(sync)]
    pub fn set_tx_label(&self, txid: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        if label.is_empty() {
            match get_tx_label_with_flag(&core.conn, &txid)? {
                Some((_, false)) => {
                    // Explicit label: delete the row and cascade.
                    db_set_tx_label(&core.conn, &txid, "", false, None)?;
                    cascade_delete_label(&core.conn, EntityType::Tx, &txid)?;
                }
                Some((_, true)) => {
                    // Inherited auto-label: no-op — only the source can clear it.
                }
                None => {} // Nothing to do.
            }
        } else {
            db_set_tx_label(&core.conn, &txid, &label, false, None)?;
            propagate_label(&core.conn, &core.wallet, EntityType::Tx, &txid, &label)?;
        }
        Ok(())
    }

    /// Read wallet metadata from the open connection (no file re-open).
    pub fn get_info(&self) -> Result<APIWalletInfo> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let row = read_wallet_info(&core.conn)?;
        row_to_api_info(self.path.clone(), row)
    }

    /// Return all currently revealed addresses for the given keychain, sorted by index ascending.
    /// Balance is the sum of all unspent outputs currently controlled by each address.
    pub fn get_addresses(&self, keychain: APIKeychain) -> Result<Vec<APIAddress>> {
        use bdk_wallet::KeychainKind;

        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let bdk_keychain = match keychain {
            APIKeychain::External => KeychainKind::External,
            APIKeychain::Internal => KeychainKind::Internal,
        };

        // Build UTXO balance map: derivation_index -> total sats for this keychain
        let mut balance_map: HashMap<u32, u64> = HashMap::new();
        for utxo in wallet.list_unspent() {
            if utxo.keychain == bdk_keychain {
                *balance_map.entry(utxo.derivation_index).or_insert(0) += utxo.txout.value.to_sat();
            }
        }

        // Count distinct transactions per address index and track used ones.
        // Two passes: (1) outputs → receiving txids + outpoint→idx map,
        //             (2) inputs spending our outpoints → spending txids.
        use std::collections::{HashMap, HashSet};
        let spk_index = wallet.spk_index();
        // addr_idx → set of distinct txids (both receiving and spending)
        let mut per_addr_txids: HashMap<u32, HashSet<String>> = HashMap::new();
        // (txid, vout) → address index, for spend detection in pass 2
        let mut outpoint_to_idx: HashMap<(String, u32), u32> = HashMap::new();

        for canonical_tx in wallet.transactions() {
            let txid_str = canonical_tx.tx_node.txid.to_string();
            for (vout_idx, output) in canonical_tx.tx_node.tx.output.iter().enumerate() {
                if let Some((k, idx)) = spk_index.index_of_spk(output.script_pubkey.clone()) {
                    if *k == bdk_keychain {
                        per_addr_txids
                            .entry(*idx)
                            .or_default()
                            .insert(txid_str.clone());
                        outpoint_to_idx.insert((txid_str.clone(), vout_idx as u32), *idx);
                    }
                }
            }
        }
        for canonical_tx in wallet.transactions() {
            let txid_str = canonical_tx.tx_node.txid.to_string();
            for input in canonical_tx.tx_node.tx.input.iter() {
                let prev = (
                    input.previous_output.txid.to_string(),
                    input.previous_output.vout,
                );
                if let Some(&idx) = outpoint_to_idx.get(&prev) {
                    per_addr_txids
                        .entry(idx)
                        .or_default()
                        .insert(txid_str.clone());
                }
            }
        }

        let address_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();

        // Collect all revealed addresses sorted by index ascending
        let mut addrs: Vec<APIAddress> = spk_index
            .revealed_keychain_spks(bdk_keychain)
            .map(|(idx, _)| {
                let addr = wallet.peek_address(bdk_keychain, idx).address.to_string();
                let balance_sat = balance_map.get(&idx).copied().unwrap_or(0);
                let addr_txids = per_addr_txids.get(&idx);
                let is_used = addr_txids.is_some();
                let tx_count = addr_txids.map(|s| s.len() as u32).unwrap_or(0);

                let (label, effective_label, is_auto) =
                    resolve_label(address_labels.get(&addr).cloned());

                APIAddress {
                    address: addr,
                    index: idx,
                    keychain,
                    balance_sat,
                    is_used,
                    tx_count,
                    label,
                    effective_label,
                    is_auto,
                }
            })
            .collect();

        addrs.sort_by_key(|a| a.index);
        Ok(addrs)
    }

    /// Return all unspent outputs (UTXOs / coins), sorted by value descending.
    pub fn get_utxos(&self) -> Result<Vec<APIUtxo>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let coin_labels = get_all_coin_labels_with_flag(&core.conn).unwrap_or_default();

        // Build outpoint → [psbt_id] map from all pending PSBTs.
        let mut pending_map: std::collections::HashMap<String, Vec<i64>> =
            std::collections::HashMap::new();
        if let Ok(rows) = list_psbt_rows(&core.conn) {
            for row in rows {
                if let Ok(psbt) = psbt_from_base64(&row.psbt) {
                    for txin in &psbt.unsigned_tx.input {
                        let key = format!(
                            "{}:{}",
                            txin.previous_output.txid, txin.previous_output.vout
                        );
                        pending_map.entry(key).or_default().push(row.id);
                    }
                }
            }
        }

        // Build txid → confirmation_height map for all wallet transactions.
        // Used to determine the original confirmation status of ghost UTXOs.
        let tx_conf_heights: std::collections::HashMap<bdk_wallet::bitcoin::Txid, Option<u32>> =
            wallet
                .transactions()
                .map(|t| {
                    let height =
                        if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                            &t.chain_position
                        {
                            Some(anchor.block_id.height)
                        } else {
                            None
                        };
                    (t.tx_node.txid, height)
                })
                .collect();

        // Regular UTXOs (unspent per BDK).
        let mut utxos: Vec<APIUtxo> = wallet
            .list_unspent()
            .map(|local_output| {
                let keychain = match local_output.keychain {
                    bdk_wallet::KeychainKind::External => APIKeychain::External,
                    bdk_wallet::KeychainKind::Internal => APIKeychain::Internal,
                };
                let address = wallet
                    .peek_address(local_output.keychain, local_output.derivation_index)
                    .address
                    .to_string();
                let is_confirmed = matches!(
                    &local_output.chain_position,
                    bdk_wallet::chain::ChainPosition::Confirmed { .. }
                );
                let confirmation_height =
                    if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                        &local_output.chain_position
                    {
                        Some(anchor.block_id.height)
                    } else {
                        None
                    };
                let outpoint_key = format!(
                    "{}:{}",
                    local_output.outpoint.txid, local_output.outpoint.vout
                );
                let (label, effective_label, is_auto) =
                    resolve_label(coin_labels.get(&outpoint_key).cloned());
                let pending_psbt_ids = pending_map.get(&outpoint_key).cloned().unwrap_or_default();

                APIUtxo {
                    txid: local_output.outpoint.txid.to_string(),
                    vout: local_output.outpoint.vout,
                    value_sat: local_output.txout.value.to_sat(),
                    keychain,
                    derivation_index: local_output.derivation_index,
                    address,
                    is_confirmed,
                    confirmation_height,
                    label,
                    effective_label,
                    is_auto,
                    pending_psbt_ids,
                    mempool_spending_txid: None,
                }
            })
            .collect();

        // Ghost UTXOs: coins spent by unconfirmed (mempool) transactions.
        // BDK removes these from list_unspent() as soon as the spending tx is known,
        // but we reconstruct them from the tx graph so they remain visible as "Spending".
        let existing: std::collections::HashSet<String> = utxos
            .iter()
            .map(|u| format!("{}:{}", u.txid, u.vout))
            .collect();

        for canonical_tx in wallet.transactions() {
            if !matches!(
                canonical_tx.chain_position,
                bdk_wallet::chain::ChainPosition::Unconfirmed { .. }
            ) {
                continue;
            }
            let spending_txid = canonical_tx.tx_node.txid.to_string();
            for txin in &canonical_tx.tx_node.tx.input {
                if txin.previous_output.is_null() {
                    continue;
                }
                let outpoint_key = format!(
                    "{}:{}",
                    txin.previous_output.txid, txin.previous_output.vout
                );
                if existing.contains(&outpoint_key) {
                    continue;
                }
                // Resolve the previous output via the tx graph.
                let Some(txout) = wallet.tx_graph().get_txout(txin.previous_output) else {
                    continue;
                };
                // Check whether this scriptpubkey belongs to one of our keychains.
                let Some((keychain_kind, index)) =
                    wallet.spk_index().index_of_spk(txout.script_pubkey.clone())
                else {
                    continue;
                };
                let api_keychain = match keychain_kind {
                    bdk_wallet::KeychainKind::External => APIKeychain::External,
                    bdk_wallet::KeychainKind::Internal => APIKeychain::Internal,
                };
                let address = wallet
                    .peek_address(*keychain_kind, *index)
                    .address
                    .to_string();

                // Determine whether the creating tx was confirmed.
                let conf_height = tx_conf_heights
                    .get(&txin.previous_output.txid)
                    .copied()
                    .flatten();

                let (label, effective_label, is_auto) =
                    resolve_label(coin_labels.get(&outpoint_key).cloned());
                let pending_psbt_ids = pending_map.get(&outpoint_key).cloned().unwrap_or_default();

                utxos.push(APIUtxo {
                    txid: txin.previous_output.txid.to_string(),
                    vout: txin.previous_output.vout,
                    value_sat: txout.value.to_sat(),
                    keychain: api_keychain,
                    derivation_index: *index,
                    address,
                    is_confirmed: conf_height.is_some(),
                    confirmation_height: conf_height,
                    label,
                    effective_label,
                    is_auto,
                    pending_psbt_ids,
                    mempool_spending_txid: Some(spending_txid.clone()),
                });
            }
        }

        utxos.sort_by(|a, b| b.value_sat.cmp(&a.value_sat).then(a.txid.cmp(&b.txid)));
        Ok(utxos)
    }

    // -----------------------------------------------------------------------
    // Detail APIs (entity + related entities for detail dialogs)
    // -----------------------------------------------------------------------

    /// Return full detail for a transaction: the tx plus related UTXOs, input addresses,
    /// and output addresses. External input transactions not in BDK's graph are fetched
    /// from Electrum (using the URL stored from the last sync).
    pub fn get_tx_details(&self, txid: String) -> Result<APITxDetails> {
        use bdk_wallet::bitcoin::Txid;
        use std::collections::{HashMap, HashSet};

        // Phase 1: identify input txids absent from BDK's data (brief lock scope).
        let (missing_txids, electrum_url) = {
            let core = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
            let wallet = &core.wallet;
            let canonical_tx = wallet
                .transactions()
                .find(|t| t.tx_node.txid.to_string() == txid)
                .ok_or_else(|| anyhow::anyhow!("transaction not found: {}", txid))?;
            let known_txids: HashSet<Txid> =
                wallet.transactions().map(|t| t.tx_node.txid).collect();
            let missing: Vec<Txid> = canonical_tx
                .tx_node
                .tx
                .input
                .iter()
                .filter(|i| !i.previous_output.is_null())
                .filter(|i| {
                    !known_txids.contains(&i.previous_output.txid)
                        && wallet.tx_graph().get_txout(i.previous_output).is_none()
                })
                .map(|i| i.previous_output.txid)
                .collect::<HashSet<_>>()
                .into_iter()
                .collect();
            let url = self
                .electrum_url
                .lock()
                .map(|u| (*u).clone())
                .unwrap_or_default();
            (missing, url)
        }; // inner lock released here

        // Phase 2: fetch missing input transactions from Electrum (no lock held).
        let fetched_txs: HashMap<String, bdk_wallet::bitcoin::Transaction> = {
            let mut map = HashMap::new();
            if !missing_txids.is_empty() && !electrum_url.is_empty() {
                use bdk_electrum::electrum_client::ElectrumApi;
                if let Ok(client) = bdk_electrum::electrum_client::Client::new(&electrum_url) {
                    for id in missing_txids {
                        if let Ok(tx) = client.transaction_get(&id) {
                            map.insert(id.to_string(), tx);
                        }
                    }
                }
            }
            map
        };

        // Phase 3: full processing (re-acquire lock).
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let tx_labels = get_all_tx_labels_with_flag(&core.conn).unwrap_or_default();

        let canonical_tx = wallet
            .transactions()
            .find(|t| t.tx_node.txid.to_string() == txid)
            .ok_or_else(|| anyhow::anyhow!("transaction not found: {}", txid))?;

        let tx_ref = &canonical_tx.tx_node.tx;
        let (confirmation_height, confirmation_time) =
            if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                &canonical_tx.chain_position
            {
                (Some(anchor.block_id.height), Some(anchor.confirmation_time))
            } else {
                (None, None)
            };
        let (sent, received) = wallet.sent_and_received(tx_ref);
        let fee = wallet.calculate_fee(tx_ref).ok().map(|f| f.to_sat());

        let (label, effective_label, is_auto) = resolve_label(tx_labels.get(&txid).cloned());

        let tx = APITransaction {
            txid: txid.clone(),
            received: received.to_sat(),
            sent: sent.to_sat(),
            fee,
            confirmation_height,
            confirmation_time,
            label,
            effective_label,
            is_auto,
        };

        // Unspent output coins created by this transaction.
        let coin_labels = get_all_coin_labels_with_flag(&core.conn).unwrap_or_default();
        let related_utxos = wallet
            .list_unspent()
            .filter(|u| u.outpoint.txid.to_string() == txid)
            .map(|u| {
                let address = wallet
                    .peek_address(u.keychain, u.derivation_index)
                    .address
                    .to_string();
                let outpoint_key = format!("{}:{}", u.outpoint.txid, u.outpoint.vout);
                let (_, effective_label, is_auto) =
                    resolve_label(coin_labels.get(&outpoint_key).cloned());
                APIRelatedUtxo {
                    txid: u.outpoint.txid.to_string(),
                    vout: u.outpoint.vout,
                    address: address.clone(),
                    value_sat: u.txout.value.to_sat(),
                    effective_label,
                    is_auto,
                }
            })
            .collect();

        let address_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let spk_index = wallet.spk_index();
        let network = wallet.network();
        let tx_map: HashMap<String, _> = wallet
            .transactions()
            .map(|t| (t.tx_node.txid.to_string(), t))
            .collect();

        // Resolve a previous output: BDK graph → TxGraph TxOut → Electrum-fetched tx.
        let resolve_prev = |outpoint: bdk_wallet::bitcoin::OutPoint|
            -> Option<(bdk_wallet::bitcoin::ScriptBuf, u64)> {
            let prev_txid = outpoint.txid.to_string();
            let prev_vout = outpoint.vout as usize;
            if let Some(o) = tx_map.get(&prev_txid).and_then(|t| t.tx_node.tx.output.get(prev_vout)) {
                return Some((o.script_pubkey.clone(), o.value.to_sat()));
            }
            if let Some(txout) = wallet.tx_graph().get_txout(outpoint) {
                return Some((txout.script_pubkey.clone(), txout.value.to_sat()));
            }
            fetched_txs
                .get(&prev_txid)?
                .output
                .get(prev_vout)
                .map(|o| (o.script_pubkey.clone(), o.value.to_sat()))
        };

        // Input addresses.
        let input_addresses: Vec<APIRelatedAddress> = tx_ref
            .input
            .iter()
            .map(|input| {
                if input.previous_output.is_null() {
                    return APIRelatedAddress {
                        address: "Coinbase".to_string(),
                        value_sat: None,
                        effective_label: None,
                        is_auto: false,
                        is_mine: false,
                    };
                }
                let prev_txid = input.previous_output.txid.to_string();
                let Some((spk, value)) = resolve_prev(input.previous_output) else {
                    return APIRelatedAddress {
                        address: format!("{}…:{}", &prev_txid[..8], input.previous_output.vout),
                        value_sat: None,
                        effective_label: None,
                        is_auto: false,
                        is_mine: false,
                    };
                };
                if let Some((k, i)) = spk_index.index_of_spk(spk.clone()) {
                    let addr_str = wallet.peek_address(*k, *i).address.to_string();
                    let (_, effective_label, is_auto) =
                        resolve_label(address_labels.get(&addr_str).cloned());
                    APIRelatedAddress {
                        address: addr_str,
                        value_sat: Some(value),
                        effective_label,
                        is_auto,
                        is_mine: true,
                    }
                } else {
                    let addr_str = bdk_wallet::bitcoin::Address::from_script(&spk, network)
                        .map(|a| a.to_string())
                        .unwrap_or_else(|_| "undecodeable script".to_string());
                    APIRelatedAddress {
                        address: addr_str,
                        value_sat: Some(value),
                        effective_label: None,
                        is_auto: false,
                        is_mine: false,
                    }
                }
            })
            .collect();

        // Output addresses.
        let output_addresses: Vec<APIRelatedAddress> = tx_ref
            .output
            .iter()
            .map(|output| {
                if let Some((k, i)) = spk_index.index_of_spk(output.script_pubkey.clone()) {
                    let addr_str = wallet.peek_address(*k, *i).address.to_string();
                    let (_, effective_label, is_auto) =
                        resolve_label(address_labels.get(&addr_str).cloned());
                    APIRelatedAddress {
                        address: addr_str,
                        value_sat: Some(output.value.to_sat()),
                        effective_label,
                        is_auto,
                        is_mine: true,
                    }
                } else {
                    let addr_str =
                        bdk_wallet::bitcoin::Address::from_script(&output.script_pubkey, network)
                            .map(|a| a.to_string())
                            .unwrap_or_else(|_| "undecodeable script".to_string());
                    APIRelatedAddress {
                        address: addr_str,
                        value_sat: Some(output.value.to_sat()),
                        effective_label: None,
                        is_auto: false,
                        is_mine: false,
                    }
                }
            })
            .collect();

        Ok(APITxDetails {
            tx,
            related_utxos,
            input_addresses,
            output_addresses,
        })
    }

    /// Return RBF replacement constraints for a mempool tx spending one of our UTXOs.
    /// Fetches parent txs from Electrum when fee cannot be determined from the wallet graph.
    pub async fn get_rbf_info(&self, spending_txid: String) -> Result<APIRbfInfo> {
        use bdk_wallet::bitcoin::Txid;
        use std::collections::{HashMap, HashSet};

        // Phase 1: retrieve the tx + attempt fee calculation (brief lock).
        let (tx, fee_opt, electrum_url) = {
            let core = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
            let txid: Txid = spending_txid
                .parse()
                .map_err(|e| anyhow::anyhow!("invalid txid: {}", e))?;
            let tx = core
                .wallet
                .tx_graph()
                .get_tx(txid)
                .ok_or_else(|| anyhow::anyhow!("spending tx not found: {}", spending_txid))?
                .as_ref()
                .clone();
            let fee_opt = core.wallet.tx_graph().calculate_fee(&tx).ok();
            let url = self
                .electrum_url
                .lock()
                .map(|u| (*u).clone())
                .unwrap_or_default();
            (tx, fee_opt, url)
        };

        // Phase 2: if fee unknown (external inputs), fetch parent txs from Electrum.
        let fee_sat = match fee_opt {
            Some(f) => f.to_sat(),
            None => {
                // Collect outpoints whose parent txs are missing from the wallet graph.
                let missing_txids: Vec<Txid> = {
                    let core = self
                        .inner
                        .lock()
                        .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
                    tx.input
                        .iter()
                        .filter(|i| !i.previous_output.is_null())
                        .filter(|i| {
                            core.wallet
                                .tx_graph()
                                .get_txout(i.previous_output)
                                .is_none()
                        })
                        .map(|i| i.previous_output.txid)
                        .collect::<HashSet<_>>()
                        .into_iter()
                        .collect()
                };

                let mut parent_txs: HashMap<Txid, bdk_wallet::bitcoin::Transaction> =
                    HashMap::new();
                if !missing_txids.is_empty() && !electrum_url.is_empty() {
                    use bdk_electrum::electrum_client::ElectrumApi;
                    if let Ok(client) = bdk_electrum::electrum_client::Client::new(&electrum_url) {
                        for id in &missing_txids {
                            if let Ok(t) = client.transaction_get(id) {
                                parent_txs.insert(*id, t);
                            }
                        }
                    }
                }

                // Compute fee = sum(inputs) - sum(outputs).
                let input_sum: u64 = {
                    let core = self
                        .inner
                        .lock()
                        .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
                    let mut sum = 0u64;
                    for inp in &tx.input {
                        if inp.previous_output.is_null() {
                            continue;
                        }
                        let val = core
                            .wallet
                            .tx_graph()
                            .get_txout(inp.previous_output)
                            .map(|o| o.value.to_sat())
                            .or_else(|| {
                                parent_txs
                                    .get(&inp.previous_output.txid)
                                    .and_then(|t| t.output.get(inp.previous_output.vout as usize))
                                    .map(|o| o.value.to_sat())
                            })
                            .ok_or_else(|| {
                                anyhow::anyhow!("input value unknown for RBF fee calc")
                            })?;
                        sum += val;
                    }
                    sum
                };
                let output_sum: u64 = tx.output.iter().map(|o| o.value.to_sat()).sum();
                input_sum.saturating_sub(output_sum)
            }
        };

        let vsize = tx.weight().to_vbytes_ceil() as u32;
        let fee_rate = if vsize > 0 {
            fee_sat as f64 / vsize as f64
        } else {
            1.0
        };
        Ok(APIRbfInfo {
            orig_fee_sat: fee_sat,
            orig_vsize: vsize,
            orig_fee_rate_sat_per_vb: fee_rate,
            // BIP-125 Rule 4 approx (orig_vsize proxy for new_vsize; Dart refines).
            min_fee_sat: fee_sat + vsize as u64,
            // ImprovesFeerateDiagram constraint: new_rate must strictly exceed orig_rate.
            // Fixed — independent of new tx size. Dart validates with strict >.
            min_fee_rate_sat_per_vb: fee_rate,
        })
    }

    /// Return full detail for a UTXO: the UTXO plus the explicit labels of its cluster peers.
    pub fn get_utxo_details(&self, txid: String, vout: u32) -> Result<APIUtxoDetails> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let coin_labels = get_all_coin_labels_with_flag(&core.conn).unwrap_or_default();
        let address_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let tx_labels = get_all_tx_labels_with_flag(&core.conn).unwrap_or_default();

        let local_output = wallet
            .list_unspent()
            .find(|u| u.outpoint.txid.to_string() == txid && u.outpoint.vout == vout)
            .ok_or_else(|| anyhow::anyhow!("UTXO not found: {}:{}", txid, vout))?;

        let keychain = match local_output.keychain {
            bdk_wallet::KeychainKind::External => APIKeychain::External,
            bdk_wallet::KeychainKind::Internal => APIKeychain::Internal,
        };
        let address = wallet
            .peek_address(local_output.keychain, local_output.derivation_index)
            .address
            .to_string();
        let is_confirmed = matches!(
            &local_output.chain_position,
            bdk_wallet::chain::ChainPosition::Confirmed { .. }
        );
        let confirmation_height =
            if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                &local_output.chain_position
            {
                Some(anchor.block_id.height)
            } else {
                None
            };
        let outpoint_key = format!("{}:{}", txid, vout);

        let (label, effective_label, is_auto) =
            resolve_label(coin_labels.get(&outpoint_key).cloned());

        let utxo_address = address.clone();
        let utxo = APIUtxo {
            txid: txid.clone(),
            vout,
            value_sat: local_output.txout.value.to_sat(),
            keychain,
            derivation_index: local_output.derivation_index,
            address: utxo_address,
            is_confirmed,
            confirmation_height,
            label,
            effective_label,
            is_auto,
            pending_psbt_ids: vec![],
            mempool_spending_txid: None,
        };

        // The transaction that created this UTXO
        let creating_tx = wallet
            .transactions()
            .find(|t| t.tx_node.txid.to_string() == txid)
            .map(|canonical_tx| {
                let tx_ref = &canonical_tx.tx_node.tx;
                let fee = wallet.calculate_fee(tx_ref).ok().map(|f| f.to_sat());
                let conf_height =
                    if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                        &canonical_tx.chain_position
                    {
                        Some(anchor.block_id.height)
                    } else {
                        None
                    };
                let (_, effective_label, is_auto) = resolve_label(tx_labels.get(&txid).cloned());
                // This is the creating tx: the coin is the output, nothing is spent yet.
                APIRelatedTx {
                    txid: txid.clone(),
                    effective_label,
                    is_auto,
                    confirmation_height: conf_height,
                    addr_received: local_output.txout.value.to_sat(),
                    addr_spent: 0,
                    fee,
                }
            })
            .ok_or_else(|| anyhow::anyhow!("creating transaction not found: {}", txid))?;

        let (_, address_effective_label, address_label_is_auto) =
            resolve_label(address_labels.get(&address).cloned());

        Ok(APIUtxoDetails {
            utxo,
            address_effective_label,
            address_label_is_auto,
            creating_tx,
        })
    }

    /// Return full detail for an address: the address plus its unspent UTXOs.
    pub fn get_address_details(&self, address: String) -> Result<APIAddressDetails> {
        use bdk_wallet::KeychainKind;
        use std::collections::HashSet;

        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let address_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let coin_labels = get_all_coin_labels_with_flag(&core.conn).unwrap_or_default();
        let tx_labels = get_all_tx_labels_with_flag(&core.conn).unwrap_or_default();

        // Determine keychain + index for this address
        let spk_index = wallet.spk_index();
        let (keychain, idx) = [KeychainKind::External, KeychainKind::Internal]
            .iter()
            .find_map(|&k| {
                spk_index
                    .revealed_keychain_spks(k)
                    .find(|(i, _)| wallet.peek_address(k, *i).address.to_string() == address)
                    .map(|(i, _)| (k, i))
            })
            .ok_or_else(|| anyhow::anyhow!("address not found: {}", address))?;

        let api_keychain = match keychain {
            KeychainKind::External => APIKeychain::External,
            KeychainKind::Internal => APIKeychain::Internal,
        };

        // Balance
        let balance_sat: u64 = wallet
            .list_unspent()
            .filter(|u| u.keychain == keychain && u.derivation_index == idx)
            .map(|u| u.txout.value.to_sat())
            .sum();

        // All transactions that sent to OR spent from this address.
        // Pass 1: outputs to our address → receiving txids + outpoints we own.
        let mut related_txids: HashSet<String> = HashSet::new();
        let mut our_outpoints: HashSet<(String, u32)> = HashSet::new();
        for canonical_tx in wallet.transactions() {
            for (vout_idx, output) in canonical_tx.tx_node.tx.output.iter().enumerate() {
                if let Some((k, i)) = spk_index.index_of_spk(output.script_pubkey.clone()) {
                    if *k == keychain && *i == idx {
                        let txid_str = canonical_tx.tx_node.txid.to_string();
                        related_txids.insert(txid_str.clone());
                        our_outpoints.insert((txid_str, vout_idx as u32));
                    }
                }
            }
        }
        // Pass 2: inputs spending our outpoints → spending txids.
        for canonical_tx in wallet.transactions() {
            for input in canonical_tx.tx_node.tx.input.iter() {
                let prev = (
                    input.previous_output.txid.to_string(),
                    input.previous_output.vout,
                );
                if our_outpoints.contains(&prev) {
                    related_txids.insert(canonical_tx.tx_node.txid.to_string());
                }
            }
        }

        let used = !related_txids.is_empty();
        let tx_count = related_txids.len() as u32;

        let (label, effective_label, is_auto) =
            resolve_label(address_labels.get(&address).cloned());

        let addr = APIAddress {
            address: address.clone(),
            index: idx,
            keychain: api_keychain,
            balance_sat,
            is_used: used,
            tx_count,
            label,
            effective_label,
            is_auto,
        };

        // Related UTXOs at this address
        let related_utxos = wallet
            .list_unspent()
            .filter(|u| u.keychain == keychain && u.derivation_index == idx)
            .map(|u| {
                let outpoint_key = format!("{}:{}", u.outpoint.txid, u.outpoint.vout);
                let txid = u.outpoint.txid.to_string();
                let (_, effective_label, is_auto) =
                    resolve_label(coin_labels.get(&outpoint_key).cloned());
                APIRelatedUtxo {
                    txid: txid.clone(),
                    vout: u.outpoint.vout,
                    address: address.clone(),
                    value_sat: u.txout.value.to_sat(),
                    effective_label,
                    is_auto,
                }
            })
            .collect();

        let mut related_txs: Vec<APIRelatedTx> = wallet
            .transactions()
            .filter(|t| related_txids.contains(&t.tx_node.txid.to_string()))
            .map(|canonical_tx| {
                let tx_ref = &canonical_tx.tx_node.tx;
                let txid_str = canonical_tx.tx_node.txid.to_string();
                let fee = wallet.calculate_fee(tx_ref).ok().map(|f| f.to_sat());
                let conf_height =
                    if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                        &canonical_tx.chain_position
                    {
                        Some(anchor.block_id.height)
                    } else {
                        None
                    };
                // Sats going to this address in this tx.
                let addr_received: u64 = tx_ref
                    .output
                    .iter()
                    .filter(|out| {
                        spk_index
                            .index_of_spk(out.script_pubkey.clone())
                            .map(|(k, i)| *k == keychain && *i == idx)
                            .unwrap_or(false)
                    })
                    .map(|out| out.value.to_sat())
                    .sum();
                // Sats leaving this address in this tx (inputs that were our outpoints).
                let addr_spent: u64 = tx_ref
                    .input
                    .iter()
                    .filter_map(|inp| {
                        let prev = (
                            inp.previous_output.txid.to_string(),
                            inp.previous_output.vout,
                        );
                        if our_outpoints.contains(&prev) {
                            wallet
                                .tx_graph()
                                .get_txout(inp.previous_output)
                                .map(|txout| txout.value.to_sat())
                        } else {
                            None
                        }
                    })
                    .sum();
                let (_, effective_label, is_auto) =
                    resolve_label(tx_labels.get(&txid_str).cloned());
                APIRelatedTx {
                    txid: txid_str.clone(),
                    effective_label,
                    is_auto,
                    confirmation_height: conf_height,
                    addr_received,
                    addr_spent,
                    fee,
                }
            })
            .collect();

        // Unconfirmed first, then by descending height
        related_txs.sort_by(
            |a, b| match (a.confirmation_height, b.confirmation_height) {
                (None, None) => std::cmp::Ordering::Equal,
                (None, Some(_)) => std::cmp::Ordering::Less,
                (Some(_), None) => std::cmp::Ordering::Greater,
                (Some(ha), Some(hb)) => hb.cmp(&ha),
            },
        );

        Ok(APIAddressDetails {
            address: addr,
            related_utxos,
            related_txs,
        })
    }

    /// Reveal `count` new addresses for the given keychain beyond those already revealed,
    /// then persist the wallet. Returns the new total number of revealed addresses.
    #[frb(sync)]
    pub fn reveal_more_addresses(&self, keychain: APIKeychain, count: u32) -> Result<u32> {
        use bdk_wallet::KeychainKind;

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let bdk_keychain = match keychain {
            APIKeychain::External => KeychainKind::External,
            APIKeychain::Internal => KeychainKind::Internal,
        };

        for _ in 0..count {
            core.wallet.reveal_next_address(bdk_keychain);
        }
        core.persist()?;

        let total = core
            .wallet
            .spk_index()
            .revealed_keychain_spks(bdk_keychain)
            .count() as u32;
        Ok(total)
    }

    /// Persist a label for an address. Pass an empty string to remove it.
    /// Automatically propagates to related entities (transactions and UTXOs).
    /// Clearing an inherited (auto) label is a no-op.
    #[frb(sync)]
    pub fn set_address_label(&self, address: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        if label.is_empty() {
            match get_address_label_with_flag(&core.conn, &address)? {
                Some((_, false)) => {
                    // Explicit label: delete the row and cascade.
                    db_set_address_label(&core.conn, &address, "", false, None)?;
                    cascade_delete_label(&core.conn, EntityType::Address, &address)?;
                }
                Some((_, true)) => {
                    // Inherited auto-label: no-op — only the source can clear it.
                }
                None => {} // Nothing to do.
            }
        } else {
            db_set_address_label(&core.conn, &address, &label, false, None)?;
            propagate_label(
                &core.conn,
                &core.wallet,
                EntityType::Address,
                &address,
                &label,
            )?;
        }
        Ok(())
    }

    /// Persist a label for a coin (UTXO) by outpoint. Pass an empty string to remove it.
    /// Automatically propagates to related entities (transaction and address).
    /// Clearing an inherited (auto) label is a no-op.
    #[frb(sync)]
    pub fn set_coin_label(&self, txid: String, vout: u32, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let outpoint = format!("{}:{}", txid, vout);

        if label.is_empty() {
            match get_coin_label_with_flag(&core.conn, &outpoint)? {
                Some((_, false)) => {
                    // Explicit label: delete the row and cascade.
                    db_set_coin_label(&core.conn, &outpoint, "", false, None)?;
                    cascade_delete_label(&core.conn, EntityType::Coin, &outpoint)?;
                }
                Some((_, true)) => {
                    // Inherited auto-label: no-op — only the source can clear it.
                }
                None => {} // Nothing to do.
            }
        } else {
            db_set_coin_label(&core.conn, &outpoint, &label, false, None)?;
            propagate_label(
                &core.conn,
                &core.wallet,
                EntityType::Coin,
                &outpoint,
                &label,
            )?;
        }
        Ok(())
    }

    /// Return the current best block height from the local chain (0 if not yet synced).
    pub fn get_tip_height(&self) -> Result<u32> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        Ok(core.wallet.latest_checkpoint().block_id().height)
    }

    /// Return all key labels (mfp → label).
    pub fn get_key_labels(&self) -> Result<Vec<APIKeyLabel>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let map = get_all_key_labels(&core.conn).unwrap_or_default();
        Ok(map
            .into_iter()
            .map(|(mfp, label)| APIKeyLabel { mfp, label })
            .collect())
    }

    /// Persist a label for a key by master fingerprint. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_key_label(&self, mfp: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_key_label(&core.conn, &mfp, &label)
    }

    /// Return all spend-path labels (rust_id → label).
    pub fn get_path_labels(&self) -> Result<Vec<APIPathLabel>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let map = get_all_path_labels(&core.conn).unwrap_or_default();
        Ok(map
            .into_iter()
            .map(|(rust_id, label)| APIPathLabel { rust_id, label })
            .collect())
    }

    /// Persist a label for a spend path by rust_id. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_path_label(&self, rust_id: u32, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_path_label(&core.conn, rust_id, &label)
    }

    /// Repropagate all existing explicit labels to their related entities.
    /// Useful after imports or migrations. Clears all auto labels first.
    #[frb(sync)]
    pub fn repropagate_all_labels(&self) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        // Clear all auto-labels (identified by a non-NULL source_entity).
        core.conn
            .execute("DELETE FROM tx_labels WHERE source_entity IS NOT NULL", [])?;
        core.conn.execute(
            "DELETE FROM address_labels WHERE source_entity IS NOT NULL",
            [],
        )?;
        core.conn.execute(
            "DELETE FROM coin_labels WHERE source_entity IS NOT NULL",
            [],
        )?;

        // Re-propagate only explicit labels.
        let tx_labels = get_all_tx_labels_with_flag(&core.conn)?;
        for (txid, (label, is_auto)) in tx_labels {
            if !is_auto && !label.is_empty() {
                propagate_label(&core.conn, &core.wallet, EntityType::Tx, &txid, &label)?;
            }
        }

        let address_labels = get_all_address_labels_with_flag(&core.conn)?;
        for (address, (label, is_auto)) in address_labels {
            if !is_auto && !label.is_empty() {
                propagate_label(
                    &core.conn,
                    &core.wallet,
                    EntityType::Address,
                    &address,
                    &label,
                )?;
            }
        }

        let coin_labels = get_all_coin_labels_with_flag(&core.conn)?;
        for (outpoint, (label, is_auto)) in coin_labels {
            if !is_auto && !label.is_empty() {
                propagate_label(
                    &core.conn,
                    &core.wallet,
                    EntityType::Coin,
                    &outpoint,
                    &label,
                )?;
            }
        }

        Ok(())
    }

    // -----------------------------------------------------------------------
    // BIP-329 label import / export
    // -----------------------------------------------------------------------

    /// Export all explicit (non-auto) labels to BIP-329 JSONL format.
    #[frb(sync)]
    pub fn export_bip329(&self) -> Result<Vec<String>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let conn = &core.conn;
        let mut lines: Vec<String> = Vec::new();

        for (txid, (label, is_auto)) in get_all_tx_labels_with_flag(conn)? {
            if !is_auto && !label.is_empty() {
                lines.push(serde_json::json!({"type":"tx","ref":txid,"label":label}).to_string());
            }
        }
        for (address, (label, is_auto)) in get_all_address_labels_with_flag(conn)? {
            if !is_auto && !label.is_empty() {
                lines.push(
                    serde_json::json!({"type":"addr","ref":address,"label":label}).to_string(),
                );
            }
        }
        for (outpoint, (label, is_auto)) in get_all_coin_labels_with_flag(conn)? {
            if !is_auto && !label.is_empty() {
                lines.push(
                    serde_json::json!({"type":"output","ref":outpoint,"label":label}).to_string(),
                );
            }
        }

        // Export key labels as "xpub" type using mfp→xpub map from descriptor.
        let wallet_info = read_wallet_info(conn)?;
        let mfp_to_xpub = extract_xpub_mfp_map(&wallet_info.descriptor);
        for (mfp, label) in get_all_key_labels(conn)? {
            if !label.is_empty() {
                if let Some(xpub) = mfp_to_xpub.get(&mfp) {
                    lines.push(
                        serde_json::json!({"type":"xpub","ref":xpub,"label":label}).to_string(),
                    );
                }
            }
        }

        Ok(lines)
    }

    /// Import labels from BIP-329 JSONL. Sets all as explicit, then re-propagates.
    /// Malformed lines and unknown types are silently skipped.
    #[frb(sync)]
    pub fn import_bip329(&self, lines: Vec<String>) -> Result<()> {
        // Phase 1: apply under lock
        {
            let core = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
            let conn = &core.conn;

            // Build xpub→mfp reverse map from descriptor.
            let wallet_info = read_wallet_info(conn)?;
            let xpub_to_mfp: std::collections::HashMap<String, String> =
                extract_xpub_mfp_map(&wallet_info.descriptor)
                    .into_iter()
                    .map(|(mfp, xpub)| (xpub, mfp))
                    .collect();

            for line in &lines {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                let Ok(obj) = serde_json::from_str::<serde_json::Value>(trimmed) else {
                    continue;
                };
                let Some(t) = obj.get("type").and_then(|v| v.as_str()) else {
                    continue;
                };
                let Some(r) = obj.get("ref").and_then(|v| v.as_str()) else {
                    continue;
                };
                let Some(l) = obj.get("label").and_then(|v| v.as_str()) else {
                    continue;
                };
                if l.is_empty() {
                    continue;
                }
                match t {
                    "tx" => db_set_tx_label(conn, r, l, false, None)?,
                    "addr" => db_set_address_label(conn, r, l, false, None)?,
                    "output" => db_set_coin_label(conn, r, l, false, None)?,
                    "xpub" => {
                        if let Some(mfp) = xpub_to_mfp.get(r) {
                            db_set_key_label(conn, mfp, l)?
                        } else {
                            continue; // xpub not in this wallet's descriptor — ignore
                        }
                    }
                    _ => continue,
                }
            }
        } // lock released

        // Phase 2: re-propagate (re-acquires lock internally)
        self.repropagate_all_labels()
    }

    // -----------------------------------------------------------------------
    // PSBT / coin-control
    // -----------------------------------------------------------------------

    /// Build an unsigned PSBT with optional coin control and spend-path selection.
    ///
    /// * `selected_utxos` — if non-empty, only those coins are used.
    ///   Empty = BDK automatic coin selection.
    /// * `policy_path`    — spend-path branch selections from [APISpendPath.policyPath].
    /// * `spend_path_id`  — rust_id of the selected spend path (stored for reference).
    /// * `threshold`      — required signatures (from the spend path).
    /// * `mfps`           — master fingerprints of keys in the spend path.
    #[frb(sync)]
    #[allow(clippy::too_many_arguments)]
    pub fn create_psbt(
        &self,
        recipient_address: String,
        amount_sat: u64,
        fee_rate_sat_per_vb: f64,
        selected_utxos: Vec<APICoinControl>,
        policy_path: Vec<APIPolicyPath>,
        spend_path_id: u32,
        threshold: u32,
        mfps: Vec<String>,
        send_max: bool,
    ) -> Result<APIPsbtInfo> {
        use bdk_wallet::bitcoin::{Address, Amount, FeeRate, OutPoint, Txid};
        use bdk_wallet::KeychainKind;
        use std::collections::BTreeMap;
        use std::str::FromStr;

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let network = core.wallet.network();
        let address = Address::from_str(&recipient_address)?.require_network(network)?;

        // float sat/vB → sat/kwu (1 sat/vB = 250 sat/kwu). Minimum 1 sat/kwu.
        let sat_per_kwu = ((fee_rate_sat_per_vb * 250.0).ceil() as u64).max(1);
        let fee_rate = FeeRate::from_sat_per_kwu(sat_per_kwu);

        let policy_map: BTreeMap<String, Vec<usize>> = policy_path
            .into_iter()
            .map(|pp| {
                (
                    pp.policy_id,
                    pp.path.into_iter().map(|x| x as usize).collect(),
                )
            })
            .collect();

        // Pre-resolve each selected UTXO before the builder borrows the wallet.
        // Coins spent by a mempool tx are absent from BDK's internal UTXO set;
        // we reconstruct them as foreign UTXOs from the tx graph (full-RBF).
        struct ResolvedUtxo {
            outpoint: OutPoint,
            /// Some → foreign (mempool) UTXO; None → normal internal UTXO.
            foreign: Option<(
                bdk_wallet::bitcoin::psbt::Input,
                bdk_wallet::bitcoin::Weight,
            )>,
        }
        let mut resolved: Vec<ResolvedUtxo> = Vec::with_capacity(selected_utxos.len());
        for coin in &selected_utxos {
            let outpoint = OutPoint::new(Txid::from_str(&coin.txid)?, coin.vout);
            if core.wallet.get_utxo(outpoint).is_some() {
                resolved.push(ResolvedUtxo {
                    outpoint,
                    foreign: None,
                });
            } else {
                // Not in the internal UTXO set — try the tx graph (mempool coin).
                let txout = core
                    .wallet
                    .tx_graph()
                    .get_txout(outpoint)
                    .ok_or_else(|| {
                        anyhow::anyhow!(
                            "UTXO not found in wallet or tx graph: {}:{}",
                            coin.txid,
                            coin.vout
                        )
                    })?
                    .clone();
                let keychain = core
                    .wallet
                    .spk_index()
                    .index_of_spk(txout.script_pubkey.clone())
                    .map(|(k, _)| *k)
                    .unwrap_or(KeychainKind::External);
                // BIP-174: non-taproot segwit inputs (P2WPKH, P2WSH) must include
                // non_witness_utxo (full previous tx) in addition to witness_utxo.
                let non_witness_utxo = core
                    .wallet
                    .tx_graph()
                    .get_tx(outpoint.txid)
                    .map(|tx| tx.as_ref().clone());
                let psbt_input = bdk_wallet::bitcoin::psbt::Input {
                    witness_utxo: Some(txout),
                    non_witness_utxo,
                    ..Default::default()
                };
                let satisfaction_weight = core
                    .wallet
                    .public_descriptor(keychain)
                    .max_weight_to_satisfy()
                    .unwrap_or(bdk_wallet::bitcoin::Weight::from_wu(500));
                resolved.push(ResolvedUtxo {
                    outpoint,
                    foreign: Some((psbt_input, satisfaction_weight)),
                });
            }
        }

        let mut builder = core.wallet.build_tx();
        builder.fee_rate(fee_rate);

        if send_max {
            // Drain all selected (or all wallet) funds to recipient, no change output.
            builder.drain_to(address.script_pubkey());
            if !resolved.is_empty() {
                for r in &resolved {
                    if let Some((psbt_input, weight)) = &r.foreign {
                        builder.add_foreign_utxo(r.outpoint, psbt_input.clone(), *weight)?;
                    } else {
                        builder.add_utxo(r.outpoint)?;
                    }
                }
                builder.manually_selected_only();
            } else {
                builder.drain_wallet();
            }
        } else {
            let amount = Amount::from_sat(amount_sat);
            builder.add_recipient(address.script_pubkey(), amount);
            if !resolved.is_empty() {
                for r in &resolved {
                    if let Some((psbt_input, weight)) = &r.foreign {
                        builder.add_foreign_utxo(r.outpoint, psbt_input.clone(), *weight)?;
                    } else {
                        builder.add_utxo(r.outpoint)?;
                    }
                }
                builder.manually_selected_only();
            }
        }

        if !policy_map.is_empty() {
            builder.policy_path(policy_map.clone(), KeychainKind::External);
            builder.policy_path(policy_map, KeychainKind::Internal);
        }

        let psbt = builder.finish()?;
        let fee_sat = psbt.fee()?.to_sat();
        let txid = psbt.unsigned_tx.compute_txid().to_string();
        let psbt_base64 = psbt_to_base64(&psbt);
        let recipient = address.to_string();

        // When send_max, read actual output amount from the PSBT.
        let actual_amount_sat = if send_max {
            let script = address.script_pubkey();
            psbt.unsigned_tx
                .output
                .iter()
                .find(|o| o.script_pubkey == script)
                .map(|o| o.value.to_sat())
                .unwrap_or(0)
        } else {
            amount_sat
        };

        let utxo_max_conf_height = psbt_max_utxo_conf_height(&core.wallet, &psbt);

        ensure_unsigned_txs_table(&core.conn)?;
        let id = insert_psbt(
            &core.conn,
            &psbt_base64,
            &txid,
            None,
            &recipient,
            actual_amount_sat,
            fee_sat,
            spend_path_id,
            threshold,
            &mfps,
        )?;

        let created_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs() as i64;
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let (effective_label, is_auto) = psbt_effective_label(&None, &recipient, &addr_labels);
        let is_self_transfer = is_psbt_self_transfer(&core.wallet, &recipient);

        Ok(APIPsbtInfo {
            id,
            psbt_base64,
            txid,
            label: None,
            effective_label,
            is_auto,
            is_self_transfer,
            created_at,
            recipient,
            amount_sat: actual_amount_sat,
            fee_sat,
            spend_path_id,
            threshold,
            mfps,
            utxo_max_conf_height,
            has_spent_inputs: false, // inputs were just selected and are confirmed unspent
        })
    }

    /// Return all saved unsigned PSBTs for this wallet, newest-first.
    pub fn list_psbts(&self) -> Result<Vec<APIPsbtInfo>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        ensure_unsigned_txs_table(&core.conn)?;
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let valid_outpoints = build_valid_outpoints(&core.wallet);
        Ok(list_psbt_rows(&core.conn)?
            .into_iter()
            .map(|row| row_to_api_psbt(row, &core.wallet, &addr_labels, &valid_outpoints))
            .collect())
    }

    /// Delete a saved PSBT by id.
    #[frb(sync)]
    pub fn delete_psbt(&self, id: i64) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        delete_psbt_row(&core.conn, id)
    }

    /// Set or clear the label for a saved PSBT. Pass an empty string to clear.
    #[frb(sync)]
    pub fn set_psbt_label(&self, id: i64, label: String) -> Result<APIPsbtInfo> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let new_label = if label.is_empty() {
            None
        } else {
            Some(label.as_str())
        };
        update_psbt_label(&core.conn, id, new_label)?;
        let row = get_psbt_row(&core.conn, id)?;
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let valid_outpoints = build_valid_outpoints(&core.wallet);
        Ok(row_to_api_psbt(
            row,
            &core.wallet,
            &addr_labels,
            &valid_outpoints,
        ))
    }

    /// Merge partial signatures from a signed PSBT into the stored one.
    ///
    /// The signed PSBT must refer to the same transaction (same inputs/outputs).
    /// Returns the updated info.
    #[frb(sync)]
    pub fn merge_psbt(&self, id: i64, signed_psbt_base64: String) -> Result<APIPsbtInfo> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let row = get_psbt_row(&core.conn, id)?;

        let mut existing = psbt_from_base64(&row.psbt)?;
        let signed = psbt_from_base64(&signed_psbt_base64)?;
        existing.combine(signed)?;

        let merged_base64 = psbt_to_base64(&existing);
        update_psbt_data(&core.conn, id, &merged_base64)?;

        let utxo_max_conf_height = psbt_max_utxo_conf_height(&core.wallet, &existing);
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let (effective_label, is_auto) =
            psbt_effective_label(&row.label, &row.recipient, &addr_labels);
        let is_self_transfer = is_psbt_self_transfer(&core.wallet, &row.recipient);
        let valid_outpoints = build_valid_outpoints(&core.wallet);
        let has_spent_inputs = existing.unsigned_tx.input.iter().any(|txin| {
            !txin.previous_output.is_null() && !valid_outpoints.contains(&txin.previous_output)
        });
        Ok(APIPsbtInfo {
            id,
            psbt_base64: merged_base64,
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
        })
    }

    /// Import a PSBT (base64) from an external source.
    ///
    /// If a record with the same unsigned txid already exists, the signatures are
    /// merged and the existing record is updated (`was_merged = true`).
    /// Otherwise a new record is created with metadata extracted from the PSBT.
    pub fn import_psbt(&self, psbt_base64: String) -> Result<APIImportPsbtResult> {
        use std::collections::HashSet;

        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        ensure_unsigned_txs_table(&core.conn)?;

        let imported = psbt_from_base64(&psbt_base64)?;
        let txid = imported.unsigned_tx.compute_txid().to_string();

        // Merge with existing record if txid matches.
        if let Some(row) = get_psbt_row_by_txid(&core.conn, &txid)? {
            let mut existing = psbt_from_base64(&row.psbt)?;
            existing.combine(imported)?;
            let merged_base64 = psbt_to_base64(&existing);
            update_psbt_data(&core.conn, row.id, &merged_base64)?;
            let utxo_max_conf_height = psbt_max_utxo_conf_height(&core.wallet, &existing);
            let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
            let (effective_label, is_auto) =
                psbt_effective_label(&row.label, &row.recipient, &addr_labels);
            let is_self_transfer = is_psbt_self_transfer(&core.wallet, &row.recipient);
            let valid_outpoints = build_valid_outpoints(&core.wallet);
            let has_spent_inputs = existing.unsigned_tx.input.iter().any(|txin| {
                !txin.previous_output.is_null() && !valid_outpoints.contains(&txin.previous_output)
            });
            return Ok(APIImportPsbtResult {
                psbt: APIPsbtInfo {
                    id: row.id,
                    psbt_base64: merged_base64,
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
                },
                was_merged: true,
            });
        }

        // New PSBT — extract metadata from the PSBT fields.
        let tx = &imported.unsigned_tx;

        // Collect unique MFPs from all inputs.
        let mut mfp_set: HashSet<String> = HashSet::new();
        for input in &imported.inputs {
            for (fp, _) in input.bip32_derivation.values() {
                mfp_set.insert(fp.to_string());
            }
            for (_, (fp, _)) in input.tap_key_origins.values() {
                mfp_set.insert(fp.to_string());
            }
        }
        let mfps: Vec<String> = mfp_set.into_iter().collect();

        // Identify external (non-wallet) outputs as the recipient.
        let external_outputs: Vec<_> = tx
            .output
            .iter()
            .filter(|o| !core.wallet.is_mine(o.script_pubkey.clone()))
            .collect();
        let (recipient, amount_sat) = if external_outputs.is_empty() {
            // Self-transfer or indeterminate — use first output.
            let addr = bdk_wallet::bitcoin::Address::from_script(
                &tx.output[0].script_pubkey,
                core.wallet.network(),
            )
            .map(|a| a.to_string())
            .unwrap_or_default();
            let amt: u64 = tx.output.iter().map(|o| o.value.to_sat()).sum();
            (addr, amt)
        } else {
            let addr = bdk_wallet::bitcoin::Address::from_script(
                &external_outputs[0].script_pubkey,
                core.wallet.network(),
            )
            .map(|a| a.to_string())
            .unwrap_or_default();
            let amt: u64 = external_outputs.iter().map(|o| o.value.to_sat()).sum();
            (addr, amt)
        };

        // Fee = witness_utxo input sum − output sum (best-effort).
        let input_sum: u64 = imported
            .inputs
            .iter()
            .filter_map(|i| i.witness_utxo.as_ref().map(|u| u.value.to_sat()))
            .sum();
        let output_sum: u64 = tx.output.iter().map(|o| o.value.to_sat()).sum();
        let fee_sat = input_sum.saturating_sub(output_sum);

        let threshold = mfps.len().max(1) as u32;
        let id = insert_psbt(
            &core.conn,
            &psbt_base64,
            &txid,
            None,
            &recipient,
            amount_sat,
            fee_sat,
            0,
            threshold,
            &mfps,
        )?;

        let created_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs() as i64;
        let utxo_max_conf_height = psbt_max_utxo_conf_height(&core.wallet, &imported);
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let (effective_label, is_auto) = psbt_effective_label(&None, &recipient, &addr_labels);
        let is_self_transfer = is_psbt_self_transfer(&core.wallet, &recipient);
        let valid_outpoints = build_valid_outpoints(&core.wallet);
        let has_spent_inputs = imported.unsigned_tx.input.iter().any(|txin| {
            !txin.previous_output.is_null() && !valid_outpoints.contains(&txin.previous_output)
        });

        Ok(APIImportPsbtResult {
            psbt: APIPsbtInfo {
                id,
                psbt_base64,
                txid,
                label: None,
                effective_label,
                is_auto,
                is_self_transfer,
                created_at,
                recipient,
                amount_sat,
                fee_sat,
                spend_path_id: 0,
                threshold,
                mfps,
                utxo_max_conf_height,
                has_spent_inputs,
            },
            was_merged: false,
        })
    }

    /// Analyze partial signatures present in a PSBT.
    ///
    /// Returns signing status per MFP (must sign every input to count as signed)
    /// and whether all inputs are already finalized.
    pub fn analyze_psbt(&self, psbt_base64: String, mfps: Vec<String>) -> Result<APIPsbtAnalysis> {
        use std::collections::HashMap;

        let psbt = psbt_from_base64(&psbt_base64)?;
        let n_inputs = psbt.inputs.len();

        // For each MFP track a per-input signed flag — signer must cover ALL inputs.
        let mut signed: HashMap<String, Vec<bool>> = mfps
            .iter()
            .map(|m| (m.clone(), vec![false; n_inputs]))
            .collect();

        for (idx, input) in psbt.inputs.iter().enumerate() {
            // Non-taproot: bip32_derivation maps CompressedPublicKey → (Fingerprint, DerivPath)
            for (pk, (fingerprint, _)) in &input.bip32_derivation {
                let mfp = fingerprint.to_string();
                let bpk = bdk_wallet::bitcoin::PublicKey::new(*pk);
                if input.partial_sigs.contains_key(&bpk) {
                    if let Some(v) = signed.get_mut(&mfp) {
                        v[idx] = true;
                    }
                }
            }

            // Taproot key-path: tap_key_sig present → internal key signed
            if input.tap_key_sig.is_some() {
                if let Some(tap_key) = input.tap_internal_key {
                    if let Some((_, ks)) = input.tap_key_origins.get(&tap_key) {
                        let mfp = ks.0.to_string();
                        if let Some(v) = signed.get_mut(&mfp) {
                            v[idx] = true;
                        }
                    }
                }
            }

            // Taproot script-path: tap_script_sigs keyed by (XOnlyPubKey, TapLeafHash)
            for (xpk, _) in input.tap_script_sigs.keys() {
                if let Some((_, ks)) = input.tap_key_origins.get(xpk) {
                    let mfp = ks.0.to_string();
                    if let Some(v) = signed.get_mut(&mfp) {
                        v[idx] = true;
                    }
                }
            }
        }

        let signers = mfps
            .iter()
            .map(|mfp| {
                let has_signed = signed
                    .get(mfp)
                    .map(|v| !v.is_empty() && v.iter().all(|&b| b))
                    .unwrap_or(false);
                APIPsbtSignerStatus {
                    mfp: mfp.clone(),
                    has_signed,
                }
            })
            .collect();

        let is_finalized = psbt
            .inputs
            .iter()
            .all(|i| i.final_script_sig.is_some() || i.final_script_witness.is_some());

        Ok(APIPsbtAnalysis {
            signers,
            is_finalized,
        })
    }

    /// Finalize the PSBT, broadcast via Electrum, and delete the local record.
    ///
    /// Returns the broadcast txid on success.
    pub async fn broadcast_psbt(&self, id: i64, electrum_url: String) -> Result<String> {
        use bdk_electrum::{electrum_client, BdkElectrumClient};

        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let row = get_psbt_row(&core.conn, id)?;
        // Capture label before consuming the row.
        let psbt_label = row.label.clone();
        let mut psbt = psbt_from_base64(&row.psbt)?;

        // Reject broadcast if any input UTXO is unconfirmed (required for relative timelocks,
        // and generally invalid — unconfirmed inputs cannot be spent by the network).
        for txin in &psbt.unsigned_tx.input {
            if let Some(utxo) = core.wallet.get_utxo(txin.previous_output) {
                if !matches!(
                    utxo.chain_position,
                    bdk_wallet::chain::ChainPosition::Confirmed { .. }
                ) {
                    return Err(anyhow::anyhow!(
                        "Cannot broadcast: input {} is not yet confirmed. \
                         Wait for the funding transaction to confirm first.",
                        txin.previous_output
                    ));
                }
            }
        }

        // If not already finalized by signer, try to finalize via BDK/miniscript.
        let already_final = psbt
            .inputs
            .iter()
            .all(|i| i.final_script_sig.is_some() || i.final_script_witness.is_some());
        if !already_final {
            #[allow(deprecated)]
            let ok = core
                .wallet
                .finalize_psbt(&mut psbt, bdk_wallet::SignOptions::default())?;
            if !ok {
                return Err(anyhow::anyhow!(
                    "Not enough signatures — PSBT cannot be finalized"
                ));
            }
        }

        let tx = psbt.extract_tx()?;
        let txid = tx.compute_txid();

        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);
        client.transaction_broadcast(&tx)?;

        // Apply the PSBT's label to the transaction before deleting the PSBT.
        if let Some(label) = &psbt_label {
            if !label.is_empty() && !tx_has_explicit_label(&core.conn, &txid.to_string())? {
                let _ = db_set_tx_label(&core.conn, &txid.to_string(), label, false, None);
            }
        }
        delete_psbt_row(&core.conn, id)?;
        drop(core);
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(txid.to_string())
    }
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
            None,
            KEY_HEX.to_string(),
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

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string())?;
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

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string())?;
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

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string())?;
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

        let handle = open_wallet(info.wallet_path, KEY_HEX.to_string())?;
        let b1 = handle.get_balance()?;
        let b2 = handle.get_balance()?;

        assert_eq!(b1.confirmed, b2.confirmed);
        Ok(())
    }

    #[test]
    fn test_open_wallet_get_info() -> Result<()> {
        let dir = tempdir()?;
        let info = make_wallet(&dir)?;

        let handle = open_wallet(info.wallet_path.clone(), KEY_HEX.to_string())?;
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
            None,
            KEY_HEX.to_string(),
        )?;
        create_wallet(
            wallets_dir.clone(),
            "W2".to_string(),
            MAINNET_DESC.to_string(),
            APINetwork::Bitcoin,
            None,
            KEY_HEX.to_string(),
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
        )?;

        let updated = get_wallet_info(info.wallet_path, KEY_HEX.to_string())?;
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
