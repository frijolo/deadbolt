use super::detail_address::{get_address_details_inner, get_utxo_details_inner};
use super::detail_cpfp::get_cpfp_info_inner;
use super::detail_rbf::get_rbf_info_inner;
use super::detail_tx::get_tx_details_inner;
use super::*;

impl APIWallet {
    /// Return the cached balance (no network call).
    pub fn get_balance(&self) -> Result<APIBalance> {
        let core = self.lock_wallet()?;
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
        let core = self.lock_wallet()?;
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
                        chain_conf_info(&canonical_tx.chain_position);

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

    /// Read wallet metadata from the open connection (no file re-open).
    pub fn get_info(&self) -> Result<APIWalletInfo> {
        let core = self.lock_wallet()?;
        let row = read_wallet_info(&core.conn)?;
        row_to_api_info(self.path.clone(), row)
    }

    /// Return all currently revealed addresses for the given keychain, sorted by index ascending.
    /// Balance is the sum of all unspent outputs currently controlled by each address.
    pub fn get_addresses(&self, keychain: APIKeychain) -> Result<Vec<APIAddress>> {
        use bdk_wallet::KeychainKind;

        let core = self.lock_wallet()?;
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
        let core = self.lock_wallet()?;
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

        // Build txid → (confirmation_height, confirmation_time) map for all wallet transactions.
        // Used to determine the original confirmation status of ghost UTXOs.
        let tx_conf_info: std::collections::HashMap<
            bdk_wallet::bitcoin::Txid,
            (Option<u32>, Option<u64>),
        > = wallet
            .transactions()
            .map(|t| {
                let info = chain_conf_info(&t.chain_position);
                (t.tx_node.txid, info)
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
                let (confirmation_height, confirmation_time) =
                    chain_conf_info(&local_output.chain_position);
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
                    confirmation_time,
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
                let (conf_height, conf_time) = tx_conf_info
                    .get(&txin.previous_output.txid)
                    .copied()
                    .unwrap_or((None, None));

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
                    confirmation_time: conf_time,
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
        get_tx_details_inner(self, txid)
    }

    /// Return RBF replacement constraints for a mempool tx spending one of our UTXOs.
    /// Fetches parent txs from Electrum when fee cannot be determined from the wallet graph.
    pub async fn get_rbf_info(&self, spending_txid: String) -> Result<APIRbfInfo> {
        get_rbf_info_inner(self, spending_txid).await
    }

    /// Return the aggregate fee info for the full unconfirmed ancestor package of the given
    /// parent txids. Performs a BFS through the tx graph to collect all unconfirmed ancestors
    /// transitively (parents, grandparents, …), summing their fees and vsizes to compute the
    /// effective package fee rate that miners use when evaluating CPFP.
    ///
    /// `parent_txids` should be the txids of the unconfirmed UTXOs being spent as child inputs.
    pub async fn get_cpfp_info(&self, parent_txids: Vec<String>) -> Result<APICpfpInfo> {
        get_cpfp_info_inner(self, parent_txids).await
    }

    /// Return full detail for a UTXO: the UTXO plus the explicit labels of its cluster peers.
    pub fn get_utxo_details(&self, txid: String, vout: u32) -> Result<APIUtxoDetails> {
        get_utxo_details_inner(self, txid, vout)
    }

    /// Return full detail for an address: the address plus its unspent UTXOs.
    pub fn get_address_details(&self, address: String) -> Result<APIAddressDetails> {
        get_address_details_inner(self, address)
    }

    /// Reveal `count` new addresses for the given keychain beyond those already revealed,
    /// then persist the wallet. Returns the new total number of revealed addresses.
    #[frb(sync)]
    pub fn reveal_more_addresses(&self, keychain: APIKeychain, count: u32) -> Result<u32> {
        use bdk_wallet::KeychainKind;

        let mut core = self.lock_wallet()?;
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

    /// Return the current best block height from the local chain (0 if not yet synced).
    pub fn get_tip_height(&self) -> Result<u32> {
        let core = self.lock_wallet()?;
        Ok(core.wallet.latest_checkpoint().block_id().height)
    }

    // -----------------------------------------------------------------------
    // Fiat price methods
    // -----------------------------------------------------------------------

    /// Store (or replace) the BTC price in `currency` at the time of a transaction.
    pub fn store_fiat_price(&self, txid: String, currency: String, btc_price: f64) -> Result<()> {
        let core = self.lock_wallet()?;
        store_fiat_price_db(&core.conn, &txid, &currency, btc_price)
    }

    /// Return all stored BTC prices for `currency` as a list of (txid, price) pairs.
    pub fn get_fiat_prices(&self, currency: String) -> Result<Vec<APIFiatPrice>> {
        let core = self.lock_wallet()?;
        Ok(get_fiat_prices_db(&core.conn, &currency)?
            .into_iter()
            .map(|(txid, btc_price)| APIFiatPrice { txid, btc_price })
            .collect())
    }

    /// Return transactions that have no stored fiat price for `currency`.
    pub fn get_txids_missing_fiat(&self, currency: String) -> Result<Vec<APITxMissingFiat>> {
        let core = self.lock_wallet()?;
        let existing: std::collections::HashSet<String> =
            get_fiat_prices_db(&core.conn, &currency)?
                .into_iter()
                .map(|(txid, _)| txid)
                .collect();
        let missing = core
            .wallet
            .transactions()
            .filter_map(|canonical_tx| {
                let txid = canonical_tx.tx_node.txid.to_string();
                if existing.contains(&txid) {
                    return None;
                }
                let confirmation_time = chain_conf_info(&canonical_tx.chain_position)
                    .1
                    .map(|t| t as i64);
                Some(APITxMissingFiat {
                    txid,
                    confirmation_time,
                })
            })
            .collect();
        Ok(missing)
    }

    /// Delete all stored fiat prices (called when the user changes fiat currency).
    pub fn clear_fiat_prices(&self) -> Result<()> {
        let core = self.lock_wallet()?;
        clear_fiat_prices_db(&core.conn)
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Unit tests for get_cpfp_info
// ───────────────────────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "queries_tests.rs"]
mod tests;
