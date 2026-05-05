/// CPFP (Child-Pays-For-Parent) info query helper.
/// Extracted from `queries.rs` to reduce file size.
use super::*;

pub(super) async fn get_cpfp_info_inner(
    wallet: &APIWallet,
    parent_txids: Vec<String>,
) -> Result<APICpfpInfo> {
    use bdk_wallet::bitcoin::Txid;
    use bdk_wallet::chain::ChainPosition;
    use std::collections::{HashMap, HashSet, VecDeque};

    // Phase 1 (brief lock): BFS through tx_graph to collect all unconfirmed ancestor txs.
    // Also collect outpoints whose parent txout is missing from the graph → need Electrum.
    let (ancestor_txs, missing_txids, electrum_url) = {
        let core = wallet.lock_wallet()?;
        let wallet_inner = &core.wallet;

        // Index unconfirmed txids for O(1) lookup.
        let unconfirmed_txids: HashSet<Txid> = wallet_inner
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
            let tx = match wallet_inner.tx_graph().get_tx(txid) {
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
                if wallet_inner
                    .tx_graph()
                    .get_txout(inp.previous_output)
                    .is_none()
                {
                    missing_outpoints.insert(inp.previous_output.txid);
                }
            }
        }

        let url = wallet
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
        let core = wallet.lock_wallet()?;
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
