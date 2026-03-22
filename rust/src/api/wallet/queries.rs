use super::*;

type LabelMap = std::collections::HashMap<String, (String, bool)>;

/// Load all three label maps in one call. Used by detail query functions that
/// need tx, address, and coin labels simultaneously.
fn load_all_label_maps(conn: &rusqlite::Connection) -> (LabelMap, LabelMap, LabelMap) {
    (
        get_all_tx_labels_with_flag(conn).unwrap_or_default(),
        get_all_address_labels_with_flag(conn).unwrap_or_default(),
        get_all_coin_labels_with_flag(conn).unwrap_or_default(),
    )
}

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
            let core = self.lock_wallet()?;
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
        let core = self.lock_wallet()?;
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
            let core = self.lock_wallet()?;
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
                    let core = self.lock_wallet()?;
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
                    let core = self.lock_wallet()?;
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
        let core = self.lock_wallet()?;
        let wallet = &core.wallet;

        let (tx_labels, address_labels, coin_labels) = load_all_label_maps(&core.conn);

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

        let core = self.lock_wallet()?;
        let wallet = &core.wallet;

        let (tx_labels, address_labels, coin_labels) = load_all_label_maps(&core.conn);

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
                let confirmation_time =
                    if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                        &canonical_tx.chain_position
                    {
                        Some(anchor.confirmation_time as i64)
                    } else {
                        None
                    };
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
