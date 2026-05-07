use super::*;

// ---------------------------------------------------------------------------
// Shared UTXO resolution — used by create_psbt and prepare_backup_psbt
// ---------------------------------------------------------------------------

struct ResolvedUtxo {
    outpoint: bdk_wallet::bitcoin::OutPoint,
    /// Some → foreign (mempool) UTXO; None → normal internal UTXO.
    foreign: Option<(
        bdk_wallet::bitcoin::psbt::Input,
        bdk_wallet::bitcoin::Weight,
    )>,
}

/// Resolve selected coin-control UTXOs.
///
/// Confirmed UTXOs are looked up in BDK's internal set. Coins already spent in a
/// mempool TX (full-RBF) are reconstructed from the tx graph as foreign UTXOs so the
/// TxBuilder can still include them.
fn resolve_selected_utxos(
    core: &crate::core::wallet::CoreWallet,
    selected_utxos: &[APICoinControl],
) -> Result<Vec<ResolvedUtxo>> {
    use bdk_wallet::bitcoin::{OutPoint, Txid};
    use bdk_wallet::KeychainKind;
    use std::str::FromStr;

    let mut resolved = Vec::with_capacity(selected_utxos.len());
    for coin in selected_utxos {
        let outpoint = OutPoint::new(Txid::from_str(&coin.txid)?, coin.vout);
        if core.wallet.get_utxo(outpoint).is_some() {
            resolved.push(ResolvedUtxo {
                outpoint,
                foreign: None,
            });
        } else {
            let txout = core
                .wallet
                .tx_graph()
                .get_txout(outpoint)
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "UTXO not found in wallet or tx graph: {}:{}",
                        coin.txid,
                        coin.vout
                    )
                })?
                .clone();
            let keychain = core
                .wallet
                .spk_index()
                .index_of_spk(txout.script_pubkey.clone())
                .map(|(k, _)| *k)
                .unwrap_or(KeychainKind::External);
            // BIP-174: non-taproot segwit inputs must include non_witness_utxo.
            let non_witness_utxo = core
                .wallet
                .tx_graph()
                .get_tx(outpoint.txid)
                .map(|tx| tx.as_ref().clone());
            let psbt_input = bdk_wallet::bitcoin::psbt::Input {
                witness_utxo: Some(txout),
                non_witness_utxo,
                ..Default::default()
            };
            let satisfaction_weight = core
                .wallet
                .public_descriptor(keychain)
                .max_weight_to_satisfy()
                .unwrap_or(bdk_wallet::bitcoin::Weight::from_wu(500));
            resolved.push(ResolvedUtxo {
                outpoint,
                foreign: Some((psbt_input, satisfaction_weight)),
            });
        }
    }
    Ok(resolved)
}

// ---------------------------------------------------------------------------
// Shared signer injection — used by sign_psbt_with_key and sign_backup_psbt
// ---------------------------------------------------------------------------

/// Inject the hot-key signer for `mfp` into `core.wallet` and sign `psbt` in place.
///
/// Never auto-finalizes (`try_finalize: false`). Clears injected signers after signing
/// to keep the wallet watch-only.
fn sign_psbt_in_place(
    core: &mut crate::core::wallet::CoreWallet,
    psbt: &mut bdk_wallet::bitcoin::psbt::Psbt,
    mfp: &str,
) -> Result<()> {
    use crate::core::seed::{
        make_private_descriptor, root_xprv_to_mfp, seed_entry_to_root_xprv,
        split_multipath_descriptor, strip_descriptor_checksum,
    };
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use bdk_wallet::{KeychainKind, Wallet};
    use std::sync::Arc;

    let (seeds, _) = list_seed_entries(&core.conn)?;
    let seed = seeds
        .iter()
        .find(|s| s.mfp == mfp)
        .ok_or_else(|| anyhow::anyhow!("No signing key with MFP {} found", mfp))?;

    let info = read_wallet_info(&core.conn)?;
    let network: bdk_wallet::bitcoin::Network = APINetwork::try_from(info.network.as_str())?.into();
    let secp = Secp256k1::new();

    let root_xprv = seed_entry_to_root_xprv(
        &seed.seed_type,
        seed.mnemonic.as_deref(),
        &seed.passphrase,
        seed.xprv.as_deref(),
        network,
    )?;

    let derived_mfp = root_xprv_to_mfp(&root_xprv, &secp);
    if derived_mfp != mfp {
        return Err(anyhow::anyhow!(
            "Key MFP mismatch: expected {} got {}",
            mfp,
            derived_mfp
        ));
    }

    let private_desc = make_private_descriptor(&info.descriptor, &root_xprv, &secp)
        .map_err(|e| anyhow::anyhow!("make_private_descriptor failed for {}: {}", mfp, e))?;
    let private_desc = strip_descriptor_checksum(&private_desc);
    let (ext_desc, int_desc) = split_multipath_descriptor(&private_desc);

    let temp = Wallet::create(ext_desc, int_desc)
        .network(network)
        .create_wallet_no_persist()
        .map_err(|e| anyhow::anyhow!("Failed to build signer for {}: {}", mfp, e))?;

    for keychain in [KeychainKind::External, KeychainKind::Internal] {
        #[allow(deprecated)]
        for signer in temp.get_signers(keychain).signers() {
            #[allow(deprecated)]
            core.wallet.add_signer(
                keychain,
                bdk_wallet::signer::SignerOrdering(200),
                Arc::clone(signer),
            );
        }
    }

    #[allow(deprecated)]
    match core.wallet.sign(
        psbt,
        bdk_wallet::SignOptions {
            trust_witness_utxo: true,
            try_finalize: false,
            ..Default::default()
        },
    ) {
        Ok(_) => {}
        Err(e) => return Err(anyhow::anyhow!("Signing failed for {}: {}", mfp, e)),
    }

    core.wallet
        .set_keymap(KeychainKind::External, Default::default());
    core.wallet
        .set_keymap(KeychainKind::Internal, Default::default());

    Ok(())
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Patch nSequence and nLockTime on foreign (mempool) UTXO inputs when the spend path has a
/// timelock. BDK applies policy_path to internal UTXOs but leaves foreign UTXOs with the default
/// ENABLE_RBF_NO_LOCKTIME sequence (0xFFFFFFFD, bit 31 = 1). OP_CSV requires bit 31 = 0, so
/// Bitcoin Core rejects the broadcast with "Locktime requirement not satisfied" without this fixup.
fn apply_timelock_fixup(
    psbt: &mut bdk_wallet::bitcoin::psbt::Psbt,
    conn: &rusqlite::Connection,
    spend_path_id: u32,
    has_foreign: bool,
) {
    if !has_foreign || spend_path_id == 0 {
        return;
    }
    if let Ok(paths) = load_spend_paths(conn) {
        if let Some(sp) = paths.iter().find(|sp| sp.id == spend_path_id) {
            if sp.rel_timelock > 0 {
                let seq = bdk_wallet::bitcoin::Sequence(sp.rel_timelock);
                for txin in &mut psbt.unsigned_tx.input {
                    txin.sequence = seq;
                }
            }
            if sp.abs_timelock > 0 {
                psbt.unsigned_tx.lock_time =
                    bdk_wallet::bitcoin::absolute::LockTime::from_consensus(sp.abs_timelock);
            }
        }
    }
}

/// Return true if every PSBT input is finalized (has final_script_sig or final_script_witness).
fn is_psbt_finalized(psbt: &bdk_wallet::bitcoin::psbt::Psbt) -> bool {
    psbt.inputs
        .iter()
        .all(|i| i.final_script_sig.is_some() || i.final_script_witness.is_some())
}

/// Current Unix timestamp in seconds.
fn current_unix_secs() -> anyhow::Result<i64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64)
}

