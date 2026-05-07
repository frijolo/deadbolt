use super::chain_conf_info;
/// Transaction detail query helper.
/// Extracted from `queries.rs` to reduce file size.
use super::*;

pub(super) fn get_tx_details_inner(wallet: &APIWallet, txid: String) -> Result<APITxDetails> {
    use bdk_wallet::bitcoin::Txid;
    use std::collections::{HashMap, HashSet};

    // Phase 1: identify input txids absent from BDK's data (brief lock scope).
    let (missing_txids, electrum_url) = {
        let core = wallet.lock_wallet()?;
        let wallet_inner = &core.wallet;
        let canonical_tx = wallet_inner
            .transactions()
            .find(|t| t.tx_node.txid.to_string() == txid)
            .ok_or_else(|| anyhow::anyhow!("transaction not found: {}", txid))?;
        let known_txids: HashSet<Txid> = wallet_inner
            .transactions()
            .map(|t| t.tx_node.txid)
            .collect();
        let missing: Vec<Txid> = canonical_tx
            .tx_node
            .tx
            .input
            .iter()
            .filter(|i| !i.previous_output.is_null())
            .filter(|i| {
                !known_txids.contains(&i.previous_output.txid)
                    && wallet_inner
                        .tx_graph()
                        .get_txout(i.previous_output)
                        .is_none()
            })
            .map(|i| i.previous_output.txid)
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        let url = wallet
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
    let core = wallet.lock_wallet()?;
    let wallet_inner = &core.wallet;

    let tx_labels = get_all_tx_labels_with_flag(&core.conn).unwrap_or_default();

    let canonical_tx = wallet_inner
        .transactions()
        .find(|t| t.tx_node.txid.to_string() == txid)
        .ok_or_else(|| anyhow::anyhow!("transaction not found: {}", txid))?;

    let tx_ref = &canonical_tx.tx_node.tx;
    let (confirmation_height, confirmation_time) = chain_conf_info(&canonical_tx.chain_position);
    let (sent, received) = wallet_inner.sent_and_received(tx_ref);
    let fee = wallet_inner.calculate_fee(tx_ref).ok().map(|f| f.to_sat());

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
    let related_utxos = wallet_inner
        .list_unspent()
        .filter(|u| u.outpoint.txid.to_string() == txid)
        .map(|u| {
            let address = wallet_inner
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
    let spk_index = wallet_inner.spk_index();
    let network = wallet_inner.network();
    let tx_map: HashMap<String, _> = wallet_inner
        .transactions()
        .map(|t| (t.tx_node.txid.to_string(), t))
        .collect();

    // Resolve a previous output: BDK graph → TxGraph TxOut → Electrum-fetched tx.
    let resolve_prev =
        |outpoint: bdk_wallet::bitcoin::OutPoint| -> Option<(bdk_wallet::bitcoin::ScriptBuf, u64)> {
            let prev_txid = outpoint.txid.to_string();
            let prev_vout = outpoint.vout as usize;
            if let Some(o) = tx_map
                .get(&prev_txid)
                .and_then(|t| t.tx_node.tx.output.get(prev_vout))
            {
                return Some((o.script_pubkey.clone(), o.value.to_sat()));
            }
            if let Some(txout) = wallet_inner.tx_graph().get_txout(outpoint) {
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
                    ..Default::default()
                };
            }
            let prev_txid = input.previous_output.txid.to_string();
            let Some((spk, value)) = resolve_prev(input.previous_output) else {
                return APIRelatedAddress {
                    address: format!("{}…:{}", &prev_txid[..8], input.previous_output.vout),
                    ..Default::default()
                };
            };
            if let Some((k, i)) = spk_index.index_of_spk(spk.clone()) {
                let addr_str = wallet_inner.peek_address(*k, *i).address.to_string();
                let (_, effective_label, is_auto) =
                    resolve_label(address_labels.get(&addr_str).cloned());
                APIRelatedAddress {
                    address: addr_str,
                    value_sat: Some(value),
                    effective_label,
                    is_auto,
                    is_mine: true,
                    ..Default::default()
                }
            } else {
                let addr_str = bdk_wallet::bitcoin::Address::from_script(&spk, network)
                    .map(|a| a.to_string())
                    .unwrap_or_else(|_| "undecodeable script".to_string());
                APIRelatedAddress {
                    address: addr_str,
                    value_sat: Some(value),
                    ..Default::default()
                }
            }
        })
        .collect();

    // Output addresses.
    let output_addresses: Vec<APIRelatedAddress> = tx_ref
        .output
        .iter()
        .map(|output| {
            if output.script_pubkey.is_op_return() {
                return APIRelatedAddress {
                    value_sat: Some(output.value.to_sat()),
                    op_return_data: Some(crate::core::op_return::extract_op_return_payload(
                        &output.script_pubkey,
                    )),
                    ..Default::default()
                };
            }
            if let Some((k, i)) = spk_index.index_of_spk(output.script_pubkey.clone()) {
                let addr_str = wallet_inner.peek_address(*k, *i).address.to_string();
                let (_, effective_label, is_auto) =
                    resolve_label(address_labels.get(&addr_str).cloned());
                APIRelatedAddress {
                    address: addr_str,
                    value_sat: Some(output.value.to_sat()),
                    effective_label,
                    is_auto,
                    is_mine: true,
                    ..Default::default()
                }
            } else {
                let addr_str =
                    bdk_wallet::bitcoin::Address::from_script(&output.script_pubkey, network)
                        .map(|a| a.to_string())
                        .unwrap_or_else(|_| "undecodeable script".to_string());
                APIRelatedAddress {
                    address: addr_str,
                    value_sat: Some(output.value.to_sat()),
                    ..Default::default()
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
