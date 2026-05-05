/// Address and UTXO detail query helpers.
/// Extracted from `queries.rs` to reduce file size.
use super::*;
use super::{chain_conf_info, load_all_label_maps};

// ───────────────────────────────────────────────────────────────────────────
// get_utxo_details
// ───────────────────────────────────────────────────────────────────────────

pub(super) fn get_utxo_details_inner(
    wallet: &APIWallet,
    txid: String,
    vout: u32,
) -> Result<APIUtxoDetails> {
    let core = wallet.lock_wallet()?;
    let wallet_inner = &core.wallet;

    let (tx_labels, address_labels, coin_labels) = load_all_label_maps(&core.conn);

    let local_output = wallet_inner
        .list_unspent()
        .find(|u| u.outpoint.txid.to_string() == txid && u.outpoint.vout == vout)
        .ok_or_else(|| anyhow::anyhow!("UTXO not found: {}:{}", txid, vout))?;

    let keychain = match local_output.keychain {
        bdk_wallet::KeychainKind::External => APIKeychain::External,
        bdk_wallet::KeychainKind::Internal => APIKeychain::Internal,
    };
    let address = wallet_inner
        .peek_address(local_output.keychain, local_output.derivation_index)
        .address
        .to_string();
    let is_confirmed = matches!(
        &local_output.chain_position,
        bdk_wallet::chain::ChainPosition::Confirmed { .. }
    );
    let (confirmation_height, confirmation_time) = chain_conf_info(&local_output.chain_position);
    let outpoint_key = format!("{}:{}", txid, vout);

    let (label, effective_label, is_auto) = resolve_label(coin_labels.get(&outpoint_key).cloned());

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
        confirmation_time,
        label,
        effective_label,
        is_auto,
        pending_psbt_ids: vec![],
        mempool_spending_txid: None,
    };

    // The transaction that created this UTXO
    let creating_tx = wallet_inner
        .transactions()
        .find(|t| t.tx_node.txid.to_string() == txid)
        .map(|canonical_tx| {
            let tx_ref = &canonical_tx.tx_node.tx;
            let fee = wallet_inner.calculate_fee(tx_ref).ok().map(|f| f.to_sat());
            let conf_height = chain_conf_info(&canonical_tx.chain_position).0;
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

// ───────────────────────────────────────────────────────────────────────────
// get_address_details
// ───────────────────────────────────────────────────────────────────────────

pub(super) fn get_address_details_inner(
    wallet: &APIWallet,
    address: String,
) -> Result<APIAddressDetails> {
    use bdk_wallet::KeychainKind;
    use std::collections::HashSet;

    let core = wallet.lock_wallet()?;
    let wallet_inner = &core.wallet;

    let (tx_labels, address_labels, coin_labels) = load_all_label_maps(&core.conn);

    // Determine keychain + index for this address
    let spk_index = wallet_inner.spk_index();
    let (keychain, idx) = [KeychainKind::External, KeychainKind::Internal]
        .iter()
        .find_map(|&k| {
            spk_index
                .revealed_keychain_spks(k)
                .find(|(i, _)| wallet_inner.peek_address(k, *i).address.to_string() == address)
                .map(|(i, _)| (k, i))
        })
        .ok_or_else(|| anyhow::anyhow!("address not found: {}", address))?;

    let api_keychain = match keychain {
        KeychainKind::External => APIKeychain::External,
        KeychainKind::Internal => APIKeychain::Internal,
    };

    // Balance
    let balance_sat: u64 = wallet_inner
        .list_unspent()
        .filter(|u| u.keychain == keychain && u.derivation_index == idx)
        .map(|u| u.txout.value.to_sat())
        .sum();

    // All transactions that sent to OR spent from this address.
    // Pass 1: outputs to our address → receiving txids + outpoints we own.
    let mut related_txids: HashSet<String> = HashSet::new();
    let mut our_outpoints: HashSet<(String, u32)> = HashSet::new();
    for canonical_tx in wallet_inner.transactions() {
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
    for canonical_tx in wallet_inner.transactions() {
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

    let (label, effective_label, is_auto) = resolve_label(address_labels.get(&address).cloned());

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
    let related_utxos = wallet_inner
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

    let mut related_txs: Vec<APIRelatedTx> = wallet_inner
        .transactions()
        .filter(|t| related_txids.contains(&t.tx_node.txid.to_string()))
        .map(|canonical_tx| {
            let tx_ref = &canonical_tx.tx_node.tx;
            let txid_str = canonical_tx.tx_node.txid.to_string();
            let fee = wallet_inner.calculate_fee(tx_ref).ok().map(|f| f.to_sat());
            let conf_height = chain_conf_info(&canonical_tx.chain_position).0;
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
                        wallet_inner
                            .tx_graph()
                            .get_txout(inp.previous_output)
                            .map(|txout| txout.value.to_sat())
                    } else {
                        None
                    }
                })
                .sum();
            let (_, effective_label, is_auto) = resolve_label(tx_labels.get(&txid_str).cloned());
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