// ---------------------------------------------------------------------------
// Recipient parsing — shared by create_psbt and preview_psbt
// ---------------------------------------------------------------------------

/// Parsed form of one APIRecipient. Either a payment to an on-chain address
/// or an OP_RETURN data carrier (`address` empty, value forced to 0).
struct ParsedRecipient {
    /// Canonical address string for a payment, or empty for OP_RETURN.
    address: String,
    /// Output script. For OP_RETURN, an OP_RETURN <push> script.
    script: bdk_wallet::bitcoin::ScriptBuf,
    /// Original payload bytes when this is an OP_RETURN recipient.
    op_return_data: Option<Vec<u8>>,
}

/// Parse and validate every recipient in one pass.
///
/// Validations:
/// - At most 1 OP_RETURN recipient (Bitcoin standardness).
/// - OP_RETURN payload must fit a single push (≤ 520 bytes — `PushBytesBuf`
///   enforces this; relay policy is stricter at 83 bytes but we don't enforce
///   that here so app users can still craft non-standard data carriers if they
///   need to).
/// - OP_RETURN cannot be the `max_recipient_index` (drain_to has no meaning).
/// - Payment addresses must parse on the wallet's network.
fn parse_recipients(
    recipients: &[APIRecipient],
    network: bdk_wallet::bitcoin::Network,
    max_recipient_index: Option<u32>,
) -> Result<Vec<ParsedRecipient>> {
    use bdk_wallet::bitcoin::script::PushBytesBuf;
    use bdk_wallet::bitcoin::ScriptBuf;

    let op_return_count = recipients
        .iter()
        .filter(|r| r.op_return_data.is_some())
        .count();
    if op_return_count > 1 {
        return Err(anyhow::anyhow!("Only one OP_RETURN output allowed per tx"));
    }

    let mut out = Vec::with_capacity(recipients.len());
    for (i, r) in recipients.iter().enumerate() {
        if let Some(data) = &r.op_return_data {
            if Some(i as u32) == max_recipient_index {
                return Err(anyhow::anyhow!("OP_RETURN cannot receive remaining funds"));
            }
            let push = PushBytesBuf::try_from(data.clone()).map_err(|e| {
                anyhow::anyhow!("OP_RETURN payload exceeds single-push limit: {}", e)
            })?;
            out.push(ParsedRecipient {
                address: String::new(),
                script: ScriptBuf::new_op_return(&push),
                op_return_data: Some(data.clone()),
            });
        } else {
            let addr = crate::core::address::parse_address(&r.address, network)
                .map_err(|e| anyhow::anyhow!("Recipient {}: invalid address: {}", i + 1, e))?;
            out.push(ParsedRecipient {
                address: addr.to_string(),
                script: addr.script_pubkey(),
                op_return_data: None,
            });
        }
    }
    Ok(out)
}

/// Load and parse the wallet's spend paths from its stored descriptor.
fn load_spend_paths(
    conn: &rusqlite::Connection,
) -> anyhow::Result<Vec<crate::core::spend_path::SpendPath>> {
    let wallet_info = read_wallet_info(conn)?;
    crate::core::descriptor::DescriptorAnalyzer::analyze(&wallet_info.descriptor)
        .map_err(|e| anyhow::anyhow!("descriptor analysis failed: {}", e))?
        .spend_paths()
        .map_err(|e| anyhow::anyhow!("spend path extraction failed: {}", e))
}

impl APIWallet {
    // -----------------------------------------------------------------------
    // PSBT / coin-control
    // -----------------------------------------------------------------------

