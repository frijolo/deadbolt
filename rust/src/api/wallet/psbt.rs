use super::*;

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

/// Collect unique master fingerprints from all inputs of a PSBT.
/// Covers both non-taproot (bip32_derivation) and taproot (tap_key_origins) inputs.
fn extract_mfps_from_psbt_inputs(inputs: &[bdk_wallet::bitcoin::psbt::Input]) -> Vec<String> {
    use std::collections::HashSet;
    let mut mfp_set: HashSet<String> = HashSet::new();
    for input in inputs {
        for (fp, _) in input.bip32_derivation.values() {
            mfp_set.insert(fp.to_string());
        }
        for (_, (fp, _)) in input.tap_key_origins.values() {
            mfp_set.insert(fp.to_string());
        }
    }
    mfp_set.into_iter().collect()
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
        fee_rate_sat_per_vb: f64,
        selected_utxos: Vec<APICoinControl>,
        policy_path: Vec<APIPolicyPath>,
        spend_path_id: u32,
        threshold: u32,
        mfps: Vec<String>,
    ) -> Result<APIPsbtInfo> {
        use bdk_wallet::bitcoin::{Address, Amount, FeeRate, OutPoint, Txid};
        use bdk_wallet::KeychainKind;
        use std::collections::BTreeMap;
        use std::str::FromStr;

        if recipients.is_empty() {
            return Err(anyhow::anyhow!("At least one recipient is required"));
        }

        let mut core = self.lock_wallet()?;
        let network = core.wallet.network();

        // float sat/vB → sat/kwu (1 sat/vB = 250 sat/kwu). Minimum 1 sat/kwu.
        let sat_per_kwu = ((fee_rate_sat_per_vb * 250.0).ceil() as u64).max(1);
        let fee_rate = FeeRate::from_sat_per_kwu(sat_per_kwu);

        let policy_map: BTreeMap<String, Vec<usize>> = policy_path
            .into_iter()
            .map(|pp| {
                (
                    pp.policy_id,
                    pp.path.into_iter().map(|x| x as usize).collect(),
                )
            })
            .collect();

        // Pre-resolve each selected UTXO before the builder borrows the wallet.
        // Coins spent by a mempool tx are absent from BDK's internal UTXO set;
        // we reconstruct them as foreign UTXOs from the tx graph (full-RBF).
        struct ResolvedUtxo {
            outpoint: OutPoint,
            /// Some → foreign (mempool) UTXO; None → normal internal UTXO.
            foreign: Option<(
                bdk_wallet::bitcoin::psbt::Input,
                bdk_wallet::bitcoin::Weight,
            )>,
        }
        let mut resolved: Vec<ResolvedUtxo> = Vec::with_capacity(selected_utxos.len());
        for coin in &selected_utxos {
            let outpoint = OutPoint::new(Txid::from_str(&coin.txid)?, coin.vout);
            if core.wallet.get_utxo(outpoint).is_some() {
                resolved.push(ResolvedUtxo {
                    outpoint,
                    foreign: None,
                });
            } else {
                // Not in the internal UTXO set — try the tx graph (mempool coin).
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
                // BIP-174: non-taproot segwit inputs (P2WPKH, P2WSH) must include
                // non_witness_utxo (full previous tx) in addition to witness_utxo.
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

        let mut builder = core.wallet.build_tx();
        builder.fee_rate(fee_rate);

        // Parse recipient addresses into (canonical_address_string, script_pubkey) pairs.
        use bdk_wallet::bitcoin::ScriptBuf;
        struct ParsedRecipient {
            address: String,
            script: ScriptBuf,
        }
        let parsed_recipients: Vec<ParsedRecipient> = recipients
            .iter()
            .enumerate()
            .map(|(i, r)| {
                let addr = Address::from_str(&r.address)
                    .map_err(|e| anyhow::anyhow!("Recipient {}: invalid address: {}", i + 1, e))?
                    .require_network(network)
                    .map_err(|e| anyhow::anyhow!("Recipient {}: wrong network: {}", i + 1, e))?;
                Ok(ParsedRecipient {
                    address: addr.to_string(),
                    script: addr.script_pubkey(),
                })
            })
            .collect::<anyhow::Result<Vec<_>>>()?;

        for (i, (r, pr)) in recipients.iter().zip(parsed_recipients.iter()).enumerate() {
            if Some(i as u32) == max_recipient_index {
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

        // Fixup: BDK does not apply policy_path nSequence/nLockTime to foreign UTXOs.
        // Coins in "spending" state (mempool) are added via add_foreign_utxo and receive
        // the default ENABLE_RBF_NO_LOCKTIME sequence (0xFFFFFFFD, bit 31 = 1).
        // OP_CSV requires bit 31 to be 0 (relative locktime enabled); with bit 31 set,
        // Bitcoin Core rejects the broadcast with "Locktime requirement not satisfied".
        //
        // When any input is foreign and the spend path has a relative/absolute timelock,
        // we patch the unsigned_tx fields before computing the txid.
        let has_foreign = resolved.iter().any(|r| r.foreign.is_some());
        if has_foreign && spend_path_id != 0 {
            use crate::core::descriptor::DescriptorAnalyzer;
            let info = read_wallet_info(&core.conn)?;
            if let Ok(analyzer) = DescriptorAnalyzer::analyze(&info.descriptor) {
                if let Ok(core_sps) = analyzer.spend_paths() {
                    if let Some(sp) = core_sps.iter().find(|sp| sp.id == spend_path_id) {
                        if sp.rel_timelock > 0 {
                            let seq = bdk_wallet::bitcoin::Sequence(sp.rel_timelock);
                            for txin in &mut psbt.unsigned_tx.input {
                                txin.sequence = seq;
                            }
                        }
                        if sp.abs_timelock > 0 {
                            psbt.unsigned_tx.lock_time =
                                bdk_wallet::bitcoin::absolute::LockTime::from_consensus(
                                    sp.abs_timelock,
                                );
                        }
                    }
                }
            }
        }

        let fee_sat = psbt.fee()?.to_sat();
        let txid = psbt.unsigned_tx.compute_txid().to_string();
        let psbt_base64 = psbt_to_base64(&psbt);

        // Build final recipients list. For the drain recipient, read the actual output value.
        let final_recipients: Vec<APIRecipient> = recipients
            .iter()
            .zip(parsed_recipients.iter())
            .enumerate()
            .map(|(i, (r, pr))| {
                let amount_sat = if Some(i as u32) == max_recipient_index {
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
                }
            })
            .collect();
        let primary_recipient = final_recipients[0].address.clone();
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
        let mfps = extract_mfps_from_psbt_inputs(&imported.inputs);

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
                let address = bdk_wallet::bitcoin::Address::from_script(
                    &o.script_pubkey,
                    core.wallet.network(),
                )
                .map(|a| a.to_string())
                .unwrap_or_default();
                APIRecipient {
                    address,
                    amount_sat: o.value.to_sat(),
                }
            })
            .collect();
        let recipient = import_recipients
            .first()
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

        let threshold = mfps.len().max(1) as u32;
        let id = insert_psbt(
            &core.conn,
            &psbt_base64,
            &txid,
            None,
            &recipient,
            amount_sat,
            fee_sat,
            0,
            threshold,
            &mfps,
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
                spend_path_id: 0,
                threshold,
                mfps,
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
            for (xpk, _) in input.tap_script_sigs.keys() {
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
        use crate::core::seed::{
            make_private_descriptor, root_xprv_to_mfp, seed_entry_to_root_xprv,
            split_multipath_descriptor, strip_descriptor_checksum,
        };
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        use bdk_wallet::{KeychainKind, Wallet};
        use std::sync::Arc;

        let mut core = self.lock_wallet()?;

        // Find the seed entry for this MFP.
        let seeds = list_seed_entries(&core.conn)?;
        let seed = seeds
            .iter()
            .find(|s| s.mfp == mfp)
            .ok_or_else(|| anyhow::anyhow!("No signing key with MFP {} found", mfp))?;

        let info = read_wallet_info(&core.conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();
        let secp = Secp256k1::new();

        // Derive the root xprv from the stored seed.
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

        // Build a private descriptor for this key and extract properly-
        // contextualized signers via a temporary in-memory wallet.
        let private_desc = make_private_descriptor(&info.descriptor, &root_xprv, &secp)
            .map_err(|e| anyhow::anyhow!("make_private_descriptor failed for {}: {}", mfp, e))?;
        let private_desc = strip_descriptor_checksum(&private_desc);

        // Split multi-path descriptor (<n;m> → /n/ for external, /m/ for internal).
        let (ext_desc, int_desc) = split_multipath_descriptor(&private_desc);

        let temp = Wallet::create(ext_desc, int_desc)
            .network(network)
            .create_wallet_no_persist()
            .map_err(|e| anyhow::anyhow!("Failed to build signer for {}: {}", mfp, e))?;

        // Add only the signer for this MFP.
        // `get_signers` / `add_signer` / `SignerOrdering` / `sign` are deprecated in BDK 2.2.0
        // (signer module moved to bitcoin::psbt). No stable replacement for runtime signer
        // injection exists in BDK 2.3.0; remove once BDK provides one.
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

        // Sign — never auto-finalize so the user controls when to finalize.
        let row = get_psbt_row(&core.conn, psbt_id)?;
        let mut psbt = psbt_from_base64(&row.psbt)?;

        #[allow(deprecated)]
        match core.wallet.sign(
            &mut psbt,
            bdk_wallet::SignOptions {
                trust_witness_utxo: true,
                try_finalize: false,
                ..Default::default()
            },
        ) {
            Ok(_) => {}
            Err(e) => return Err(anyhow::anyhow!("Signing failed for {}: {}", mfp, e)),
        }

        // Clear signers — keep the wallet watch-only between signing calls.
        core.wallet
            .set_keymap(KeychainKind::External, Default::default());
        core.wallet
            .set_keymap(KeychainKind::Internal, Default::default());

        // Persist the updated PSBT.
        let updated_base64 = psbt_to_base64(&psbt);
        update_psbt_data(&core.conn, psbt_id, &updated_base64)?;

        let updated_row = row.with_psbt(updated_base64);
        Ok(row_to_api_psbt_loaded(
            updated_row,
            &core.conn,
            &core.wallet,
        ))
    }
}
