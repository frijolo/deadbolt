/// RBF (Replace-By-Fee) info query helper.
/// Extracted from `queries.rs` to reduce file size.
use super::*;

pub(super) async fn get_rbf_info_inner(
    wallet: &APIWallet,
    spending_txid: String,
) -> Result<APIRbfInfo> {
    use bdk_wallet::bitcoin::Txid;
    use bdk_wallet::chain::ChainPosition;
    use std::collections::{HashMap, HashSet};

    // Parse txid before acquiring any lock.
    let txid: Txid = spending_txid
        .parse()
        .map_err(|e| anyhow::anyhow!("invalid txid: {}", e))?;

    // Phase 1: retrieve the tx + attempt fee calculation (brief lock).
    let (tx, fee_opt, electrum_url) = {
        let core = wallet.lock_wallet()?;
        let tx = core
            .wallet
            .tx_graph()
            .get_tx(txid)
            .ok_or_else(|| anyhow::anyhow!("spending tx not found: {}", spending_txid))?
            .as_ref()
            .clone();
        let fee_opt = core.wallet.tx_graph().calculate_fee(&tx).ok();
        let url = wallet
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
                let core = wallet.lock_wallet()?;
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

            let mut parent_txs: HashMap<Txid, bdk_wallet::bitcoin::Transaction> = HashMap::new();
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
                let core = wallet.lock_wallet()?;
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
                        .ok_or_else(|| anyhow::anyhow!("input value unknown for RBF fee calc"))?;
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
        let core = wallet.lock_wallet()?;
        let wallet_inner = &core.wallet;

        let unconfirmed_txids: HashSet<Txid> = wallet_inner
            .transactions()
            .filter(|t| matches!(t.chain_position, ChainPosition::Unconfirmed { .. }))
            .map(|t| t.tx_node.txid)
            .collect();

        // walk_descendants does a BFS starting from txid.
        // Returning None from the closure stops that branch (confirmed tx or not in
        // mempool → its own children are not explored further either).
        let desc_txids: Vec<Txid> = wallet_inner
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
            if let Some(d_arc) = wallet_inner.tx_graph().get_tx(d_txid) {
                let d_tx = d_arc.as_ref();
                count += 1;
                vsize_total += d_tx.weight().to_vbytes_ceil() as u32;
                match wallet_inner.tx_graph().calculate_fee(d_tx).ok() {
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
        // incrementalrelayfee = 1 sat/vB (Core's default) → vsize × 1.
        // orig_vsize is a proxy for new_vsize; the Dart layer refines with the actual vsize.
        min_fee_sat: total_conflict_fee + vsize as u64,
        // Package rate: the ImprovesFeerateDiagram constraint for the whole cluster.
        min_fee_rate_sat_per_vb: package_rate,
    })
}
