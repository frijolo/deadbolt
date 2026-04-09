use anyhow::Result;
use rusqlite::Connection;

use super::{
    address_has_explicit_label, coin_has_explicit_label, set_address_label, set_coin_label,
    set_tx_label, tx_has_explicit_label,
};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum EntityType {
    Tx,
    Address,
    Coin,
}

/// Build a canonical source_entity identifier for the given entity type and id.
/// Format: `"tx:{txid}"`, `"addr:{address}"`, or `"coin:{txid}:{vout}"`.
pub fn source_entity_id(source_type: EntityType, source_id: &str) -> String {
    match source_type {
        EntityType::Tx => format!("tx:{}", source_id),
        EntityType::Address => format!("addr:{}", source_id),
        EntityType::Coin => format!("coin:{}", source_id),
    }
}

fn set_coin_if_none(conn: &Connection, outpoint: &str, label: &str, source: &str) -> Result<()> {
    if !coin_has_explicit_label(conn, outpoint)? {
        set_coin_label(conn, outpoint, label, true, Some(source))?;
    }
    Ok(())
}

fn set_address_if_none(conn: &Connection, address: &str, label: &str, source: &str) -> Result<()> {
    if !address_has_explicit_label(conn, address)? {
        set_address_label(conn, address, label, true, Some(source))?;
    }
    Ok(())
}

fn set_tx_if_none(conn: &Connection, txid: &str, label: &str, source: &str) -> Result<()> {
    if !tx_has_explicit_label(conn, txid)? {
        set_tx_label(conn, txid, label, true, Some(source))?;
    }
    Ok(())
}

fn clear_source_labels(conn: &Connection, source: &str) -> Result<()> {
    for table in ["tx_labels", "address_labels", "coin_labels"] {
        conn.execute(
            &format!("DELETE FROM {table} WHERE source_entity = ?1"),
            rusqlite::params![source],
        )?;
    }
    Ok(())
}

/// Propagate a label to related entities as auto-generated labels.
/// Clears any stale auto-labels previously propagated by this source first,
/// then writes new ones — skipping targets that already have an explicit label.
pub fn propagate_label(
    conn: &Connection,
    wallet: &bdk_wallet::Wallet,
    source_type: EntityType,
    source_id: &str,
    label: &str,
) -> Result<()> {
    let source = source_entity_id(source_type, source_id);

    // Remove stale auto-labels from this source before re-propagating.
    clear_source_labels(conn, &source)?;

    match source_type {
        EntityType::Tx => {
            let txid = source_id;
            let spk_index = wallet.spk_index();
            if let Some(canonical_tx) = wallet
                .transactions()
                .find(|t| t.tx_node.txid.to_string() == txid)
            {
                let tx_ref = &canonical_tx.tx_node.tx;
                for (vout_idx, output) in tx_ref.output.iter().enumerate() {
                    let Some((keychain, derivation_index)) =
                        spk_index.index_of_spk(output.script_pubkey.clone())
                    else {
                        continue;
                    };
                    let address = wallet
                        .peek_address(*keychain, *derivation_index)
                        .address
                        .to_string();
                    let outpoint_str = format!("{}:{}", txid, vout_idx);
                    set_coin_if_none(conn, &outpoint_str, label, &source)?;
                    set_address_if_none(conn, &address, label, &source)?;
                }
                for input in tx_ref.input.iter() {
                    let prev_out = input.previous_output;
                    let Some(prev_txout) = wallet.tx_graph().get_txout(prev_out) else {
                        continue;
                    };
                    let Some((keychain, derivation_index)) =
                        spk_index.index_of_spk(prev_txout.script_pubkey.clone())
                    else {
                        continue;
                    };
                    let address = wallet
                        .peek_address(*keychain, *derivation_index)
                        .address
                        .to_string();
                    let outpoint_str = format!("{}:{}", prev_out.txid, prev_out.vout);
                    set_coin_if_none(conn, &outpoint_str, label, &source)?;
                    set_address_if_none(conn, &address, label, &source)?;
                }
            }
        }
        EntityType::Address => {
            use bdk_wallet::KeychainKind;
            let address = source_id;
            let spk_index = wallet.spk_index();
            let maybe_info = [KeychainKind::External, KeychainKind::Internal]
                .iter()
                .find_map(|&k| {
                    spk_index
                        .revealed_keychain_spks(k)
                        .find(|(i, _)| wallet.peek_address(k, *i).address.to_string() == address)
                        .map(|(i, _)| (k, i))
                });
            if let Some((keychain, idx)) = maybe_info {
                let mut our_outpoints: std::collections::HashSet<(String, u32)> =
                    std::collections::HashSet::new();
                for canonical_tx in wallet.transactions() {
                    for (vout_idx, output) in canonical_tx.tx_node.tx.output.iter().enumerate() {
                        if let Some((k, i)) = spk_index.index_of_spk(output.script_pubkey.clone()) {
                            if *k == keychain && *i == idx {
                                let txid = canonical_tx.tx_node.txid.to_string();
                                our_outpoints.insert((txid.clone(), vout_idx as u32));
                                let outpoint_str = format!("{}:{}", txid, vout_idx);
                                set_coin_if_none(conn, &outpoint_str, label, &source)?;
                                set_tx_if_none(conn, &txid, label, &source)?;
                            }
                        }
                    }
                }
                for canonical_tx in wallet.transactions() {
                    for input in canonical_tx.tx_node.tx.input.iter() {
                        let prev = (
                            input.previous_output.txid.to_string(),
                            input.previous_output.vout,
                        );
                        if our_outpoints.contains(&prev) {
                            let spending_txid = canonical_tx.tx_node.txid.to_string();
                            set_tx_if_none(conn, &spending_txid, label, &source)?;
                        }
                    }
                }
            }
        }
        EntityType::Coin => {
            let outpoint = source_id;
            let parts: Vec<&str> = outpoint.split(':').collect();
            if parts.len() == 2 {
                let txid = parts[0];
                set_tx_if_none(conn, txid, label, &source)?;
                if let Ok(vout) = parts[1].parse::<u32>() {
                    let spk_index = wallet.spk_index();
                    use bdk_wallet::bitcoin::OutPoint;
                    use std::str::FromStr;
                    if let Ok(txid_bitcoin) = bdk_wallet::bitcoin::Txid::from_str(txid) {
                        let target_outpoint = OutPoint::new(txid_bitcoin, vout);
                        if let Some(prev_txout) = wallet.tx_graph().get_txout(target_outpoint) {
                            if let Some((keychain, derivation_index)) =
                                spk_index.index_of_spk(prev_txout.script_pubkey.clone())
                            {
                                let address = wallet
                                    .peek_address(*keychain, *derivation_index)
                                    .address
                                    .to_string();
                                set_address_if_none(conn, &address, label, &source)?;
                            }
                        }
                        for canonical_tx in wallet.transactions() {
                            if canonical_tx
                                .tx_node
                                .tx
                                .input
                                .iter()
                                .any(|i| i.previous_output == target_outpoint)
                            {
                                let spending_txid = canonical_tx.tx_node.txid.to_string();
                                set_tx_if_none(conn, &spending_txid, label, &source)?;
                            }
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
pub fn cascade_delete_label(
    conn: &Connection,
    source_type: EntityType,
    source_id: &str,
) -> Result<()> {
    let source = source_entity_id(source_type, source_id);
    clear_source_labels(conn, &source)
}
