use super::*;

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
        recipient_address: String,
        amount_sat: u64,
        fee_rate_sat_per_vb: f64,
        selected_utxos: Vec<APICoinControl>,
        policy_path: Vec<APIPolicyPath>,
        spend_path_id: u32,
        threshold: u32,
        mfps: Vec<String>,
        send_max: bool,
    ) -> Result<APIPsbtInfo> {
        use bdk_wallet::bitcoin::{Address, Amount, FeeRate, OutPoint, Txid};
        use bdk_wallet::KeychainKind;
        use std::collections::BTreeMap;
        use std::str::FromStr;

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let network = core.wallet.network();
        let address = Address::from_str(&recipient_address)?.require_network(network)?;

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

        if send_max {
            // Drain all selected (or all wallet) funds to recipient, no change output.
            builder.drain_to(address.script_pubkey());
            if resolved.is_empty() {
                builder.drain_wallet();
            }
        } else {
            let amount = Amount::from_sat(amount_sat);
            builder.add_recipient(address.script_pubkey(), amount);
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

        let psbt = builder.finish()?;
        let fee_sat = psbt.fee()?.to_sat();
        let txid = psbt.unsigned_tx.compute_txid().to_string();
        let psbt_base64 = psbt_to_base64(&psbt);
        let recipient = address.to_string();

        // When send_max, read actual output amount from the PSBT.
        let actual_amount_sat = if send_max {
            let script = address.script_pubkey();
            psbt.unsigned_tx
                .output
                .iter()
                .find(|o| o.script_pubkey == script)
                .map(|o| o.value.to_sat())
                .unwrap_or(0)
        } else {
            amount_sat
        };

        let utxo_max_conf_height = psbt_max_utxo_conf_height(&core.wallet, &psbt);

        ensure_unsigned_txs_table(&core.conn)?;
        let id = insert_psbt(
            &core.conn,
            &psbt_base64,
            &txid,
            None,
            &recipient,
            actual_amount_sat,
            fee_sat,
            spend_path_id,
            threshold,
            &mfps,
        )?;

        let created_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs() as i64;
        let addr_labels = get_all_address_labels_with_flag(&core.conn).unwrap_or_default();
        let (effective_label, is_auto) = psbt_effective_label(&None, &recipient, &addr_labels);
        let is_self_transfer = is_psbt_self_transfer(&core.wallet, &recipient);

        Ok(APIPsbtInfo {
            id,
            psbt_base64,
            txid,
            label: None,
            effective_label,
            is_auto,
            is_self_transfer,
            created_at,
            recipient,
            amount_sat: actual_amount_sat,
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
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        delete_psbt_row(&core.conn, id)
    }

    /// Set or clear the label for a saved PSBT. Pass an empty string to clear.
    #[frb(sync)]
    pub fn set_psbt_label(&self, id: i64, label: String) -> Result<APIPsbtInfo> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
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
        let recipient = bdk_wallet::bitcoin::Address::from_script(
            &recipient_outputs[0].script_pubkey,
            core.wallet.network(),
        )
        .map(|a| a.to_string())
        .unwrap_or_default();
        let amount_sat: u64 = recipient_outputs.iter().map(|o| o.value.to_sat()).sum();

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
        )?;

        let created_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs() as i64;
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

        let is_finalized = psbt
            .inputs
            .iter()
            .all(|i| i.final_script_sig.is_some() || i.final_script_witness.is_some());

        Ok(APIPsbtAnalysis {
            signers,
            is_finalized,
        })
    }

    /// Finalize the PSBT, broadcast via Electrum, and delete the local record.
    ///
    /// Returns the broadcast txid on success.
    pub async fn broadcast_psbt(&self, id: i64, electrum_url: String) -> Result<String> {
        use bdk_electrum::{electrum_client, BdkElectrumClient};

        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let row = get_psbt_row(&core.conn, id)?;
        // Capture label before consuming the row.
        let psbt_label = row.label.clone();
        let mut psbt = psbt_from_base64(&row.psbt)?;

        // Reject broadcast if any input UTXO is unconfirmed (required for relative timelocks,
        // and generally invalid — unconfirmed inputs cannot be spent by the network).
        for txin in &psbt.unsigned_tx.input {
            if let Some(utxo) = core.wallet.get_utxo(txin.previous_output) {
                if !matches!(
                    utxo.chain_position,
                    bdk_wallet::chain::ChainPosition::Confirmed { .. }
                ) {
                    return Err(anyhow::anyhow!(
                        "Cannot broadcast: input {} is not yet confirmed. \
                         Wait for the funding transaction to confirm first.",
                        txin.previous_output
                    ));
                }
            }
        }

        // If not already finalized by signer, try to finalize via BDK/miniscript.
        let already_final = psbt
            .inputs
            .iter()
            .all(|i| i.final_script_sig.is_some() || i.final_script_witness.is_some());
        if !already_final {
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

        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);
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
            make_private_descriptor, mnemonic_to_root_xprv, root_xprv_to_mfp,
            split_multipath_descriptor, strip_descriptor_checksum, xprv_str_to_root_xprv,
        };
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        use bdk_wallet::{KeychainKind, Wallet};
        use std::sync::Arc;

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

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
        let root_xprv = if seed.seed_type == "mnemonic" {
            let mnemonic = seed
                .mnemonic
                .as_deref()
                .ok_or_else(|| anyhow::anyhow!("Mnemonic missing for seed"))?;
            mnemonic_to_root_xprv(mnemonic, &seed.passphrase, network)?
        } else {
            let xprv_str = seed
                .xprv
                .as_deref()
                .ok_or_else(|| anyhow::anyhow!("xprv missing for seed"))?;
            xprv_str_to_root_xprv(xprv_str)?
        };

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
            Ok(_) => eprintln!("sign_psbt_with_key: added partial sigs for {}", mfp),
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
