use std::sync::Mutex;

use anyhow::Result;
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIAddress, APIBalance, APICoinControl, APIKeychain, APINetwork, APIPolicyPath,
    APIPsbtAnalysis, APIPsbtInfo, APIPsbtSignerStatus, APITransaction, APITransactionPage,
    APIUtxo, APIWalletInfo,
};
use crate::core::wallet::CoreWallet;
use crate::core::wallet_info::{
    create_wallet_db, get_wallet_info_from_file, list_wallets_in_dir, rename_wallet_in_file,
};
use crate::core::wallet_persistence::{
    delete_psbt_row, ensure_unsigned_txs_table, get_all_address_labels, get_all_key_labels,
    get_all_path_labels, get_all_tx_labels, get_psbt_row, insert_psbt, list_psbt_rows,
    open_encrypted_connection, read_wallet_info,
    set_address_label as db_set_address_label, set_key_label as db_set_key_label,
    set_path_label as db_set_path_label, set_tx_label as db_set_tx_label, touch_last_synced,
    update_psbt_data, PsbtRow, WalletInfoRow,
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

fn row_to_api_psbt(row: PsbtRow) -> APIPsbtInfo {
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
    })
}

/// Live wallet handle. Open once with [open_wallet], then call methods directly.
///
/// Holds the BDK wallet and its SQLite connection in memory — no file re-open per call.
pub struct APIWallet {
    inner: Mutex<CoreWallet>,
    pub path: String,
}

