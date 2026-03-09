use std::sync::Mutex;

use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIAddress, APIAddressDetails, APIBalance, APICoinControl, APIKeychain, APINetwork,
    APIPolicyPath, APIPsbtAnalysis, APIPsbtInfo, APIPsbtSignerStatus, APIRelatedAddress,
    APIRelatedTx, APIRelatedUtxo, APITransaction, APITransactionPage, APITxDetails, APIUtxo,
    APIUtxoDetails, APIWalletInfo,
};
use crate::core::wallet::CoreWallet;
use crate::core::wallet_info::{
    create_wallet_db, get_wallet_info_from_file, list_wallets_in_dir, rename_wallet_in_file,
};
use crate::core::wallet_persistence::{
    delete_psbt_row, ensure_unsigned_txs_table, get_all_address_labels, get_all_coin_labels,
    get_all_key_labels, get_all_path_labels, get_all_tx_labels, get_psbt_row, insert_psbt,
    list_psbt_rows, open_encrypted_connection, read_wallet_info,
    set_address_label as db_set_address_label, set_coin_label as db_set_coin_label,
    set_key_label as db_set_key_label, set_path_label as db_set_path_label,
    set_tx_label as db_set_tx_label, touch_last_synced, update_psbt_data, PsbtRow, WalletInfoRow,
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

fn row_to_api_psbt(row: PsbtRow, wallet: &bdk_wallet::Wallet) -> APIPsbtInfo {
    let utxo_max_conf_height = psbt_from_base64(&row.psbt)
        .ok()
        .and_then(|psbt| psbt_max_utxo_conf_height(wallet, &psbt));
    APIPsbtInfo {
        id: row.id,
        psbt_base64: row.psbt,
        label: row.label,
        created_at: row.created_at,
        recipient: row.recipient,
        amount_sat: row.amount_sat,
        fee_sat: row.fee_sat,
        spend_path_id: row.spend_path_id,
        threshold: row.threshold,
        mfps: row.mfps,
        utxo_max_conf_height,
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
// Label inheritance helpers
// ---------------------------------------------------------------------------

/// Resolve effective label: explicit label wins; otherwise use inherited.
/// Returns `(effective_label, is_inherited)`.
fn resolve_label(explicit: Option<&String>, inherited: Option<&String>) -> (Option<String>, bool) {
    if let Some(l) = explicit.filter(|l| !l.is_empty()) {
        return (Some(l.clone()), false);
    }
    if let Some(l) = inherited.filter(|l| !l.is_empty()) {
        return (Some(l.clone()), true);
    }
    (None, false)
}

/// Build a map  txid → Vec<(address, addr_label, coin_label)>  from all unspent outputs.
/// Used to look up cluster labels for transactions and to build the related-UTXO list.
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

/// Build a map  address → Vec<(txid, tx_label, coin_label)>  from all unspent outputs.
/// Used to look up cluster labels for addresses.
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

/// Pick the first non-empty inherited label from a list of (primary, fallback) pairs.
fn first_inherited(pairs: &[(Option<String>, Option<String>)]) -> Option<String> {
    for (primary, fallback) in pairs {
        if let Some(l) = primary.as_deref().filter(|l| !l.is_empty()) {
            return Some(l.to_string());
        }
        if let Some(l) = fallback.as_deref().filter(|l| !l.is_empty()) {
            return Some(l.to_string());
        }
    }
    None
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
            let height_a = a.chain_position.confirmation_height_upper_bound();
            let height_b = b.chain_position.confirmation_height_upper_bound();
            height_b.cmp(&height_a)
        });

        let total_count = txs.len() as u32;
        let start = (page * page_size) as usize;
        let end = (start + page_size as usize).min(txs.len());
        let has_more = end < txs.len();

        let tx_labels = get_all_tx_labels(&core.conn).unwrap_or_default();
        let address_labels = get_all_address_labels(&core.conn).unwrap_or_default();
        let coin_labels = get_all_coin_labels(&core.conn).unwrap_or_default();
        // txid → Vec<(address, addr_label, coin_label)> for cluster label lookup
        let tx_utxo_map = build_tx_utxo_map(wallet, &address_labels, &coin_labels);

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
                    let label = tx_labels.get(&txid).cloned();

                    // Inherited: scan output UTXOs — address label > coin label
                    let cluster = tx_utxo_map.get(&txid).map(|v| {
                        v.iter()
                            .map(|(_, al, cl)| (al.clone(), cl.clone()))
                            .collect::<Vec<_>>()
                    });
                    let inherited = cluster.as_deref().and_then(first_inherited);
                    let (effective_label, label_is_inherited) =
                        resolve_label(label.as_ref(), inherited.as_ref());

                    APITransaction {
                        txid,
                        received: received.to_sat(),
                        sent: sent.to_sat(),
                        fee,
                        confirmation_height,
                        confirmation_time,
                        label,
                        effective_label,
                        label_is_inherited,
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
        drop(core);
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(())
    }

    /// Persist a label for a transaction. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_tx_label(&self, txid: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_tx_label(&core.conn, &txid, &label)
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

        let address_labels = get_all_address_labels(&core.conn).unwrap_or_default();
        let coin_labels = get_all_coin_labels(&core.conn).unwrap_or_default();
        let tx_labels = get_all_tx_labels(&core.conn).unwrap_or_default();
        // address → Vec<(txid, tx_label, coin_label)> for cluster label lookup
        let addr_utxo_map = build_addr_utxo_map(wallet, &tx_labels, &coin_labels);

        // Collect all revealed addresses sorted by index ascending
        let mut addrs: Vec<APIAddress> = spk_index
            .revealed_keychain_spks(bdk_keychain)
            .map(|(idx, _)| {
                let addr = wallet.peek_address(bdk_keychain, idx).address.to_string();
                let balance_sat = balance_map.get(&idx).copied().unwrap_or(0);
                let addr_txids = per_addr_txids.get(&idx);
                let is_used = addr_txids.is_some();
                let tx_count = addr_txids.map(|s| s.len() as u32).unwrap_or(0);
                let label = address_labels.get(&addr).cloned();

                // Inherited: scan UTXOs at this address — tx label > coin label
                let cluster = addr_utxo_map.get(&addr).map(|v| {
                    v.iter()
                        .map(|(_, tl, cl)| (tl.clone(), cl.clone()))
                        .collect::<Vec<_>>()
                });
                let inherited = cluster.as_deref().and_then(first_inherited);
                let (effective_label, label_is_inherited) =
                    resolve_label(label.as_ref(), inherited.as_ref());

                APIAddress {
                    address: addr,
                    index: idx,
                    keychain,
                    balance_sat,
                    is_used,
                    tx_count,
                    label,
                    effective_label,
                    label_is_inherited,
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

        let coin_labels = get_all_coin_labels(&core.conn).unwrap_or_default();
        let address_labels = get_all_address_labels(&core.conn).unwrap_or_default();
        let tx_labels = get_all_tx_labels(&core.conn).unwrap_or_default();

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
                let txid = local_output.outpoint.txid.to_string();
                let label = coin_labels.get(&outpoint_key).cloned();

                // Inherited: address label > tx label
                let inherited = first_inherited(&[(
                    address_labels
                        .get(&address)
                        .filter(|l| !l.is_empty())
                        .cloned(),
                    tx_labels.get(&txid).filter(|l| !l.is_empty()).cloned(),
                )]);
                let (effective_label, label_is_inherited) =
                    resolve_label(label.as_ref(), inherited.as_ref());

                APIUtxo {
                    txid,
                    vout: local_output.outpoint.vout,
                    value_sat: local_output.txout.value.to_sat(),
                    keychain,
                    derivation_index: local_output.derivation_index,
                    address,
                    is_confirmed,
                    confirmation_height,
                    label,
                    effective_label,
                    label_is_inherited,
                }
            })
            .collect();

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

        let tx_labels = get_all_tx_labels(&core.conn).unwrap_or_default();
        let address_labels = get_all_address_labels(&core.conn).unwrap_or_default();
        let coin_labels = get_all_coin_labels(&core.conn).unwrap_or_default();
        let tx_utxo_map = build_tx_utxo_map(wallet, &address_labels, &coin_labels);

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
        let label = tx_labels.get(&txid).cloned();

        let cluster = tx_utxo_map.get(&txid).map(|v| {
            v.iter()
                .map(|(_, al, cl)| (al.clone(), cl.clone()))
                .collect::<Vec<_>>()
        });
        let inherited = cluster.as_deref().and_then(first_inherited);
        let (effective_label, label_is_inherited) =
            resolve_label(label.as_ref(), inherited.as_ref());

        let tx = APITransaction {
            txid: txid.clone(),
            received: received.to_sat(),
            sent: sent.to_sat(),
            fee,
            confirmation_height,
            confirmation_time,
            label,
            effective_label,
            label_is_inherited,
        };

        // Unspent output coins created by this transaction.
        let related_utxos = wallet
            .list_unspent()
            .filter(|u| u.outpoint.txid.to_string() == txid)
            .map(|u| {
                let address = wallet
                    .peek_address(u.keychain, u.derivation_index)
                    .address
                    .to_string();
                let outpoint_key = format!("{}:{}", u.outpoint.txid, u.outpoint.vout);
                APIRelatedUtxo {
                    txid: u.outpoint.txid.to_string(),
                    vout: u.outpoint.vout,
                    address: address.clone(),
                    value_sat: u.txout.value.to_sat(),
                    utxo_label: coin_labels
                        .get(&outpoint_key)
                        .filter(|l| !l.is_empty())
                        .cloned(),
                    address_label: address_labels
                        .get(&address)
                        .filter(|l| !l.is_empty())
                        .cloned(),
                }
            })
            .collect();

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
                        label: None,
                        is_mine: false,
                    };
                }
                let prev_txid = input.previous_output.txid.to_string();
                let Some((spk, value)) = resolve_prev(input.previous_output) else {
                    return APIRelatedAddress {
                        address: format!("{}…:{}", &prev_txid[..8], input.previous_output.vout),
                        value_sat: None,
                        label: None,
                        is_mine: false,
                    };
                };
                if let Some((k, i)) = spk_index.index_of_spk(spk.clone()) {
                    let addr_str = wallet.peek_address(*k, *i).address.to_string();
                    let label = address_labels
                        .get(&addr_str)
                        .filter(|l| !l.is_empty())
                        .cloned();
                    APIRelatedAddress {
                        address: addr_str,
                        value_sat: Some(value),
                        label,
                        is_mine: true,
                    }
                } else {
                    let addr_str = bdk_wallet::bitcoin::Address::from_script(&spk, network)
                        .map(|a| a.to_string())
                        .unwrap_or_else(|_| "undecodeable script".to_string());
                    APIRelatedAddress {
                        address: addr_str,
                        value_sat: Some(value),
                        label: None,
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
                    let label = address_labels
                        .get(&addr_str)
                        .filter(|l| !l.is_empty())
                        .cloned();
                    APIRelatedAddress {
                        address: addr_str,
                        value_sat: Some(output.value.to_sat()),
                        label,
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
                        label: None,
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

    /// Return full detail for a UTXO: the UTXO plus the explicit labels of its cluster peers.
    pub fn get_utxo_details(&self, txid: String, vout: u32) -> Result<APIUtxoDetails> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let coin_labels = get_all_coin_labels(&core.conn).unwrap_or_default();
        let address_labels = get_all_address_labels(&core.conn).unwrap_or_default();
        let tx_labels = get_all_tx_labels(&core.conn).unwrap_or_default();

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
        let label = coin_labels.get(&outpoint_key).cloned();
        let address_label = address_labels
            .get(&address)
            .filter(|l| !l.is_empty())
            .cloned();
        let tx_label = tx_labels.get(&txid).filter(|l| !l.is_empty()).cloned();

        let inherited = first_inherited(&[(address_label.clone(), tx_label.clone())]);
        let (effective_label, label_is_inherited) =
            resolve_label(label.as_ref(), inherited.as_ref());

        let utxo = APIUtxo {
            txid: txid.clone(),
            vout,
            value_sat: local_output.txout.value.to_sat(),
            keychain,
            derivation_index: local_output.derivation_index,
            address,
            is_confirmed,
            confirmation_height,
            label,
            effective_label,
            label_is_inherited,
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
                // This is the creating tx: the coin is the output, nothing is spent yet.
                APIRelatedTx {
                    txid: txid.clone(),
                    label: tx_label.clone(),
                    confirmation_height: conf_height,
                    addr_received: local_output.txout.value.to_sat(),
                    addr_spent: 0,
                    fee,
                }
            })
            .ok_or_else(|| anyhow::anyhow!("creating transaction not found: {}", txid))?;

        Ok(APIUtxoDetails {
            utxo,
            address_label,
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

        let address_labels = get_all_address_labels(&core.conn).unwrap_or_default();
        let coin_labels = get_all_coin_labels(&core.conn).unwrap_or_default();
        let tx_labels = get_all_tx_labels(&core.conn).unwrap_or_default();
        let addr_utxo_map = build_addr_utxo_map(wallet, &tx_labels, &coin_labels);

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

        let label = address_labels.get(&address).cloned();
        let cluster = addr_utxo_map.get(&address).map(|v| {
            v.iter()
                .map(|(_, tl, cl)| (tl.clone(), cl.clone()))
                .collect::<Vec<_>>()
        });
        let inherited = cluster.as_deref().and_then(first_inherited);
        let (effective_label, label_is_inherited) =
            resolve_label(label.as_ref(), inherited.as_ref());

        let addr = APIAddress {
            address: address.clone(),
            index: idx,
            keychain: api_keychain,
            balance_sat,
            is_used: used,
            tx_count,
            label,
            effective_label,
            label_is_inherited,
        };

        // Related UTXOs at this address
        let related_utxos = wallet
            .list_unspent()
            .filter(|u| u.keychain == keychain && u.derivation_index == idx)
            .map(|u| {
                let outpoint_key = format!("{}:{}", u.outpoint.txid, u.outpoint.vout);
                let txid = u.outpoint.txid.to_string();
                APIRelatedUtxo {
                    txid: txid.clone(),
                    vout: u.outpoint.vout,
                    address: address.clone(),
                    value_sat: u.txout.value.to_sat(),
                    utxo_label: coin_labels
                        .get(&outpoint_key)
                        .filter(|l| !l.is_empty())
                        .cloned(),
                    address_label: address_labels
                        .get(&address)
                        .filter(|l| !l.is_empty())
                        .cloned(),
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
                APIRelatedTx {
                    txid: txid_str.clone(),
                    label: tx_labels.get(&txid_str).filter(|l| !l.is_empty()).cloned(),
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
    #[frb(sync)]
    pub fn set_address_label(&self, address: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_address_label(&core.conn, &address, &label)
    }

    /// Persist a label for a coin (UTXO) by outpoint. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_coin_label(&self, txid: String, vout: u32, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let outpoint = format!("{}:{}", txid, vout);
        db_set_coin_label(&core.conn, &outpoint, &label)
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

        let mut builder = core.wallet.build_tx();
        builder.fee_rate(fee_rate);

        if send_max {
            // Drain all selected (or all wallet) funds to recipient, no change output.
            builder.drain_to(address.script_pubkey());
            if !selected_utxos.is_empty() {
                for coin in &selected_utxos {
                    let txid = Txid::from_str(&coin.txid)?;
                    builder.add_utxo(OutPoint::new(txid, coin.vout))?;
                }
                builder.manually_selected_only();
            } else {
                builder.drain_wallet();
            }
        } else {
            let amount = Amount::from_sat(amount_sat);
            builder.add_recipient(address.script_pubkey(), amount);
            if !selected_utxos.is_empty() {
                for coin in &selected_utxos {
                    let txid = Txid::from_str(&coin.txid)?;
                    builder.add_utxo(OutPoint::new(txid, coin.vout))?;
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

        Ok(APIPsbtInfo {
            id,
            psbt_base64,
            label: None,
            created_at,
            recipient,
            amount_sat: actual_amount_sat,
            fee_sat,
            spend_path_id,
            threshold,
            mfps,
            utxo_max_conf_height,
        })
    }

    /// Return all saved unsigned PSBTs for this wallet, newest-first.
    pub fn list_psbts(&self) -> Result<Vec<APIPsbtInfo>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        ensure_unsigned_txs_table(&core.conn)?;
        Ok(list_psbt_rows(&core.conn)?
            .into_iter()
            .map(|row| row_to_api_psbt(row, &core.wallet))
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
        Ok(APIPsbtInfo {
            id,
            psbt_base64: merged_base64,
            label: row.label,
            created_at: row.created_at,
            recipient: row.recipient,
            amount_sat: row.amount_sat,
            fee_sat: row.fee_sat,
            spend_path_id: row.spend_path_id,
            threshold: row.threshold,
            mfps: row.mfps,
            utxo_max_conf_height,
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