    /// Build an unsigned PSBT with optional coin control and spend-path selection.
    ///
    /// * `recipients`           — one or more outputs; each has an address and amount.
    /// * `max_recipient_index`  — if `Some(i)`, recipient at index `i` gets the wallet
    ///   remainder (drain_to); its `amount_sat` field is ignored.
    ///   Pass `None` when every amount is explicit.
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
        recipients: Vec<APIRecipient>,
        max_recipient_index: Option<u32>,
        fee_absolute_sat: u64,
        selected_utxos: Vec<APICoinControl>,
        policy_path: Vec<APIPolicyPath>,
        spend_path_id: u32,
        threshold: u32,
        mfps: Vec<String>,
    ) -> Result<APIPsbtInfo> {
        use bdk_wallet::bitcoin::Amount;
        use bdk_wallet::KeychainKind;
        use std::collections::BTreeMap;

        if recipients.is_empty() {
            return Err(anyhow::anyhow!("At least one recipient is required"));
        }

        let mut core = self.lock_wallet()?;
        let network = core.wallet.network();

        let policy_map: BTreeMap<String, Vec<usize>> = policy_path
            .into_iter()
            .map(|pp| {
                (
                    pp.policy_id,
                    pp.path.into_iter().map(|x| x as usize).collect(),
                )
            })
            .collect();

        let parsed_recipients = parse_recipients(&recipients, network, max_recipient_index)?;

        let resolved = resolve_selected_utxos(&core, &selected_utxos)?;

        let mut builder = core.wallet.build_tx();
        builder.fee_absolute(Amount::from_sat(fee_absolute_sat));

        for (i, (r, pr)) in recipients.iter().zip(parsed_recipients.iter()).enumerate() {
            if pr.op_return_data.is_some() {
                // OP_RETURN data carrier — value forced to 0.
                builder.add_recipient(pr.script.clone(), Amount::ZERO);
            } else if Some(i as u32) == max_recipient_index {
                // This recipient gets the remainder (send-max semantics).
                builder.drain_to(pr.script.clone());
                if resolved.is_empty() {
                    builder.drain_wallet();
                }
            } else {
                builder.add_recipient(pr.script.clone(), Amount::from_sat(r.amount_sat));
            }
        }
        if !resolved.is_empty() {
            for r in &resolved {
                if let Some((psbt_input, weight)) = &r.foreign {
                    builder.add_foreign_utxo(r.outpoint, psbt_input.clone(), *weight)?;
                } else {
                    builder.add_utxo(r.outpoint)?;
                }
            }
            builder.manually_selected_only();
        }

        if !policy_map.is_empty() {
            builder.policy_path(policy_map.clone(), KeychainKind::External);
            builder.policy_path(policy_map, KeychainKind::Internal);
        }

        let mut psbt = builder.finish()?;

        let has_foreign = resolved.iter().any(|r| r.foreign.is_some());
        apply_timelock_fixup(&mut psbt, &core.conn, spend_path_id, has_foreign);

        let fee_sat = psbt.fee()?.to_sat();
        let txid = psbt.unsigned_tx.compute_txid().to_string();
        let psbt_base64 = psbt_to_base64(&psbt);

        // Build final recipients list. For the drain recipient, read the actual output value.
        let final_recipients: Vec<APIRecipient> = recipients
            .iter()
            .zip(parsed_recipients.iter())
            .enumerate()
            .map(|(i, (r, pr))| {
                let amount_sat = if pr.op_return_data.is_some() {
                    0
                } else if Some(i as u32) == max_recipient_index {
                    psbt.unsigned_tx
                        .output
                        .iter()
                        .find(|o| o.script_pubkey == pr.script)
                        .map(|o| o.value.to_sat())
                        .unwrap_or(0)
                } else {
                    r.amount_sat
                };
                APIRecipient {
                    address: pr.address.clone(),
                    amount_sat,
                    op_return_data: pr.op_return_data.clone(),
                }
            })
            .collect();
        // Use the first non-OP_RETURN recipient as the canonical "primary" for storage.
        let primary_recipient = final_recipients
            .iter()
            .find(|r| r.op_return_data.is_none())
            .map(|r| r.address.clone())
            .unwrap_or_default();
        let total_amount_sat: u64 = final_recipients.iter().map(|r| r.amount_sat).sum();

        let recipients_json = serde_json::to_string(&final_recipients).ok();

        let utxo_max_conf_height = psbt_max_utxo_conf_height(&core.wallet, &psbt);

        ensure_unsigned_txs_table(&core.conn)?;
        let id = insert_psbt(
            &core.conn,
            &psbt_base64,
            &txid,
            None,
            &primary_recipient,
            total_amount_sat,
            fee_sat,
            spend_path_id,
            threshold,
            &mfps,
            recipients_json.as_deref(),
        )?;

        let created_at = current_unix_secs()?;
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let (effective_label, is_auto) =
            psbt_effective_label(&None, &primary_recipient, &addr_labels);
        let is_self_transfer = is_psbt_self_transfer(&core.wallet, &primary_recipient);

        Ok(APIPsbtInfo {
            id,
            psbt_base64,
            txid,
            label: None,
            effective_label,
            is_auto,
            is_self_transfer,
            created_at,
            recipient: primary_recipient,
            amount_sat: total_amount_sat,
            recipients: final_recipients,
            fee_sat,
            spend_path_id,
            threshold,
            mfps,
            utxo_max_conf_height,
            has_spent_inputs: false, // inputs were just selected and are confirmed unspent
        })
    }

    /// Preview the result of building an unsigned tx — fee, change, send, weight — without
    /// constructing or persisting a PSBT. Mirrors `create_psbt` inputs so the UI can show
    /// what BDK would actually do, and so a subsequent `create_psbt` produces matching numbers.
    ///
    /// Exactly one of `fee_rate_sat_per_vb` / `fee_absolute_sat` must be `Some`.
    ///
    /// `rbf_infos` (optional) lets the preview compute `rbf_min_fee_sats` — the BIP-125
    /// Rule 4 / PaysForRBF threshold for the *new* tx vsize. Pass the same RBF infos the UI
    /// already fetched per conflicting mempool tx; pass empty when not replacing anything.
    ///
    /// Insufficient-funds is returned as a flag in the preview rather than as an error, so
    /// the screen can render gracefully while the user is still typing amounts.
    #[frb(sync)]
    #[allow(clippy::too_many_arguments)]
    pub fn preview_psbt(
        &self,
        recipients: Vec<APIRecipient>,
        max_recipient_index: Option<u32>,
        fee_rate_sat_per_vb: Option<f64>,
        fee_absolute_sat: Option<u64>,
        selected_utxos: Vec<APICoinControl>,
        policy_path: Vec<APIPolicyPath>,
        spend_path_id: u32,
        rbf_infos: Vec<APIRbfInfo>,
    ) -> Result<APITxPreview> {
        use bdk_wallet::bitcoin::{Amount, FeeRate, ScriptBuf};
        use bdk_wallet::KeychainKind;
        use std::collections::BTreeMap;

        if recipients.is_empty() {
            return Err(anyhow::anyhow!("At least one recipient is required"));
        }
        match (fee_rate_sat_per_vb, fee_absolute_sat) {
            (Some(_), None) | (None, Some(_)) => {}
            _ => {
                return Err(anyhow::anyhow!(
                    "Exactly one of fee_rate_sat_per_vb / fee_absolute_sat must be set"
                ))
            }
        }

        let mut core = self.lock_wallet()?;
        let network = core.wallet.network();

        let parsed_recipients = parse_recipients(&recipients, network, max_recipient_index)?;

        let policy_map: BTreeMap<String, Vec<usize>> = policy_path
            .into_iter()
            .map(|pp| {
                (
                    pp.policy_id,
                    pp.path.into_iter().map(|x| x as usize).collect(),
                )
            })
            .collect();

        let resolved = resolve_selected_utxos(&core, &selected_utxos)?;

        // Per-path satisfaction weight from descriptor analysis. BDK's TxBuilder uses
        // `max_weight_to_satisfy()` for fee estimation, which over-estimates for taproot
        // multi-path descriptors (always returns the worst-case script-path weight even
        // when the user has selected the cheaper key-path). Use the spend path's
        // pre-computed actual weight so different paths produce different fees.
        let path_weights: Option<(u64, u64, u64)> = load_spend_paths(&core.conn)
            .ok()
            .and_then(|paths| paths.into_iter().find(|p| p.id == spend_path_id))
            .map(|sp| (sp.wu_base as u64, sp.wu_in as u64, sp.wu_out as u64));

        // Per-recipient output weight (constant — depends only on the address, not the path).
        let recipients_wu: u64 = parsed_recipients
            .iter()
            .map(|p| {
                bdk_wallet::bitcoin::TxOut {
                    value: bdk_wallet::bitcoin::Amount::ZERO,
                    script_pubkey: p.script.clone(),
                }
                .weight()
                .to_wu()
            })
            .sum();

        let n_inputs = resolved.len() as u64;
        let path_wu_no_change = path_weights.map(|(b, i, _)| b + n_inputs * i + recipients_wu);
        let path_wu_with_change =
            path_weights.map(|(b, i, o)| b + n_inputs * i + recipients_wu + o);

        // When given a rate, convert it to an absolute fee using the path's actual weight
        // so BDK builds with that exact fee instead of computing one from max_weight_to_satisfy.
        // For drain mode there's no change output, so use wu_no_change.
        let path_derived_fee_abs: Option<u64> = match (fee_rate_sat_per_vb, path_weights) {
            (Some(rate), Some(_)) => {
                let wu = if max_recipient_index.is_some() {
                    path_wu_no_change.unwrap()
                } else {
                    path_wu_with_change.unwrap()
                };
                Some((rate * wu as f64 / 4.0).ceil() as u64)
            }
            _ => None,
        };

        // Insufficient-funds preview: zero-filled, but with parsed recipients and rbf info.
        let insufficient_preview = || -> APITxPreview {
            APITxPreview {
                fee_sats: 0,
                fee_rate_sat_per_vb: fee_rate_sat_per_vb.unwrap_or(0.0),
                change_sats: 0,
                send_sats: 0,
                total_wu: 0,
                has_change: false,
                insufficient_funds: true,
                recipients: parsed_recipients
                    .iter()
                    .zip(recipients.iter())
                    .map(|(pr, r)| APIRecipient {
                        address: pr.address.clone(),
                        amount_sat: if pr.op_return_data.is_some() {
                            0
                        } else {
                            r.amount_sat
                        },
                        op_return_data: pr.op_return_data.clone(),
                    })
                    .collect(),
                rbf_min_fee_sats: None,
            }
        };

        let mut psbt = {
            let mut builder = core.wallet.build_tx();

            // Prefer the path-derived absolute fee so BDK does not size change using its
            // worst-case `max_weight_to_satisfy()`.
            if let Some(abs) = path_derived_fee_abs.or(fee_absolute_sat) {
                builder.fee_absolute(Amount::from_sat(abs));
            } else if let Some(rate) = fee_rate_sat_per_vb {
                let micro = (rate * 1000.0).round() as u64;
                let fr = FeeRate::from_sat_per_kwu(micro / 4);
                builder.fee_rate(fr);
            }

            for (i, (r, pr)) in recipients.iter().zip(parsed_recipients.iter()).enumerate() {
                if pr.op_return_data.is_some() {
                    builder.add_recipient(pr.script.clone(), Amount::ZERO);
                } else if Some(i as u32) == max_recipient_index {
                    builder.drain_to(pr.script.clone());
                    if resolved.is_empty() {
                        builder.drain_wallet();
                    }
                } else {
                    builder.add_recipient(pr.script.clone(), Amount::from_sat(r.amount_sat));
                }
            }
            if !resolved.is_empty() {
                for r in &resolved {
                    if let Some((psbt_input, weight)) = &r.foreign {
                        builder.add_foreign_utxo(r.outpoint, psbt_input.clone(), *weight)?;
                    } else {
                        builder.add_utxo(r.outpoint)?;
                    }
                }
                builder.manually_selected_only();
            }

            if !policy_map.is_empty() {
                builder.policy_path(policy_map.clone(), KeychainKind::External);
                builder.policy_path(policy_map, KeychainKind::Internal);
            }

            match builder.finish() {
                Ok(p) => p,
                Err(e) => {
                    let msg = format!("{e}").to_lowercase();
                    if msg.contains("insufficient")
                        || msg.contains("outputbelowdustlimit")
                        || msg.contains("dust")
                    {
                        return Ok(insufficient_preview());
                    }
                    return Err(anyhow::anyhow!("preview build failed: {}", e));
                }
            }
        };

        let has_foreign = resolved.iter().any(|r| r.foreign.is_some());
        apply_timelock_fixup(&mut psbt, &core.conn, spend_path_id, has_foreign);

        // Identify recipient outputs vs change.
        let recipient_scripts: std::collections::HashSet<ScriptBuf> =
            parsed_recipients.iter().map(|p| p.script.clone()).collect();
        let mut send_sats: u64 = 0;
        let mut change_sats: u64 = 0;
        for out in &psbt.unsigned_tx.output {
            if recipient_scripts.contains(&out.script_pubkey) {
                send_sats += out.value.to_sat();
            } else {
                change_sats += out.value.to_sat();
            }
        }
        let has_change = change_sats > 0;

        let fee_sats = psbt.fee()?.to_sat();

        // Total weight: prefer the per-path actual weight (so taproot key-path is
        // correctly cheaper than script-path). Fall back to BDK's max-based weight
        // when the spend path is unknown.
        let total_wu = if let (Some(no_change), Some(with_change)) =
            (path_wu_no_change, path_wu_with_change)
        {
            if has_change {
                with_change
            } else {
                no_change
            }
        } else {
            let base_wu = psbt.unsigned_tx.weight().to_wu();
            let mut sat_wu: u64 = 0;
            for r in &resolved {
                let w = if let Some((_, weight)) = &r.foreign {
                    weight.to_wu()
                } else {
                    let keychain = core
                        .wallet
                        .get_utxo(r.outpoint)
                        .map(|u| u.keychain)
                        .unwrap_or(KeychainKind::External);
                    core.wallet
                        .public_descriptor(keychain)
                        .max_weight_to_satisfy()
                        .map(|w| w.to_wu())
                        .unwrap_or(500)
                };
                sat_wu += w;
            }
            base_wu + sat_wu
        };
        let vbytes = (total_wu as f64) / 4.0;
        let effective_rate = if vbytes > 0.0 {
            fee_sats as f64 / vbytes
        } else {
            0.0
        };

        // Final recipients: drain recipient reads its actual assigned amount.
        let final_recipients: Vec<APIRecipient> = recipients
            .iter()
            .zip(parsed_recipients.iter())
            .enumerate()
            .map(|(i, (r, pr))| {
                let amount_sat = if pr.op_return_data.is_some() {
                    0
                } else if Some(i as u32) == max_recipient_index {
                    psbt.unsigned_tx
                        .output
                        .iter()
                        .find(|o| o.script_pubkey == pr.script)
                        .map(|o| o.value.to_sat())
                        .unwrap_or(0)
                } else {
                    r.amount_sat
                };
                APIRecipient {
                    address: pr.address.clone(),
                    amount_sat,
                    op_return_data: pr.op_return_data.clone(),
                }
            })
            .collect();

        // BIP-125 Rule 4 / PaysForRBF: replacement fee must strictly exceed
        // sum(orig_fee + descendant_fees) + new_vsize × 1 sat/vB.
        let rbf_min_fee_sats = if rbf_infos.is_empty() {
            None
        } else {
            let cluster: u64 = rbf_infos
                .iter()
                .map(|i| i.orig_fee_sat + i.descendant_fee_sat.unwrap_or(0))
                .sum();
            let new_vbytes = vbytes.ceil() as u64;
            Some(cluster + new_vbytes + 1)
        };

        Ok(APITxPreview {
            fee_sats,
            fee_rate_sat_per_vb: effective_rate,
            change_sats,
            send_sats,
            total_wu,
            has_change,
            insufficient_funds: false,
            recipients: final_recipients,
            rbf_min_fee_sats,
        })
    }

    /// Return all saved unsigned PSBTs for this wallet, newest-first.
    pub fn list_psbts(&self) -> Result<Vec<APIPsbtInfo>> {
        let core = self.lock_wallet()?;
        ensure_unsigned_txs_table(&core.conn)?;
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let valid_outpoints = build_valid_outpoints(&core.wallet);
        Ok(list_psbt_rows(&core.conn)?
            .into_iter()
            .map(|row| row_to_api_psbt(row, &core.wallet, &addr_labels, &valid_outpoints))
            .collect())
    }

    /// Delete a saved PSBT by id.
    #[frb(sync)]
    pub fn delete_psbt(&self, id: i64) -> Result<()> {
        let core = self.lock_wallet()?;
        delete_psbt_row(&core.conn, id)
    }

    /// Set or clear the label for a saved PSBT. Pass an empty string to clear.
    #[frb(sync)]
    pub fn set_psbt_label(&self, id: i64, label: String) -> Result<APIPsbtInfo> {
        let core = self.lock_wallet()?;
        let new_label = if label.is_empty() {
            None
        } else {
            Some(label.as_str())
        };
        update_psbt_label(&core.conn, id, new_label)?;
        let row = get_psbt_row(&core.conn, id)?;
        Ok(row_to_api_psbt_loaded(row, &core.conn, &core.wallet))
    }

    /// Merge partial signatures from a signed PSBT into the stored one.
    ///
    /// The signed PSBT must refer to the same transaction (same inputs/outputs).
    /// Returns the updated info.
    #[frb(sync)]
    pub fn merge_psbt(&self, id: i64, signed_psbt_base64: String) -> Result<APIPsbtInfo> {
        let core = self.lock_wallet()?;
        let row = get_psbt_row(&core.conn, id)?;

        let mut existing = psbt_from_base64(&row.psbt)?;
        let signed = psbt_from_base64(&signed_psbt_base64)?;
        existing.combine(signed)?;

        let merged_base64 = psbt_to_base64(&existing);
        update_psbt_data(&core.conn, id, &merged_base64)?;
        let updated_row = get_psbt_row(&core.conn, id)?;
        Ok(row_to_api_psbt_loaded(
            updated_row,
            &core.conn,
            &core.wallet,
        ))
    }

    /// Import a PSBT (base64) from an external source.
    ///
    /// If a record with the same unsigned txid already exists, the signatures are
    /// merged and the existing record is updated (`was_merged = true`).
    /// Otherwise a new record is created with metadata extracted from the PSBT.
    pub fn import_psbt(&self, psbt_base64: String) -> Result<APIImportPsbtResult> {
        let core = self.lock_wallet()?;
        ensure_unsigned_txs_table(&core.conn)?;

        let imported = psbt_from_base64(&psbt_base64)?;
        let txid = imported.unsigned_tx.compute_txid().to_string();

        // Merge with existing record if txid matches.
        if let Some(row) = get_psbt_row_by_txid(&core.conn, &txid)? {
            let mut existing = psbt_from_base64(&row.psbt)?;
            existing.combine(imported)?;
            let merged_base64 = psbt_to_base64(&existing);
            update_psbt_data(&core.conn, row.id, &merged_base64)?;
            let updated_row = get_psbt_row(&core.conn, row.id)?;
            return Ok(APIImportPsbtResult {
                psbt: row_to_api_psbt_loaded(updated_row, &core.conn, &core.wallet),
                was_merged: true,
            });
        }

        // New PSBT — extract metadata from the PSBT fields.
        let tx = &imported.unsigned_tx;

        // Identify external (non-wallet) outputs as the recipient.
        // For self-transfers with no external outputs, fall back to all outputs.
        let external_outputs: Vec<&bdk_wallet::bitcoin::TxOut> = tx
            .output
            .iter()
            .filter(|o| !core.wallet.is_mine(o.script_pubkey.clone()))
            .collect();
        let recipient_outputs: Vec<&bdk_wallet::bitcoin::TxOut> = if external_outputs.is_empty() {
            tx.output.iter().collect()
        } else {
            external_outputs
        };
        let import_recipients: Vec<APIRecipient> = recipient_outputs
            .iter()
            .map(|o| {
                if o.script_pubkey.is_op_return() {
                    return APIRecipient {
                        address: String::new(),
                        amount_sat: 0,
                        op_return_data: Some(crate::core::op_return::extract_op_return_payload(
                            &o.script_pubkey,
                        )),
                    };
                }
                let address = bdk_wallet::bitcoin::Address::from_script(
                    &o.script_pubkey,
                    core.wallet.network(),
                )
                .map(|a| a.to_string())
                .unwrap_or_default();
                APIRecipient {
                    address,
                    amount_sat: o.value.to_sat(),
                    op_return_data: None,
                }
            })
            .collect();
        let recipient = import_recipients
            .iter()
            .find(|r| r.op_return_data.is_none())
            .map(|r| r.address.clone())
            .unwrap_or_default();
        let amount_sat: u64 = import_recipients.iter().map(|r| r.amount_sat).sum();
        let recipients_json = serde_json::to_string(&import_recipients).ok();

        // Fee = witness_utxo input sum − output sum (best-effort).
        let input_sum: u64 = imported
            .inputs
            .iter()
            .filter_map(|i| i.witness_utxo.as_ref().map(|u| u.value.to_sat()))
            .sum();
        let output_sum: u64 = tx.output.iter().map(|o| o.value.to_sat()).sum();
        let fee_sat = input_sum.saturating_sub(output_sum);

        // Infer the spend path from nSequence / nLockTime.
        // BDK encodes the selected policy branch in every input's nSequence:
        //   - key-path or no timelock → bit 31 set (e.g. 0xFFFFFFFD) → rel_tl = 0
        //   - older(N) leaf           → bit 31 clear, value = N        → rel_tl = N
        // lock_time carries either a miniscript absolute timelock (after(N)) or BDK's
        // anti-fee-sniping block height. Only treat it as a real abs_timelock when some
        // descriptor spend path explicitly requires that exact value; otherwise ignore it.
        let first_seq = imported
            .unsigned_tx
            .input
            .first()
            .map(|i| i.sequence.0)
            .unwrap_or(0xFFFF_FFFF);
        let rel_tl = if first_seq & (1u32 << 31) == 0 {
            first_seq
        } else {
            0
        };
        let raw_abs = imported.unsigned_tx.lock_time.to_consensus_u32();

        let spend_paths = load_spend_paths(&core.conn)?;
        let abs_tl = if raw_abs > 0 && spend_paths.iter().any(|sp| sp.abs_timelock == raw_abs) {
            raw_abs
        } else {
            0
        };

        let matched_sp = spend_paths
            .into_iter()
            .find(|sp| sp.rel_timelock == rel_tl && sp.abs_timelock == abs_tl)
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "PSBT does not match any spending path of this wallet \
                     (nSequence={:#010x}, lock_time={})",
                    first_seq,
                    imported.unsigned_tx.lock_time
                )
            })?;

        let spend_path_id = matched_sp.id;
        let threshold = matched_sp.threshold as u32;
        let matched_mfps = matched_sp.mfps.clone();

        let id = insert_psbt(
            &core.conn,
            &psbt_base64,
            &txid,
            None,
            &recipient,
            amount_sat,
            fee_sat,
            spend_path_id,
            threshold,
            &matched_mfps,
            recipients_json.as_deref(),
        )?;

        let created_at = current_unix_secs()?;
        let utxo_max_conf_height = psbt_max_utxo_conf_height(&core.wallet, &imported);
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let (effective_label, is_auto) = psbt_effective_label(&None, &recipient, &addr_labels);
        let is_self_transfer = is_psbt_self_transfer(&core.wallet, &recipient);
        let valid_outpoints = build_valid_outpoints(&core.wallet);
        let has_spent_inputs = imported.unsigned_tx.input.iter().any(|txin| {
            !txin.previous_output.is_null() && !valid_outpoints.contains(&txin.previous_output)
        });

        Ok(APIImportPsbtResult {
            psbt: APIPsbtInfo {
                id,
                psbt_base64,
                txid,
                label: None,
                effective_label,
                is_auto,
                is_self_transfer,
                created_at,
                recipient,
                amount_sat,
                recipients: import_recipients,
                fee_sat,
                spend_path_id,
                threshold,
                mfps: matched_mfps,
                utxo_max_conf_height,
                has_spent_inputs,
            },
            was_merged: false,
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

        fn mark_signed(
            signed: &mut std::collections::HashMap<String, Vec<bool>>,
            mfp: &str,
            idx: usize,
        ) {
            if let Some(v) = signed.get_mut(mfp) {
                v[idx] = true;
            }
        }

        for (idx, input) in psbt.inputs.iter().enumerate() {
            // Non-taproot: bip32_derivation maps CompressedPublicKey → (Fingerprint, DerivPath)
            for (pk, (fingerprint, _)) in &input.bip32_derivation {
                let bpk = bdk_wallet::bitcoin::PublicKey::new(*pk);
                if input.partial_sigs.contains_key(&bpk) {
                    mark_signed(&mut signed, &fingerprint.to_string(), idx);
                }
            }

            // Taproot key-path: tap_key_sig present → internal key signed
            if input.tap_key_sig.is_some() {
                if let Some(tap_key) = input.tap_internal_key {
                    if let Some((_, ks)) = input.tap_key_origins.get(&tap_key) {
                        mark_signed(&mut signed, &ks.0.to_string(), idx);
                    }
                }
            }

            // Taproot script-path: tap_script_sigs keyed by (XOnlyPubKey, TapLeafHash)
            for (xpk, _) in input.tap_script_sigs.keys() {
                if let Some((_, ks)) = input.tap_key_origins.get(xpk) {
                    mark_signed(&mut signed, &ks.0.to_string(), idx);
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

        let is_finalized = is_psbt_finalized(&psbt);

        Ok(APIPsbtAnalysis {
            signers,
            is_finalized,
        })
    }

    /// Finalize the PSBT, broadcast via Electrum, and delete the local record.
    ///
    /// Returns the broadcast txid on success.
    pub async fn broadcast_psbt(&self, id: i64, electrum_url: String) -> Result<String> {
        let core = self.lock_wallet()?;
        let row = get_psbt_row(&core.conn, id)?;
        // Capture label before consuming the row.
        let psbt_label = row.label.clone();
        let mut psbt = psbt_from_base64(&row.psbt)?;

        // If not already finalized by signer, try to finalize via BDK/miniscript.
        // `finalize_psbt` / `sign` are deprecated in BDK 2.2.0 (signer module moved to
        // bitcoin::psbt), but no replacement exists for miniscript-aware finalization in 2.3.0.
        if !is_psbt_finalized(&psbt) {
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

        let client = create_electrum_client(&electrum_url)?;
        client.transaction_broadcast(&tx)?;

        // Apply the PSBT's label to the transaction before deleting the PSBT.
        if let Some(label) = &psbt_label {
            if !label.is_empty() && !tx_has_explicit_label(&core.conn, &txid.to_string())? {
                let _ = db_set_tx_label(&core.conn, &txid.to_string(), label, false, None);
            }
        }
        delete_psbt_row(&core.conn, id)?;
        drop(core);
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(txid.to_string())
    }

    /// Sign a stored PSBT using the hot key identified by `mfp`.
    ///
    /// Only the signer for the given master fingerprint is loaded, so BDK can
    /// never accidentally sign with a key the user did not intend. The PSBT is
    /// **never auto-finalized** (`try_finalize: false`) — the user explicitly
    /// controls finalization, which prevents premature finalization in multisig
    /// or complex Taproot setups where BDK might otherwise finalize on the first
    /// satisfied threshold.
    ///
    /// Returns the updated [`APIPsbtInfo`] with the partial signatures added.
    #[frb(sync)]
    pub fn sign_psbt_with_key(&self, psbt_id: i64, mfp: String) -> Result<APIPsbtInfo> {
        let mut core = self.lock_wallet()?;
        let row = get_psbt_row(&core.conn, psbt_id)?;
        let mut psbt = psbt_from_base64(&row.psbt)?;

        sign_psbt_in_place(&mut core, &mut psbt, &mfp)?;

        let updated_base64 = psbt_to_base64(&psbt);
        update_psbt_data(&core.conn, psbt_id, &updated_base64)?;

        let updated_row = row.with_psbt(updated_base64);
        Ok(row_to_api_psbt_loaded(
            updated_row,
            &core.conn,
            &core.wallet,
        ))
    }

    // -----------------------------------------------------------------------
    // On-chain backup — PSBT creation, signing, and broadcast
    // -----------------------------------------------------------------------

    /// Build the TX_COMMIT PSBT for an on-chain descriptor backup.
    ///
    /// Uses the live wallet (no extra connection). The PSBT is NOT stored in the
    /// wallet's `unsigned_txs` table — it is returned to Flutter to be signed and
    /// then passed directly to `finalize_backup`.
    ///
    /// `min_fee_rate` is the network's minimum relay fee rate. TX_COMMIT uses it
    /// as its fee rate (below relay standard so it cannot be mined alone).
    /// TX_REVEAL's fee is guaranteed to be at least `reveal_vbytes * min_fee_rate`.
    pub fn prepare_backup_psbt(
        &self,
        utxo_txids: Vec<String>,
        utxo_vouts: Vec<u32>,
        fee_rate_sat_per_vb: f64,
        min_fee_rate: f64,
        policy_path: Vec<APIPolicyPath>,
        spend_path_id: u32,
    ) -> Result<descriptor_backup::OnchainBackupPsbt> {
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        use bdk_wallet::bitcoin::{Address, Amount};
        use bdk_wallet::KeychainKind;
        use std::collections::BTreeMap;
        use std::str::FromStr as _;

        if utxo_txids.is_empty() || utxo_txids.len() != utxo_vouts.len() {
            return Err(anyhow::anyhow!(
                "At least one UTXO required; txids and vouts must be the same length"
            ));
        }

        let mut core = self.lock_wallet()?;
        let info = read_wallet_info(&core.conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();
        let descriptor = info.descriptor.clone();

        // Build the encrypted payload and derive the vault tapscript / address.
        let secp = Secp256k1::new();
        let triples = descriptor_backup::participant_triples(&descriptor);
        if triples.is_empty() {
            return Err(anyhow::anyhow!("Descriptor has no xpub keys"));
        }
        let triple_refs: Vec<(&str, &str, &str)> = triples
            .iter()
            .map(|(m, x, p)| (m.as_str(), x.as_str(), p.as_str()))
            .collect();
        let payload =
            descriptor_backup::build_encrypted_payload(&descriptor, &triple_refs, &info.name)?;
        let compressed = descriptor_backup::zstd_compress(&payload);
        let tapscript = descriptor_backup::vault_tapscript(&compressed);
        let vault_info = descriptor_backup::vault_taproot(&secp, &tapscript)?;
        let vault_addr = Address::p2tr(
            &secp,
            vault_info.internal_key(),
            vault_info.merkle_root(),
            network,
        );

        // Derive anchor addresses.
        let anchor_addrs: Vec<Address> = triples
            .iter()
            .map(|(_, xpub, _)| -> Result<_> {
                let x = bdk_wallet::bitcoin::bip32::Xpub::from_str(xpub)?;
                let k = descriptor_backup::derive_anchor_key(&secp, &x);
                Ok(descriptor_backup::anchor_p2tr_address(&secp, &k, network))
            })
            .collect::<Result<_>>()?;
        let n_anchors = anchor_addrs.len();
        let n_inputs = utxo_txids.len();

        // Compute fees (CPFP split).
        let commit_wu = descriptor_backup::commit_weight(n_inputs, n_anchors);
        let reveal_wu = descriptor_backup::reveal_weight(tapscript.len(), n_anchors);
        let (commit_fee, reveal_fee) = descriptor_backup::split_package_fees(
            commit_wu,
            reveal_wu,
            fee_rate_sat_per_vb,
            min_fee_rate,
        );
        let anchor_cost = descriptor_backup::ANCHOR_SATS * n_anchors as u64;
        let vault_sats = descriptor_backup::ANCHOR_SATS.max(reveal_fee.saturating_sub(anchor_cost));
        let package_vbytes = commit_wu.div_ceil(4) + reveal_wu.div_ceil(4);

        // Verify selected UTXOs exist and accumulate total sats.
        let coin_controls: Vec<APICoinControl> = utxo_txids
            .iter()
            .zip(utxo_vouts.iter())
            .map(|(txid, vout)| APICoinControl {
                txid: txid.clone(),
                vout: *vout,
            })
            .collect();
        let resolved = resolve_selected_utxos(&core, &coin_controls)?;

        let total_utxo_sats: u64 = resolved
            .iter()
            .map(|r| {
                core.wallet
                    .get_utxo(r.outpoint)
                    .map(|u| u.txout.value.to_sat())
                    .or_else(|| {
                        core.wallet
                            .tx_graph()
                            .get_txout(r.outpoint)
                            .map(|o| o.value.to_sat())
                    })
                    .unwrap_or(0)
            })
            .sum();

        let required = vault_sats + anchor_cost + commit_fee;
        let change_sat = total_utxo_sats.saturating_sub(required);

        if change_sat >= 330 {
            if total_utxo_sats < required + 330 {
                return Err(anyhow::anyhow!(
                    "Selected UTXOs too small ({total_utxo_sats} sats). Need at least {} sats to cover vault, anchors, fees, and a change output above dust (330 sats).",
                    required + 330
                ));
            }
        } else if total_utxo_sats < required.saturating_sub(329) {
            return Err(anyhow::anyhow!(
                "Selected UTXOs too small ({total_utxo_sats} sats). Need at least {} sats to cover vault, anchors, and fees (change below dust, burned to fees).",
                required.saturating_sub(329)
            ));
        }

        let change_addr = core
            .wallet
            .next_unused_address(KeychainKind::Internal)
            .address;

        // Apply policy path.
        let policy_map: BTreeMap<String, Vec<usize>> = policy_path
            .into_iter()
            .map(|pp| {
                (
                    pp.policy_id,
                    pp.path.into_iter().map(|x| x as usize).collect(),
                )
            })
            .collect();

        // Build TX_COMMIT PSBT.
        let mut builder = core.wallet.build_tx();
        builder.fee_absolute(Amount::from_sat(commit_fee));
        builder.add_recipient(vault_addr.script_pubkey(), Amount::from_sat(vault_sats));
        for addr in &anchor_addrs {
            builder.add_recipient(
                addr.script_pubkey(),
                Amount::from_sat(descriptor_backup::ANCHOR_SATS),
            );
        }
        if change_sat >= 330 {
            builder.add_recipient(change_addr.script_pubkey(), Amount::from_sat(change_sat));
        }
        for r in &resolved {
            if let Some((psbt_input, weight)) = &r.foreign {
                builder.add_foreign_utxo(r.outpoint, psbt_input.clone(), *weight)?;
            } else {
                builder.add_utxo(r.outpoint)?;
            }
        }
        builder.manually_selected_only();
        if !policy_map.is_empty() {
            builder.policy_path(policy_map.clone(), KeychainKind::External);
            builder.policy_path(policy_map, KeychainKind::Internal);
        }
        let mut psbt = builder.finish()?;

        let has_foreign = resolved.iter().any(|r| r.foreign.is_some());
        apply_timelock_fixup(&mut psbt, &core.conn, spend_path_id, has_foreign);

        core.persist()?;

        Ok(descriptor_backup::OnchainBackupPsbt {
            commit_psbt_base64: psbt_to_base64(&psbt),
            vault_tapscript_hex: hex::encode(tapscript.as_bytes()),
            commit_fee_sat: commit_fee,
            reveal_fee_sat: reveal_fee,
            vault_sats,
            anchor_cost_sat: anchor_cost,
            anchor_count: n_anchors as u32,
            change_sat,
            reveal_change_sat: vault_sats
                .saturating_add(anchor_cost)
                .saturating_sub(reveal_fee),
            package_vbytes,
        })
    }

    /// Sign the TX_COMMIT PSBT for an on-chain backup using a stored hot key.
    ///
    /// The PSBT is not stored in the wallet DB — it is ephemeral and returned
    /// directly to Flutter for passing to `finalize_backup`.
    #[frb(sync)]
    pub fn sign_backup_psbt(&self, psbt_base64: String, mfp: String) -> Result<String> {
        let mut core = self.lock_wallet()?;
        let mut psbt = psbt_from_base64(&psbt_base64)?;
        sign_psbt_in_place(&mut core, &mut psbt, &mfp)?;
        Ok(psbt_to_base64(&psbt))
    }

    /// Broadcast a signed TX_COMMIT and emit TX_REVEAL to complete the backup.
    ///
    /// Anchor keys are derived from the wallet's xpubs — no seed material needed.
    pub async fn finalize_backup(
        &self,
        signed_commit_psbt_base64: String,
        vault_tapscript_hex: String,
        reveal_fee_sat: u64,
        electrum_url: String,
    ) -> Result<descriptor_backup::OnchainBackupResult> {
        use bdk_electrum::electrum_client::ElectrumApi;
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        use bdk_wallet::bitcoin::ScriptBuf;
        use bdk_wallet::KeychainKind;
        use std::str::FromStr as _;

        let mut core = self.lock_wallet()?;
        let info = read_wallet_info(&core.conn)?;
        let descriptor = info.descriptor.clone();
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();

        let secp = Secp256k1::new();
        let tapscript = ScriptBuf::from_bytes(
            hex::decode(&vault_tapscript_hex)
                .map_err(|e| anyhow::anyhow!("Invalid vault tapscript hex: {e}"))?,
        );
        let vault_info = descriptor_backup::vault_taproot(&secp, &tapscript)?;
        let vault_script = bdk_wallet::bitcoin::Address::p2tr(
            &secp,
            vault_info.internal_key(),
            vault_info.merkle_root(),
            network,
        )
        .script_pubkey();

        let mut commit_psbt = psbt_from_base64(&signed_commit_psbt_base64)?;

        // Finalize via BDK/miniscript (same pattern as broadcast_psbt).
        if !is_psbt_finalized(&commit_psbt) {
            #[allow(deprecated)]
            let ok = core
                .wallet
                .finalize_psbt(&mut commit_psbt, bdk_wallet::SignOptions::default())?;
            anyhow::ensure!(ok, "TX_COMMIT cannot be finalized — not enough signatures");
        }

        let commit_tx = commit_psbt
            .extract_tx()
            .map_err(|e| anyhow::anyhow!("Failed to extract signed TX_COMMIT: {e}"))?;

        let triples = descriptor_backup::participant_triples(&descriptor);
        let n_anchors = triples.len();
        anyhow::ensure!(
            commit_tx.output.len() >= n_anchors + 2,
            "TX_COMMIT has unexpected output count (expected ≥ {})",
            n_anchors + 2
        );

        let anchor_keys: Vec<descriptor_backup::AnchorKey> = triples
            .iter()
            .map(|(_, xpub, _)| -> Result<_> {
                Ok(descriptor_backup::derive_anchor_key(
                    &secp,
                    &bdk_wallet::bitcoin::bip32::Xpub::from_str(xpub)?,
                ))
            })
            .collect::<Result<_>>()?;

        // Find actual output positions by scriptPubKey (BDK may shuffle output order).
        let vault_vout = commit_tx
            .output
            .iter()
            .position(|o| o.script_pubkey == vault_script)
            .ok_or_else(|| anyhow::anyhow!("Vault output not found in TX_COMMIT"))?
            as u32;

        let anchor_scripts: Vec<_> = anchor_keys
            .iter()
            .map(|k| descriptor_backup::anchor_p2tr_address(&secp, k, network).script_pubkey())
            .collect();
        let anchor_vouts: Vec<u32> = anchor_scripts
            .iter()
            .map(|s| {
                commit_tx
                    .output
                    .iter()
                    .position(|o| &o.script_pubkey == s)
                    .ok_or_else(|| anyhow::anyhow!("Anchor output not found in TX_COMMIT"))
                    .map(|i| i as u32)
            })
            .collect::<Result<_>>()?;

        let vault_txout = commit_tx.output[vault_vout as usize].clone();
        let anchor_txouts: Vec<bdk_wallet::bitcoin::TxOut> = anchor_vouts
            .iter()
            .map(|&i| commit_tx.output[i as usize].clone())
            .collect();

        let reveal_change_addr = core
            .wallet
            .next_unused_address(KeychainKind::Internal)
            .address;
        core.persist()?;
        drop(core);

        let client = create_raw_electrum_client(&electrum_url)?;
        let commit_txid = client
            .transaction_broadcast(&commit_tx)
            .map_err(|e| anyhow::anyhow!("TX_COMMIT broadcast failed: {e}"))?;

        let mut reveal_tx = descriptor_backup::build_reveal(
            commit_txid,
            vault_vout,
            &vault_txout,
            &anchor_vouts,
            &anchor_txouts,
            reveal_fee_sat,
            &reveal_change_addr,
        )?;
        descriptor_backup::sign_reveal(
            &secp,
            &mut reveal_tx,
            &vault_txout,
            &anchor_txouts,
            &vault_info,
            &tapscript,
            &anchor_keys,
        )?;

        let reveal_txid = client
            .transaction_broadcast(&reveal_tx)
            .map_err(|e| anyhow::anyhow!("TX_REVEAL broadcast failed: {e}"))?;

        Ok(descriptor_backup::OnchainBackupResult {
            commit_txid: commit_txid.to_string(),
            reveal_txid: reveal_txid.to_string(),
        })
    }

    /// Compute on-chain backup parameters from the already-open wallet.
    ///
    /// Pure local computation — no network, no DB re-open.
    /// Returns fee-size estimates and anchor addresses for live fee breakdown in Flutter.
    pub fn compute_backup_params(&self) -> Result<descriptor_backup::BackupParams> {
        use bdk_wallet::bitcoin::bip32::Xpub;
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        use bdk_wallet::bitcoin::Address;
        use std::str::FromStr as _;

        let core = self.lock_wallet()?;
        let info = read_wallet_info(&core.conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();
        let descriptor = info.descriptor.clone();
        drop(core);

        let secp = Secp256k1::new();
        let triples = descriptor_backup::participant_triples(&descriptor);
        let n = triples.len();
        if n == 0 {
            return Err(anyhow::anyhow!("Descriptor has no xpub keys"));
        }

        let triple_refs: Vec<(&str, &str, &str)> = triples
            .iter()
            .map(|(m, x, p)| (m.as_str(), x.as_str(), p.as_str()))
            .collect();
        let payload_json =
            descriptor_backup::build_encrypted_payload(&descriptor, &triple_refs, &info.name)?;
        let compressed_payload = descriptor_backup::zstd_compress(&payload_json);
        let tapscript = descriptor_backup::vault_tapscript(&compressed_payload);

        let commit_vbytes = descriptor_backup::commit_weight(1, n).div_ceil(4);
        let reveal_vbytes = descriptor_backup::reveal_weight(tapscript.len(), n).div_ceil(4);

        let anchor_addresses: Vec<String> = triples
            .iter()
            .map(|(_, xpub, _)| {
                let x = Xpub::from_str(xpub)?;
                let k = descriptor_backup::derive_anchor_key(&secp, &x);
                Ok(descriptor_backup::anchor_p2tr_address(&secp, &k, network).to_string())
            })
            .collect::<anyhow::Result<_>>()?;

        let vault_info = descriptor_backup::vault_taproot(&secp, &tapscript)?;
        let vault_addr = Address::p2tr(
            &secp,
            vault_info.internal_key(),
            vault_info.merkle_root(),
            network,
        );

        let (commit_fee, reveal_fee) =
            descriptor_backup::split_package_fees(commit_vbytes * 4, reveal_vbytes * 4, 0.1, 0.1);
        let anchor_cost = descriptor_backup::ANCHOR_SATS * n as u64;
        let vault_sats = descriptor_backup::ANCHOR_SATS.max(reveal_fee.saturating_sub(anchor_cost));
        let required = vault_sats + anchor_cost + commit_fee;
        let min_utxo_sats_base = if reveal_fee > anchor_cost {
            required + 330
        } else {
            required.saturating_sub(329)
        };

        Ok(descriptor_backup::BackupParams {
            commit_vbytes,
            reveal_vbytes,
            participant_count: n as u32,
            vault_address: vault_addr.to_string(),
            vault_tapscript_hex: hex::encode(tapscript.as_bytes()),
            anchor_addresses,
            min_utxo_sats_base,
        })
    }

    /// Check whether an on-chain backup already exists for this wallet.
    ///
    /// Uses the already-open wallet connection — no key derivation or DB re-open.
    /// Queries each participant's anchor address on Electrum, then finds the commit TX
    /// whose outputs cover **all** anchor addresses (unique fingerprint of this multisig).
    pub async fn check_backup_health(
        &self,
        electrum_url: String,
    ) -> Result<descriptor_backup::WalletBackupStatus> {
        use bdk_electrum::electrum_client::ElectrumApi;
        use bdk_wallet::bitcoin::bip32::Xpub;
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        use bdk_wallet::bitcoin::ScriptBuf;
        use std::collections::HashSet;
        use std::str::FromStr as _;

        let core = self.lock_wallet()?;
        let info = read_wallet_info(&core.conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();
        let descriptor = info.descriptor.clone();
        drop(core);

        let secp = Secp256k1::new();
        let triples = descriptor_backup::participant_triples(&descriptor);
        let n = triples.len();
        if n == 0 {
            return Err(anyhow::anyhow!("Descriptor has no xpub keys"));
        }

        // SHA-256 hash of the first receiving address from the wallet descriptor.
        // Used to verify that a discovered backup belongs to this wallet.
        let wallet_first_addr_hash =
            super::discovery::first_address_from_descriptor(descriptor.clone(), network.into())
                .map(super::discovery::sha256_hex)
                .unwrap_or_default();

        let anchor_spks: Vec<ScriptBuf> = triples
            .iter()
            .map(|(_, xpub, _)| {
                let x = Xpub::from_str(xpub)?;
                let k = descriptor_backup::derive_anchor_key(&secp, &x);
                Ok(descriptor_backup::anchor_p2tr_address(&secp, &k, network).script_pubkey())
            })
            .collect::<anyhow::Result<_>>()?;

        let not_found = descriptor_backup::WalletBackupStatus {
            found: false,
            commit_txid: None,
            reveal_txid: None,
            anchors_reachable: 0,
            anchors_total: n as u32,
            descriptor_verified: false,
        };

        let client = create_raw_electrum_client(&electrum_url)?;

        // Fetch all anchor histories once; reuse the results to count anchors_reachable.
        let anchor_histories: Vec<Vec<_>> = anchor_spks
            .iter()
            .map(|spk| {
                client
                    .script_get_history(spk.as_script())
                    .unwrap_or_default()
            })
            .collect();

        // Collect unique candidate txids preserving insertion order.
        let mut seen: HashSet<bdk_wallet::bitcoin::Txid> = HashSet::new();
        let mut candidate_txids: Vec<bdk_wallet::bitcoin::Txid> = Vec::new();
        for history in &anchor_histories {
            for item in history {
                if seen.insert(item.tx_hash) {
                    candidate_txids.push(item.tx_hash);
                }
            }
        }

        if candidate_txids.is_empty() {
            return Ok(not_found);
        }

        // Scan candidate commits from most recent to oldest. For each commit
        // that pays to all anchor addresses, try to decrypt the TX_REVEAL and
        // check whether its descriptor matches this wallet. The first match
        // wins; if none match the wallet's descriptor the backup is discarded.
        for txid in candidate_txids.iter().rev() {
            let tx = match client.transaction_get(txid) {
                Ok(tx) => tx,
                Err(_) => continue,
            };

            let out_spks: std::collections::HashSet<&ScriptBuf> =
                tx.output.iter().map(|o| &o.script_pubkey).collect();
            if !anchor_spks.iter().all(|spk| out_spks.contains(spk)) {
                continue;
            }

            let (reveal_txid_str, descriptor_verified) =
                match descriptor_backup::find_reveal_tx_for_commit(
                    &client,
                    &tx,
                    *txid,
                    &anchor_spks,
                ) {
                    Some((rtxid, rtx, _)) => {
                        let verified = triples.iter().any(|(_, xpub, _)| {
                            descriptor_backup::extract_descriptor_from_reveal(&rtx, xpub)
                                .ok()
                                .map(|(d, _, _)| {
                                    super::discovery::first_address_from_descriptor(
                                        d.clone(),
                                        network.into(),
                                    )
                                    .map(super::discovery::sha256_hex)
                                    .unwrap_or_default()
                                        == wallet_first_addr_hash
                                })
                                .unwrap_or(false)
                        });
                        (Some(rtxid.to_string()), verified)
                    }
                    None => (None, false),
                };

            if descriptor_verified {
                let anchors_reachable = anchor_histories
                    .iter()
                    .filter(|h| h.iter().any(|item| item.tx_hash == *txid))
                    .count() as u32;

                return Ok(descriptor_backup::WalletBackupStatus {
                    found: true,
                    commit_txid: Some(txid.to_string()),
                    reveal_txid: reveal_txid_str,
                    anchors_reachable,
                    anchors_total: n as u32,
                    descriptor_verified,
                });
            }
        }

        Ok(not_found)
    }
}

#[cfg(test)]
#[path = "psbt_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "psbt_op_return_tests.rs"]
mod op_return_tests;