impl APIWallet {
    /// Return the cached balance (no network call).
    #[frb(sync)]
    pub fn get_balance(&self) -> Result<APIBalance> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let balance = core.wallet.balance();
        Ok(APIBalance {
            confirmed: balance.confirmed.to_sat(),
            trusted_pending: balance.trusted_pending.to_sat(),
            untrusted_pending: balance.untrusted_pending.to_sat(),
            immature: balance.immature.to_sat(),
        })
    }

    /// Return a paginated page of transactions, sorted newest-first (no network call).
    #[frb(sync)]
    pub fn get_transactions(&self, page: u32, page_size: u32) -> Result<APITransactionPage> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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

        let labels = get_all_tx_labels(&core.conn).unwrap_or_default();

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
                    let label = labels.get(&txid).cloned();

                    APITransaction {
                        txid,
                        received: received.to_sat(),
                        sent: sent.to_sat(),
                        fee,
                        confirmation_height,
                        confirmation_time,
                        label,
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

    /// Sync with Electrum, persist, and update last_synced_at.
    ///
    /// Uses full_scan on first sync (last_synced_at is None) to discover all addresses
    /// up to the stop gap. Uses incremental sync on subsequent calls to only check
    /// already-revealed script pubkeys, which is much faster.
    pub async fn sync(&self, electrum_url: String) -> Result<()> {
        use bdk_electrum::electrum_client;
        use bdk_electrum::BdkElectrumClient;

        let mut core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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

        Ok(())
    }

    /// Force a full scan regardless of sync history (re-discovers all addresses).
    pub async fn rescan(&self, electrum_url: String) -> Result<()> {
        use bdk_electrum::electrum_client;
        use bdk_electrum::BdkElectrumClient;

        let mut core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);
        let request = core.wallet.start_full_scan();
        let update = client.full_scan(request, STOP_GAP, BATCH_SIZE, false)?;
        core.wallet.apply_update(update)?;
        core.persist()?;
        touch_last_synced(&core.conn)?;

        Ok(())
    }

    /// Persist a label for a transaction. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_tx_label(&self, txid: String, label: String) -> Result<()> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_tx_label(&core.conn, &txid, &label)
    }

    /// Read wallet metadata from the open connection (no file re-open).
    #[frb(sync)]
    pub fn get_info(&self) -> Result<APIWalletInfo> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let row = read_wallet_info(&core.conn)?;
        row_to_api_info(self.path.clone(), row)
    }

    /// Return all currently revealed addresses for the given keychain, sorted by index ascending.
    /// Balance is the sum of all unspent outputs currently controlled by each address.
    #[frb(sync)]
    pub fn get_addresses(&self, keychain: APIKeychain) -> Result<Vec<APIAddress>> {
        use bdk_wallet::KeychainKind;
        use std::collections::HashMap;

        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

        let bdk_keychain = match keychain {
            APIKeychain::External => KeychainKind::External,
            APIKeychain::Internal => KeychainKind::Internal,
        };

        // Build UTXO balance map: derivation_index -> total sats for this keychain
        let mut balance_map: HashMap<u32, u64> = HashMap::new();
        for utxo in wallet.list_unspent() {
            if utxo.keychain == bdk_keychain {
                *balance_map.entry(utxo.derivation_index).or_insert(0) +=
                    utxo.txout.value.to_sat();
            }
        }

        // Count distinct transactions per address index and track used ones
        use std::collections::{HashMap as CountMap, HashSet};
        let spk_index = wallet.spk_index();
        let mut used_indices: HashSet<u32> = HashSet::new();
        let mut tx_count_map: CountMap<u32, u32> = CountMap::new();
        for canonical_tx in wallet.transactions() {
            for output in canonical_tx.tx_node.tx.output.iter() {
                if let Some((k, idx)) = spk_index.index_of_spk(output.script_pubkey.clone()) {
                    if *k == bdk_keychain {
                        used_indices.insert(*idx);
                        *tx_count_map.entry(*idx).or_insert(0) += 1;
                    }
                }
            }
        }

        let labels = get_all_address_labels(&core.conn).unwrap_or_default();

        // Collect all revealed addresses sorted by index ascending
        let mut addrs: Vec<APIAddress> = spk_index
            .revealed_keychain_spks(bdk_keychain)
            .map(|(idx, _)| {
                let addr = wallet.peek_address(bdk_keychain, idx).address.to_string();
                let balance_sat = balance_map.get(&idx).copied().unwrap_or(0);
                let is_used = used_indices.contains(&idx);
                let tx_count = tx_count_map.get(&idx).copied().unwrap_or(0);
                let label = labels.get(&addr).cloned();
                APIAddress { address: addr, index: idx, keychain, balance_sat, is_used, tx_count, label }
            })
            .collect();

        addrs.sort_by_key(|a| a.index);
        Ok(addrs)
    }

    /// Return all unspent outputs (UTXOs / coins), sorted by value descending.
    #[frb(sync)]
    pub fn get_utxos(&self) -> Result<Vec<APIUtxo>> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let wallet = &core.wallet;

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
                let confirmation_height = if let bdk_wallet::chain::ChainPosition::Confirmed {
                    anchor,
                    ..
                } = &local_output.chain_position
                {
                    Some(anchor.block_id.height)
                } else {
                    None
                };
                APIUtxo {
                    txid: local_output.outpoint.txid.to_string(),
                    vout: local_output.outpoint.vout,
                    value_sat: local_output.txout.value.to_sat(),
                    keychain,
                    derivation_index: local_output.derivation_index,
                    address,
                    is_confirmed,
                    confirmation_height,
                }
            })
            .collect();

        utxos.sort_by(|a, b| b.value_sat.cmp(&a.value_sat).then(a.txid.cmp(&b.txid)));
        Ok(utxos)
    }

    /// Reveal `count` new addresses for the given keychain beyond those already revealed,
    /// then persist the wallet. Returns the new total number of revealed addresses.
    #[frb(sync)]
    pub fn reveal_more_addresses(&self, keychain: APIKeychain, count: u32) -> Result<u32> {
        use bdk_wallet::KeychainKind;

        let mut core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let bdk_keychain = match keychain {
            APIKeychain::External => KeychainKind::External,
            APIKeychain::Internal => KeychainKind::Internal,
        };

        for _ in 0..count {
            core.wallet.reveal_next_address(bdk_keychain);
        }
        core.persist()?;

        let total = core.wallet.spk_index().revealed_keychain_spks(bdk_keychain).count() as u32;
        Ok(total)
    }

    /// Persist a label for an address. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_address_label(&self, address: String, label: String) -> Result<()> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_address_label(&core.conn, &address, &label)
    }

    /// Return the current best block height from the local chain (0 if not yet synced).
    #[frb(sync)]
    pub fn get_tip_height(&self) -> Result<u32> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        Ok(core.wallet.latest_checkpoint().block_id().height)
    }

    /// Return all key labels (mfp → label).
    #[frb(sync)]
    pub fn get_key_labels(&self) -> Result<Vec<APIKeyLabel>> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let map = get_all_key_labels(&core.conn).unwrap_or_default();
        Ok(map.into_iter().map(|(mfp, label)| APIKeyLabel { mfp, label }).collect())
    }

    /// Persist a label for a key by master fingerprint. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_key_label(&self, mfp: String, label: String) -> Result<()> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_key_label(&core.conn, &mfp, &label)
    }

    /// Return all spend-path labels (rust_id → label).
    #[frb(sync)]
    pub fn get_path_labels(&self) -> Result<Vec<APIPathLabel>> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let map = get_all_path_labels(&core.conn).unwrap_or_default();
        Ok(map.into_iter().map(|(rust_id, label)| APIPathLabel { rust_id, label }).collect())
    }

    /// Persist a label for a spend path by rust_id. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_path_label(&self, rust_id: u32, label: String) -> Result<()> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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

        let mut core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let network = core.wallet.network();
        let address = Address::from_str(&recipient_address)?.require_network(network)?;

        // float sat/vB → sat/kwu (1 sat/vB = 250 sat/kwu). Minimum 1 sat/kwu.
        let sat_per_kwu = ((fee_rate_sat_per_vb * 250.0).ceil() as u64).max(1);
        let fee_rate = FeeRate::from_sat_per_kwu(sat_per_kwu);

        let policy_map: BTreeMap<String, Vec<usize>> = policy_path
            .into_iter()
            .map(|pp| (pp.policy_id, pp.path.into_iter().map(|x| x as usize).collect()))
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
        })
    }

    /// Return all saved unsigned PSBTs for this wallet, newest-first.
    #[frb(sync)]
    pub fn list_psbts(&self) -> Result<Vec<APIPsbtInfo>> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        ensure_unsigned_txs_table(&core.conn)?;
        Ok(list_psbt_rows(&core.conn)?.into_iter().map(row_to_api_psbt).collect())
    }

    /// Delete a saved PSBT by id.
    #[frb(sync)]
    pub fn delete_psbt(&self, id: i64) -> Result<()> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        delete_psbt_row(&core.conn, id)
    }

    /// Merge partial signatures from a signed PSBT into the stored one.
    ///
    /// The signed PSBT must refer to the same transaction (same inputs/outputs).
    /// Returns the updated info.
    #[frb(sync)]
    pub fn merge_psbt(&self, id: i64, signed_psbt_base64: String) -> Result<APIPsbtInfo> {
        let core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let row = get_psbt_row(&core.conn, id)?;

        let mut existing = psbt_from_base64(&row.psbt)?;
        let signed = psbt_from_base64(&signed_psbt_base64)?;
        existing.combine(signed)?;

        let merged_base64 = psbt_to_base64(&existing);
        update_psbt_data(&core.conn, id, &merged_base64)?;

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
        })
    }

    /// Analyze partial signatures present in a PSBT.
    ///
    /// Returns signing status per MFP (must sign every input to count as signed)
    /// and whether all inputs are already finalized.
    #[frb(sync)]
    pub fn analyze_psbt(&self, psbt_base64: String, mfps: Vec<String>) -> Result<APIPsbtAnalysis> {
        use std::collections::HashMap;

        let psbt = psbt_from_base64(&psbt_base64)?;
        let n_inputs = psbt.inputs.len();

        // For each MFP track a per-input signed flag — signer must cover ALL inputs.
        let mut signed: HashMap<String, Vec<bool>> =
            mfps.iter().map(|m| (m.clone(), vec![false; n_inputs])).collect();

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
            for ((xpk, _), _) in &input.tap_script_sigs {
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
                APIPsbtSignerStatus { mfp: mfp.clone(), has_signed }
            })
            .collect();

        let is_finalized = psbt.inputs.iter().all(|i| {
            i.final_script_sig.is_some() || i.final_script_witness.is_some()
        });

        Ok(APIPsbtAnalysis { signers, is_finalized })
    }

    /// Finalize the PSBT, broadcast via Electrum, and delete the local record.
    ///
    /// Returns the broadcast txid on success.
    pub async fn broadcast_psbt(&self, id: i64, electrum_url: String) -> Result<String> {
        use bdk_electrum::{electrum_client, BdkElectrumClient};

        let mut core = self.inner.lock().map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let row = get_psbt_row(&core.conn, id)?;
        let mut psbt = psbt_from_base64(&row.psbt)?;

        // If not already finalized by signer, try to finalize via BDK/miniscript.
        let already_final = psbt.inputs.iter().all(|i| {
            i.final_script_sig.is_some() || i.final_script_witness.is_some()
        });
        if !already_final {
            #[allow(deprecated)]
            let ok = core.wallet.finalize_psbt(&mut psbt, bdk_wallet::SignOptions::default())?;
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
