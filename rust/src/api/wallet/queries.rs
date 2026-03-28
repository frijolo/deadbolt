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
                if let Ok(client) = create_raw_electrum_client(&electrum_url) {
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
        use bdk_wallet::chain::ChainPosition;
        use std::collections::{HashMap, HashSet};

        // Parse txid before acquiring any lock.
        let txid: Txid = spending_txid
            .parse()
            .map_err(|e| anyhow::anyhow!("invalid txid: {}", e))?;

        // Phase 1: retrieve the tx + attempt fee calculation (brief lock).
        let (tx, fee_opt, electrum_url) = {
            let core = self.lock_wallet()?;
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
                    if let Ok(client) = create_raw_electrum_client(&electrum_url) {
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

        // Phase 3 (brief lock): BFS over unconfirmed descendants.
        //
        // BIP-125 Rule 4 requires the replacement to pay at least:
        //   sum(fees of ALL evicted txs) + relay_fee(new_vsize)
        // "All evicted txs" = original tx + every unconfirmed descendant.
        let (desc_count, desc_fee_opt, desc_vsize) = {
            let core = self.lock_wallet()?;
            let wallet = &core.wallet;

            let unconfirmed_txids: HashSet<Txid> = wallet
                .transactions()
                .filter(|t| matches!(t.chain_position, ChainPosition::Unconfirmed { .. }))
                .map(|t| t.tx_node.txid)
                .collect();

            // walk_descendants does a BFS starting from txid.
            // Returning None from the closure stops that branch (confirmed tx or not in
            // mempool → its own children are not explored further either).
            let desc_txids: Vec<Txid> = wallet
                .tx_graph()
                .walk_descendants(txid, |_depth, d| {
                    if unconfirmed_txids.contains(&d) {
                        Some(d)
                    } else {
                        None
                    }
                })
                .collect();

            let mut count = 0u32;
            let mut fee_total = 0u64;
            let mut all_known = true;
            let mut vsize_total = 0u32;

            for d_txid in desc_txids {
                if let Some(d_arc) = wallet.tx_graph().get_tx(d_txid) {
                    let d_tx = d_arc.as_ref();
                    count += 1;
                    vsize_total += d_tx.weight().to_vbytes_ceil() as u32;
                    match wallet.tx_graph().calculate_fee(d_tx).ok() {
                        Some(f) => fee_total += f.to_sat(),
                        None => all_known = false,
                    }
                }
            }

            (
                count,
                if all_known { Some(fee_total) } else { None },
                vsize_total,
            )
        };

        // Total conflict fee = orig + descendants (if all known; otherwise orig is a lower bound).
        let total_conflict_fee = fee_sat + desc_fee_opt.unwrap_or(0);
        let total_conflict_vsize = vsize + desc_vsize;

        // ImprovesFeerateDiagram: replacement must exceed the *package* rate of the whole
        // conflict cluster. Falls back to orig rate when descendant fees are unknown.
        let package_rate = if total_conflict_vsize > 0 && desc_fee_opt.is_some() {
            total_conflict_fee as f64 / total_conflict_vsize as f64
        } else {
            fee_rate
        };

        Ok(APIRbfInfo {
            orig_fee_sat: fee_sat,
            orig_vsize: vsize,
            orig_fee_rate_sat_per_vb: fee_rate,
            descendant_count: desc_count,
            descendant_fee_sat: desc_fee_opt,
            descendant_vsize: desc_vsize,
            // Rule 4: total conflict fees + relay fee for new tx bandwidth.
            // orig_vsize used as proxy for new_vsize (Dart refines with actual vsize).
            min_fee_sat: total_conflict_fee + vsize as u64,
            // Package rate: the ImprovesFeerateDiagram constraint for the whole cluster.
            min_fee_rate_sat_per_vb: package_rate,
        })
    }

    /// Return the aggregate fee info for the full unconfirmed ancestor package of the given
    /// parent txids. Performs a BFS through the tx graph to collect all unconfirmed ancestors
    /// transitively (parents, grandparents, …), summing their fees and vsizes to compute the
    /// effective package fee rate that miners use when evaluating CPFP.
    ///
    /// `parent_txids` should be the txids of the unconfirmed UTXOs being spent as child inputs.
    pub async fn get_cpfp_info(&self, parent_txids: Vec<String>) -> Result<APICpfpInfo> {
        use bdk_wallet::bitcoin::Txid;
        use bdk_wallet::chain::ChainPosition;
        use std::collections::{HashMap, HashSet, VecDeque};

        // Phase 1 (brief lock): BFS through tx_graph to collect all unconfirmed ancestor txs.
        // Also collect outpoints whose parent txout is missing from the graph → need Electrum.
        let (ancestor_txs, missing_txids, electrum_url) = {
            let core = self.lock_wallet()?;
            let wallet = &core.wallet;

            // Index unconfirmed txids for O(1) lookup.
            let unconfirmed_txids: HashSet<Txid> = wallet
                .transactions()
                .filter(|t| matches!(t.chain_position, ChainPosition::Unconfirmed { .. }))
                .map(|t| t.tx_node.txid)
                .collect();

            let mut visited: HashSet<Txid> = HashSet::new();
            let mut queue: VecDeque<Txid> = VecDeque::new();
            let mut ancestor_txs: Vec<bdk_wallet::bitcoin::Transaction> = Vec::new();
            let mut missing_outpoints: HashSet<Txid> = HashSet::new();

            for txid_str in &parent_txids {
                let txid: Txid = txid_str
                    .parse()
                    .map_err(|e| anyhow::anyhow!("invalid txid: {}", e))?;
                if visited.insert(txid) {
                    queue.push_back(txid);
                }
            }

            while let Some(txid) = queue.pop_front() {
                // Only include unconfirmed txs in the ancestor set.
                if !unconfirmed_txids.contains(&txid) {
                    continue;
                }
                let tx = match wallet.tx_graph().get_tx(txid) {
                    Some(arc) => arc.as_ref().clone(),
                    None => continue,
                };
                ancestor_txs.push(tx.clone());

                for inp in &tx.input {
                    if inp.previous_output.is_null() {
                        continue;
                    }
                    // Enqueue ancestor if not yet visited.
                    if visited.insert(inp.previous_output.txid) {
                        queue.push_back(inp.previous_output.txid);
                    }
                    // Track inputs whose txout is missing (needed for fee calculation).
                    if wallet.tx_graph().get_txout(inp.previous_output).is_none() {
                        missing_outpoints.insert(inp.previous_output.txid);
                    }
                }
            }

            let url = self
                .electrum_url
                .lock()
                .map(|u| (*u).clone())
                .unwrap_or_default();

            (
                ancestor_txs,
                missing_outpoints.into_iter().collect::<Vec<_>>(),
                url,
            )
        };

        if ancestor_txs.is_empty() {
            return Err(anyhow::anyhow!("no unconfirmed ancestor txs found"));
        }

        // Phase 2: fetch missing parent txs from Electrum (no lock held).
        let mut fetched_txs: HashMap<Txid, bdk_wallet::bitcoin::Transaction> = HashMap::new();
        if !missing_txids.is_empty() && !electrum_url.is_empty() {
            use bdk_electrum::electrum_client::ElectrumApi;
            if let Ok(client) = create_raw_electrum_client(&electrum_url) {
                for id in &missing_txids {
                    if let Ok(t) = client.transaction_get(id) {
                        fetched_txs.insert(*id, t);
                    }
                }
            }
        }

        // Phase 3 (brief lock): aggregate fees and vsizes across all ancestor txs.
        let (total_fee_opt, total_vsize) = {
            let core = self.lock_wallet()?;
            let mut total_fee: u64 = 0;
            let mut all_fees_known = true;
            let mut total_vsize: u32 = 0;

            for tx in &ancestor_txs {
                total_vsize += tx.weight().to_vbytes_ceil() as u32;

                // Try BDK's graph-based fee calculation first.
                if let Ok(fee) = core.wallet.tx_graph().calculate_fee(tx) {
                    total_fee += fee.to_sat();
                    continue;
                }

                // Fallback: sum(inputs) – sum(outputs) using graph + fetched txs.
                let mut input_sum = 0u64;
                let mut this_known = true;
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
                            fetched_txs
                                .get(&inp.previous_output.txid)
                                .and_then(|t| t.output.get(inp.previous_output.vout as usize))
                                .map(|o| o.value.to_sat())
                        });
                    match val {
                        Some(v) => input_sum += v,
                        None => {
                            this_known = false;
                            break;
                        }
                    }
                }
                if this_known {
                    let output_sum: u64 = tx.output.iter().map(|o| o.value.to_sat()).sum();
                    total_fee += input_sum.saturating_sub(output_sum);
                } else {
                    all_fees_known = false;
                }
            }

            (
                if all_fees_known {
                    Some(total_fee)
                } else {
                    None
                },
                total_vsize,
            )
        };

        let fee_rate = match total_fee_opt {
            Some(fee) if total_vsize > 0 => fee as f64 / total_vsize as f64,
            _ => 0.0,
        };

        Ok(APICpfpInfo {
            ancestor_fee_sat: total_fee_opt,
            ancestor_vsize: total_vsize,
            ancestor_fee_rate_sat_per_vb: fee_rate,
            ancestor_count: ancestor_txs.len() as u32,
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

// ───────────────────────────────────────────────────────────────────────────
// Unit tests for get_cpfp_info
// ───────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use bdk_wallet::bitcoin::{
        absolute, transaction, Amount, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut,
        Witness,
    };
    use tempfile::tempdir;

    // ── Re-use the same descriptor / key from the mod.rs tests ──────────────
    const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    fn make_wallet(dir: &tempfile::TempDir) -> APIWallet {
        let wallets_dir = dir.path().to_string_lossy().to_string();
        let info = create_wallet(
            wallets_dir,
            "CPFP Test Wallet".to_string(),
            MAINNET_DESC.to_string(),
            APINetwork::Bitcoin,
            KEY_HEX.to_string(),
            APIProtectionType::DeviceKey,
            None,
            APISecurityLevel::Standard,
        )
        .expect("create_wallet failed");
        open_wallet(info.wallet_path, KEY_HEX.to_string(), None).expect("open_wallet failed")
    }

    /// Return the scriptPubKey for external address at index `idx`.
    fn wallet_spk(wallet: &APIWallet, idx: u32) -> ScriptBuf {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(bdk_wallet::KeychainKind::External, idx)
            .address
            .script_pubkey()
    }

    /// A P2WPKH scriptPubKey that is NOT in the wallet's SPK set.
    /// Outputs to this script are invisible to `wallet.transactions()` while
    /// still being available in `tx_graph.get_txout()` for fee calculation.
    fn external_spk() -> ScriptBuf {
        // OP_0 <20 bytes of 0xde> — valid P2WPKH pattern, not in our wallet's SPK set.
        let mut bytes = vec![0x00u8, 0x14];
        bytes.extend_from_slice(&[0xde; 20]);
        ScriptBuf::from_bytes(bytes)
    }

    /// Build a genesis funding tx: sends `value_sat` to `spk`, no real inputs.
    /// Insert via `inject_graph_tx` (with `external_spk()` as the spk) so the
    /// tx is only present in the graph for txout lookups, not in `wallet.transactions()`.
    fn genesis_tx(spk: ScriptBuf, value_sat: u64) -> Transaction {
        Transaction {
            version: transaction::Version::TWO,
            lock_time: absolute::LockTime::ZERO,
            input: vec![TxIn {
                previous_output: OutPoint::null(), // null → BFS will skip it
                script_sig: ScriptBuf::default(),
                sequence: Sequence::MAX,
                witness: Witness::default(),
            }],
            output: vec![TxOut {
                value: Amount::from_sat(value_sat),
                script_pubkey: spk,
            }],
        }
    }

    /// Build a spending transaction: one input spending `prev:vout`, one output to `spk`.
    fn spending_tx(
        prev_txid: bdk_wallet::bitcoin::Txid,
        vout: u32,
        spk: ScriptBuf,
        value_sat: u64,
    ) -> Transaction {
        Transaction {
            version: transaction::Version::TWO,
            lock_time: absolute::LockTime::ZERO,
            input: vec![TxIn {
                previous_output: OutPoint {
                    txid: prev_txid,
                    vout,
                },
                script_sig: ScriptBuf::default(),
                sequence: Sequence::MAX,
                witness: Witness::default(),
            }],
            output: vec![TxOut {
                value: Amount::from_sat(value_sat),
                script_pubkey: spk,
            }],
        }
    }

    // ── Error cases ──────────────────────────────────────────────────────────

    #[tokio::test]
    async fn test_cpfp_empty_txids_returns_error() {
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);
        let result = wallet.get_cpfp_info(vec![]).await;
        assert!(result.is_err(), "empty txid list should return Err");
    }

    #[tokio::test]
    async fn test_cpfp_invalid_txid_returns_error() {
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);
        let result = wallet
            .get_cpfp_info(vec!["not_a_valid_txid".to_string()])
            .await;
        assert!(result.is_err(), "invalid txid should return Err");
    }

    #[tokio::test]
    async fn test_cpfp_no_unconfirmed_ancestor_returns_error() {
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);
        // Valid txid but the tx is not in the wallet graph at all.
        let fake_txid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let result = wallet.get_cpfp_info(vec![fake_txid.to_string()]).await;
        assert!(
            result.is_err(),
            "txid not present in wallet should return Err"
        );
        let msg = result.unwrap_err().to_string();
        assert!(
            msg.contains("no unconfirmed ancestor"),
            "error message should mention 'no unconfirmed ancestor', got: {msg}"
        );
    }

    // ── Single parent, fee calculable ────────────────────────────────────────

    #[tokio::test]
    async fn test_cpfp_single_parent_fee_known() {
        // Setup: genesis (graph-only, external output) → parent (unconfirmed, wallet output).
        // genesis output = 100_000 sats, parent output = 90_000 sats → fee = 10_000 sats.
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);

        // genesis goes to an external address → not wallet-relevant → not in wallet.transactions()
        let genesis = genesis_tx(external_spk(), 100_000);
        let genesis_txid = genesis.compute_txid();
        wallet.inject_graph_tx(genesis).unwrap();

        // parent spends genesis:0 and sends to our wallet → wallet-relevant → in wallet.transactions()
        let parent = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
        let parent_txid = parent.compute_txid();
        wallet.inject_unconfirmed_tx(parent).unwrap();

        let info = wallet
            .get_cpfp_info(vec![parent_txid.to_string()])
            .await
            .expect("get_cpfp_info should succeed");

        assert_eq!(info.ancestor_count, 1, "should find exactly one ancestor");
        assert!(info.ancestor_vsize > 0, "vsize must be positive");
        assert_eq!(
            info.ancestor_fee_sat,
            Some(10_000),
            "fee should be 100_000 − 90_000 = 10_000 sats"
        );
        let expected_rate = 10_000.0 / info.ancestor_vsize as f64;
        assert!(
            (info.ancestor_fee_rate_sat_per_vb - expected_rate).abs() < 0.001,
            "fee rate should be fee / vsize"
        );
    }

    // ── Single parent, fee unknown (parent input not in graph) ───────────────

    #[tokio::test]
    async fn test_cpfp_single_parent_fee_unknown() {
        // Parent's input txout is NOT in the graph → fee cannot be calculated.
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);

        let unknown_txid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            .parse::<bdk_wallet::bitcoin::Txid>()
            .unwrap();
        // Output to our wallet → wallet-relevant → in wallet.transactions()
        let parent = spending_tx(unknown_txid, 0, wallet_spk(&wallet, 0), 50_000);
        let parent_txid = parent.compute_txid();
        wallet.inject_unconfirmed_tx(parent).unwrap();

        let info = wallet
            .get_cpfp_info(vec![parent_txid.to_string()])
            .await
            .expect("get_cpfp_info should succeed even when fee is unknown");

        assert_eq!(info.ancestor_count, 1);
        assert!(info.ancestor_vsize > 0);
        assert_eq!(
            info.ancestor_fee_sat, None,
            "fee should be None when parent inputs are not in the graph"
        );
        assert_eq!(
            info.ancestor_fee_rate_sat_per_vb, 0.0,
            "fee rate should be 0.0 when fee is unknown"
        );
    }

    // ── Transitive ancestors (grandparent chain) ─────────────────────────────

    #[tokio::test]
    async fn test_cpfp_transitive_ancestor_chain() {
        // genesis (graph-only, external) → grandparent (unconfirmed) → parent (unconfirmed)
        // BFS from parent should count both grandparent and parent: ancestor_count=2, fee=20k.
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);

        let genesis = genesis_tx(external_spk(), 100_000);
        let genesis_txid = genesis.compute_txid();
        wallet.inject_graph_tx(genesis).unwrap();

        // grandparent: spends genesis:0, output to wallet addr #0
        let grandparent = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
        let grandparent_txid = grandparent.compute_txid();
        wallet.inject_unconfirmed_tx(grandparent).unwrap();

        // parent: spends grandparent:0, output to wallet addr #1
        let parent = spending_tx(grandparent_txid, 0, wallet_spk(&wallet, 1), 80_000);
        let parent_txid = parent.compute_txid();
        wallet.inject_unconfirmed_tx(parent).unwrap();

        let info = wallet
            .get_cpfp_info(vec![parent_txid.to_string()])
            .await
            .expect("get_cpfp_info should succeed");

        assert_eq!(
            info.ancestor_count, 2,
            "should include grandparent and parent"
        );
        assert_eq!(
            info.ancestor_fee_sat,
            Some(20_000),
            "total fee: (100k−90k) + (90k−80k) = 20_000 sats"
        );
        assert!(info.ancestor_vsize > 0);
        let expected_rate = 20_000.0 / info.ancestor_vsize as f64;
        assert!((info.ancestor_fee_rate_sat_per_vb - expected_rate).abs() < 0.001);
    }

    // ── Multiple roots (multi-parent CPFP) ───────────────────────────────────

    #[tokio::test]
    async fn test_cpfp_multiple_roots_aggregated() {
        // Two independent unconfirmed parents (each with a known fee).
        // Passing both txids should aggregate ancestor_count=2, total_fee=20k.
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);

        // Parent A: genesis_a (external, 100k) → parent_a (wallet addr #0, 90k), fee=10k
        let genesis_a = genesis_tx(external_spk(), 100_000);
        let genesis_a_txid = genesis_a.compute_txid();
        wallet.inject_graph_tx(genesis_a).unwrap();
        let parent_a = spending_tx(genesis_a_txid, 0, wallet_spk(&wallet, 0), 90_000);
        let parent_a_txid = parent_a.compute_txid();
        wallet.inject_unconfirmed_tx(parent_a).unwrap();

        // Parent B: genesis_b (external, 60k) → parent_b (wallet addr #1, 50k), fee=10k
        // genesis_b has a different value so it has a distinct txid from genesis_a.
        let genesis_b = genesis_tx(external_spk(), 60_000);
        let genesis_b_txid = genesis_b.compute_txid();
        wallet.inject_graph_tx(genesis_b).unwrap();
        let parent_b = spending_tx(genesis_b_txid, 0, wallet_spk(&wallet, 1), 50_000);
        let parent_b_txid = parent_b.compute_txid();
        wallet.inject_unconfirmed_tx(parent_b).unwrap();

        let info = wallet
            .get_cpfp_info(vec![parent_a_txid.to_string(), parent_b_txid.to_string()])
            .await
            .expect("get_cpfp_info should succeed");

        assert_eq!(
            info.ancestor_count, 2,
            "should count both independent parents"
        );
        assert_eq!(
            info.ancestor_fee_sat,
            Some(20_000),
            "total fee: (100k−90k) + (60k−50k) = 20_000 sats"
        );
        assert!(info.ancestor_vsize > 0);
    }

    // ── Deduplication: same txid supplied twice ───────────────────────────────

    #[tokio::test]
    async fn test_cpfp_duplicate_txids_not_counted_twice() {
        let dir = tempdir().unwrap();
        let wallet = make_wallet(&dir);

        let genesis = genesis_tx(external_spk(), 100_000);
        let genesis_txid = genesis.compute_txid();
        wallet.inject_graph_tx(genesis).unwrap();

        let parent = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
        let parent_txid = parent.compute_txid();
        wallet.inject_unconfirmed_tx(parent).unwrap();

        // Supply the same txid twice — must count only once.
        let info = wallet
            .get_cpfp_info(vec![parent_txid.to_string(), parent_txid.to_string()])
            .await
            .expect("get_cpfp_info should succeed");

        assert_eq!(
            info.ancestor_count, 1,
            "duplicate txids must not inflate ancestor_count"
        );
        assert_eq!(info.ancestor_fee_sat, Some(10_000));
    }
}
