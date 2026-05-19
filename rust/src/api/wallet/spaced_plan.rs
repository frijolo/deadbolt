// FFI entry point for spaced TX planning.
//
// Builds the plan (one PSBT per confirmed source UTXO) and persists the
// `tx_plans` row in `DRAFT` status. Child PSBTs are inserted with
// `auto_broadcast = 0`; `commit_spaced_plan` flips the flag once the
// bundle is fully signed.
//
// Output structure per intent:
//   - 1 output by default (drain to the UTXO's allocated destination).
//   - 2 outputs when the planner sampled `SplitIntent::Try { ratio }`
//     and the post-fee gate (§3) passes. The second address is the next
//     entry in `dst_addresses`; on a 2-output split the address cursor
//     advances by 2. Falls back to 1 output if the gate fails or the
//     2-output preview would push either output below dust.
//
// Destination addresses are caller-supplied: the cubit peeks them from
// the destination wallet before calling. The FFI is wallet-local and
// never opens the destination DB. When `split_probability > 0` the
// caller must supply at least `2 * eligible_utxo_count` addresses
// (worst case every UTXO splits).

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;

use crate::api::model::{
    APIBatchSignFailure, APIBatchSignReport, APICoinControl, APICommitSpacedPlanReport, APINetwork,
    APIRecipient, APISignedChildPsbt, APISpacedPlanAddressLabel, APISpacedPlanChildPsbt,
    APISpacedPlanDetail, APISpacedPlanDetailRow, APISpacedPlanParams, APISpacedPlanRow,
    APISpacedPlanSigningBundle, APISpacedPlanSummary,
};
use crate::api::wallet::spaced_planner::{
    plan_intents, split_passes_gate, PlannerParams, PlannerUtxo, SplitIntent,
};
use crate::api::wallet::APIWallet;
use crate::core::wallet_persistence::labels::{
    address_has_explicit_label, get_coin_label_with_flag, set_address_label,
};
use crate::core::wallet_persistence::propagation::set_address_if_none;
use crate::core::wallet_persistence::psbt_storage::{
    delete_psbt_row, get_psbt_row, set_psbt_auto_broadcast as db_set_psbt_auto_broadcast,
    update_psbt_label,
};
use crate::core::wallet_persistence::tx_plan_storage::{
    delete_tx_plan, get_tx_plan, has_active_tx_plan, insert_tx_plan, list_tx_plans,
    list_unsigned_tx_ids_for_plan, set_tx_plan_status, set_unsigned_tx_plan_id, NewTxPlan,
    TxPlanKind, TxPlanRow, TxPlanStatus,
};

/// Minimum sat-value for the single output of a 1-input-1-output tx.
/// Standardness rejects below 546 (P2WPKH); using that as the floor
/// across script types is a conservative bound.
const PLAN_DUST_THRESHOLD_SAT: u64 = 546;

impl APIWallet {
    /// Build a spaced TX plan over every confirmed UTXO of this wallet.
    ///
    /// Persists a new `tx_plans` row (status `DRAFT`) and one
    /// `unsigned_txs` row per non-dropped intent. Returns a summary the
    /// UI can render directly — no extra reads needed.
    ///
    /// Errors out when:
    ///   - this wallet already has an active plan;
    ///   - the planner params are invalid;
    ///   - no confirmed UTXOs are eligible;
    ///   - `dst_addresses.len() < eligible_utxo_count`;
    ///   - every eligible UTXO yields a dust output at the chosen feerate
    ///     range (rolls the plan row back so the user can retry without
    ///     a separate cancel call).
    #[frb(sync)]
    pub fn plan_spaced_txs(&self, params: APISpacedPlanParams) -> Result<APISpacedPlanSummary> {
        // 1. Active-plan guard. Run before any other work so a misconfigured
        //    re-entry fails fast.
        {
            let core = self.lock_wallet()?;
            if has_active_tx_plan(&core.conn)? {
                return Err(anyhow!(
                    "This wallet already has an active plan; cancel it first"
                ));
            }
        }

        // 2. Derive plan kind from destination identity, then validate the
        //    planner params. REFRESH = "destination is the source itself"
        //    (empty path or matching path); everything else is MIGRATE. The
        //    planning logic is identical for both modes — the label is only
        //    persisted for history rendering.
        let kind = if params.dst_wallet_path.is_empty() || params.dst_wallet_path == self.path {
            TxPlanKind::Refresh
        } else {
            TxPlanKind::Migrate
        };
        let planner_params = PlannerParams {
            feerate_min_msatvb: params.feerate_min_msatvb,
            feerate_max_msatvb: params.feerate_max_msatvb,
            delay_blocks_min: params.delay_blocks_min,
            delay_blocks_max: params.delay_blocks_max,
            split_probability: params.split_probability,
            min_split_output: params.min_split_output,
        };
        planner_params.validate()?;

        // 3. Collect confirmed UTXOs + read tip + rel-timelock of the chosen path.
        let (planner_utxos, tip_height, rel_timelock_blocks) =
            self.collect_planner_inputs(&params)?;

        if planner_utxos.is_empty() {
            return Err(anyhow!("No confirmed UTXOs available"));
        }
        // Address budget: every UTXO may emit up to 2 outputs when split is
        // enabled, so require 2*N upfront. With `split_probability == 0`
        // requiring 2*N is wasteful; allow N in that case.
        let required_addrs = if params.split_probability > 0.0 {
            planner_utxos.len().saturating_mul(2)
        } else {
            planner_utxos.len()
        };
        if params.dst_addresses.len() < required_addrs {
            return Err(anyhow!(
                "Need at least {} destination addresses, got {}",
                required_addrs,
                params.dst_addresses.len()
            ));
        }

        // 4. Pure planner: shuffle + per-intent delay/feerate/split sampling.
        let intents = run_planner(
            planner_utxos,
            &planner_params,
            tip_height,
            rel_timelock_blocks,
            params.rng_seed,
        )?;

        // 5. Persist plan in DRAFT (before building PSBTs so child rows can be
        //    linked atomically per insert).
        let plan_id = {
            let core = self.lock_wallet()?;
            insert_tx_plan(
                &core.conn,
                &NewTxPlan {
                    kind,
                    dst_wallet_path: params.dst_wallet_path.clone(),
                    spend_path_id: params.spend_path_id,
                    feerate_min_msatvb: params.feerate_min_msatvb,
                    feerate_max_msatvb: params.feerate_max_msatvb,
                    delay_blocks_min: params.delay_blocks_min,
                    delay_blocks_max: params.delay_blocks_max,
                    split_probability: params.split_probability,
                    min_split_output: params.min_split_output,
                },
            )?
        };

        // 6. Build + persist one PSBT per intent. Each call rolls back the
        //    plan on a hard failure to avoid leaving an unusable DRAFT
        //    or orphan label rows.
        let summary = match self.build_intent_psbts(plan_id, kind, tip_height, &params, intents) {
            Ok(s) => s,
            Err(e) => {
                let core = self.lock_wallet()?;
                let _ = clear_plan_auto_labels(&core.conn, plan_id);
                let _ = delete_tx_plan(&core.conn, plan_id);
                return Err(e);
            }
        };

        if summary.rows.is_empty() {
            let core = self.lock_wallet()?;
            // Defensive — no propagation runs for dust-only intents, but
            // the cleanup is cheap and removes any future-proofing risk.
            let _ = clear_plan_auto_labels(&core.conn, plan_id);
            let _ = delete_tx_plan(&core.conn, plan_id);
            return Err(anyhow!(
                "Every eligible UTXO produced a dust output at the chosen feerate range"
            ));
        }

        Ok(summary)
    }

    /// Verify every child PSBT of a `DRAFT` plan is fully signed and arm it
    /// for auto-broadcast.
    ///
    /// A child counts as "signed" when either its PSBT is already finalised
    /// (BDK's `final_script_witness` / `final_script_sig` present) or at
    /// least `threshold` MFPs have a partial signature on every input
    /// (driven by `analyze_psbt` so the check matches what the UI shows).
    ///
    /// Reports the per-PSBT status instead of erroring on the partial case
    /// so the cubit can render the missing-signers UI without parsing the
    /// error string. The plan transition to `SIGNED` only happens when
    /// `committed == true`.
    ///
    /// Idempotent on a plan already in `SIGNED`: no state change, returns a
    /// report with `committed == true` and zero unsigned ids.
    #[frb(sync)]
    pub fn commit_spaced_plan(&self, plan_id: i64) -> Result<APICommitSpacedPlanReport> {
        // 1. Load plan + child ids in one critical section.
        let (status, child_ids) = {
            let core = self.lock_wallet()?;
            let plan = get_tx_plan(&core.conn, plan_id)?
                .ok_or_else(|| anyhow!("Plan {plan_id} not found"))?;
            let ids = list_unsigned_tx_ids_for_plan(&core.conn, plan_id)?;
            (plan.status, ids)
        };
        match status {
            TxPlanStatus::Draft | TxPlanStatus::Signed => {}
            other => {
                return Err(anyhow!(
                    "Plan {plan_id} is in state {:?}; commit requires DRAFT",
                    other
                ));
            }
        }
        if child_ids.is_empty() {
            return Err(anyhow!("Plan {plan_id} has no child PSBTs"));
        }

        let total_count = child_ids.len() as u32;

        // 2. Per-PSBT signature audit. Inspect outside the lock since
        //    `analyze_psbt` locks internally and we don't need a coherent
        //    snapshot — once auto_broadcast is off there is no other writer
        //    racing the row.
        let mut signed_ids: Vec<i64> = Vec::new();
        let mut unsigned_ids: Vec<i64> = Vec::new();
        for id in &child_ids {
            let (psbt_b64, threshold, mfps) = {
                let core = self.lock_wallet()?;
                let row = get_psbt_row(&core.conn, *id)?;
                (row.psbt, row.threshold, row.mfps.clone())
            };
            let analysis = self.analyze_psbt(psbt_b64, mfps)?;
            let signed_count = analysis.signers.iter().filter(|s| s.has_signed).count() as u32;
            if analysis.is_finalized || signed_count >= threshold {
                signed_ids.push(*id);
            } else {
                unsigned_ids.push(*id);
            }
        }

        if !unsigned_ids.is_empty() {
            return Ok(APICommitSpacedPlanReport {
                plan_id,
                committed: false,
                total_count,
                signed_count: signed_ids.len() as u32,
                unsigned_psbt_ids: unsigned_ids,
            });
        }

        // 3. All signed — flip auto_broadcast on every child and move the
        //    plan to SIGNED. Both writes share a single lock so a crash
        //    cannot leave the flag set on some PSBTs while the plan stays
        //    in DRAFT (which would otherwise look like "armed PSBTs without
        //    a parent plan" in the running view).
        {
            let core = self.lock_wallet()?;
            for id in &signed_ids {
                db_set_psbt_auto_broadcast(&core.conn, *id, true)?;
            }
            if status == TxPlanStatus::Draft {
                set_tx_plan_status(&core.conn, plan_id, TxPlanStatus::Signed)?;
            }
        }

        Ok(APICommitSpacedPlanReport {
            plan_id,
            committed: true,
            total_count,
            signed_count: total_count,
            unsigned_psbt_ids: vec![],
        })
    }

    /// Bundle every pending child PSBT of a plan together with plan-level
    /// signing context (descriptor, threshold, key-change map). The cubit
    /// uses this in a single call so the batch sign UI never has to
    /// re-open the wallet per PSBT.
    ///
    /// The plan must be in `DRAFT` or `SIGNED`. `SIGNED` is allowed so the
    /// UI can re-render the batch after a partial-sign attempt without
    /// reverting to DRAFT.
    ///
    /// Empty plans (no pending children) return an error so the caller
    /// surfaces "nothing to sign" explicitly instead of an empty list.
    #[frb(sync)]
    pub fn prepare_spaced_plan_psbts(&self, plan_id: i64) -> Result<APISpacedPlanSigningBundle> {
        let child_ids = self.assert_plan_signable(plan_id)?;

        // 1. Plan-level context: descriptor / spend path read under a
        //    fresh lock. `assert_plan_signable` already verified status,
        //    so the second read can't see a mid-flight cancel.
        let (descriptor, network, threshold, mfps, key_changes) = {
            let core = self.lock_wallet()?;
            let plan = get_tx_plan(&core.conn, plan_id)?
                .ok_or_else(|| anyhow!("Plan {plan_id} not found"))?;
            let info = crate::core::wallet_persistence::read_wallet_info(&core.conn)?;
            let network = APINetwork::try_from(info.network.as_str())?;
            let paths = core.cached_spend_paths()?;
            let path = paths
                .iter()
                .find(|p| p.id == plan.spend_path_id)
                .ok_or_else(|| {
                    anyhow!("Spend path {} not found on this wallet", plan.spend_path_id)
                })?;
            let key_changes: std::collections::HashMap<String, u32> = path
                .key_changes
                .iter()
                .map(|(mfp, idx)| (mfp.clone(), *idx))
                .collect();
            (
                info.descriptor,
                network,
                path.threshold as u32,
                path.mfps.clone(),
                key_changes,
            )
        };

        // 2. Per-child read + signature analysis. `analyze_psbt` operates
        //    on raw bytes (no wallet lock), so each child is independent.
        let mut children = Vec::with_capacity(child_ids.len());
        for id in &child_ids {
            let (psbt_b64, child_mfps) = {
                let core = self.lock_wallet()?;
                let row = get_psbt_row(&core.conn, *id)?;
                (row.psbt, row.mfps.clone())
            };
            let analysis = self.analyze_psbt(psbt_b64.clone(), child_mfps)?;
            children.push(APISpacedPlanChildPsbt {
                psbt_id: *id,
                psbt_b64,
                signers: analysis.signers,
                is_finalized: analysis.is_finalized,
            });
        }

        Ok(APISpacedPlanSigningBundle {
            plan_id,
            descriptor,
            network,
            threshold,
            mfps,
            key_changes,
            children,
        })
    }

    /// Sign every pending child PSBT of a plan with the hot key
    /// identified by `mfp`. Each row is signed in its own critical
    /// section by reusing [`sign_psbt_with_key`]; partial failures
    /// **do not** roll back already-signed children — the failed list
    /// is returned so the UI can offer a retry.
    ///
    /// The plan must be in `DRAFT` or `SIGNED`. The plan status is
    /// **not** mutated — `commit_spaced_plan` remains the only state
    /// transition. An empty plan errors out so the caller surfaces
    /// "nothing to sign" instead of an empty `signed_ids`.
    #[frb(sync)]
    pub fn sign_spaced_plan_with_hot_key(
        &self,
        plan_id: i64,
        mfp: String,
    ) -> Result<APIBatchSignReport> {
        let child_ids = self.assert_plan_signable(plan_id)?;
        let total = child_ids.len() as u32;

        let mut signed_ids = Vec::new();
        let mut failed = Vec::new();
        for id in child_ids {
            match self.sign_psbt_with_key(id, mfp.clone()) {
                Ok(_) => signed_ids.push(id),
                Err(e) => failed.push(APIBatchSignFailure {
                    psbt_id: id,
                    error: e.to_string(),
                }),
            }
        }
        Ok(APIBatchSignReport {
            plan_id,
            total,
            signed_ids,
            failed,
        })
    }

    /// Merge externally-signed PSBTs (HW device output / QR import /
    /// envelope) into the matching children of a plan. Each entry must
    /// reference a child of `plan_id`; entries whose `psbt_id` is not in
    /// the plan are reported under `failed`. Merge errors are also
    /// reported per-row and never abort the batch.
    ///
    /// The plan status is unchanged. Children whose ids do not appear in
    /// `signed` are left untouched and are absent from both
    /// `signed_ids` and `failed` (mirroring the batch contract — the
    /// report covers the batch the caller submitted, not the whole plan).
    #[frb(sync)]
    pub fn apply_spaced_plan_signed_psbts(
        &self,
        plan_id: i64,
        signed: Vec<APISignedChildPsbt>,
    ) -> Result<APIBatchSignReport> {
        let owned = self.assert_plan_signable(plan_id)?;
        let total = signed.len() as u32;
        let owned_set: std::collections::HashSet<i64> = owned.into_iter().collect();

        let mut signed_ids = Vec::new();
        let mut failed = Vec::new();
        for entry in signed {
            if !owned_set.contains(&entry.psbt_id) {
                failed.push(APIBatchSignFailure {
                    psbt_id: entry.psbt_id,
                    error: format!("PSBT {} does not belong to plan {plan_id}", entry.psbt_id),
                });
                continue;
            }
            match self.merge_psbt(entry.psbt_id, entry.signed_b64) {
                Ok(_) => signed_ids.push(entry.psbt_id),
                Err(e) => failed.push(APIBatchSignFailure {
                    psbt_id: entry.psbt_id,
                    error: e.to_string(),
                }),
            }
        }
        Ok(APIBatchSignReport {
            plan_id,
            total,
            signed_ids,
            failed,
        })
    }

    /// True when this wallet has a plan in any active state
    /// (DRAFT / SIGNED / RUNNING). Used by the cubit to gate the
    /// "Plan spaced transactions…" menu entry.
    #[frb(sync)]
    pub fn has_active_spaced_plan(&self) -> Result<bool> {
        let core = self.lock_wallet()?;
        has_active_tx_plan(&core.conn)
    }

    /// List every plan ever created in this wallet, newest first.
    /// Terminal-state plans are kept for history (a CANCELLED row tells
    /// the user why their "Plan…" menu was greyed out earlier).
    #[frb(sync)]
    pub fn list_spaced_plans(&self) -> Result<Vec<APISpacedPlanDetail>> {
        let plans = {
            let core = self.lock_wallet()?;
            list_tx_plans(&core.conn)?
        };
        let mut out = Vec::with_capacity(plans.len());
        for plan in plans {
            out.push(self.assemble_plan_detail(plan)?);
        }
        Ok(out)
    }

    /// Fetch one plan plus the children still in `unsigned_txs`. Errors
    /// when the plan does not exist (use the plan_id returned by
    /// `plan_spaced_txs` / `list_spaced_plans`).
    #[frb(sync)]
    pub fn get_spaced_plan(&self, plan_id: i64) -> Result<APISpacedPlanDetail> {
        let plan = {
            let core = self.lock_wallet()?;
            get_tx_plan(&core.conn, plan_id)?.ok_or_else(|| anyhow!("Plan {plan_id} not found"))?
        };
        self.assemble_plan_detail(plan)
    }

    /// Cancel an active plan: discard every child PSBT (auto_broadcast
    /// vanishes with the row) and move the plan to `CANCELLED` for
    /// history. Errors when the plan is already terminal.
    #[frb(sync)]
    pub fn cancel_spaced_plan(&self, plan_id: i64) -> Result<()> {
        let core = self.lock_wallet()?;
        let plan =
            get_tx_plan(&core.conn, plan_id)?.ok_or_else(|| anyhow!("Plan {plan_id} not found"))?;
        if !plan.status.is_active() {
            return Err(anyhow!(
                "Plan {plan_id} is already in terminal state {:?}",
                plan.status
            ));
        }
        for id in list_unsigned_tx_ids_for_plan(&core.conn, plan_id)? {
            delete_psbt_row(&core.conn, id)?;
        }
        // Discard every auto-label this plan propagated to destination
        // addresses (and any future propagation it might have driven).
        // Explicit user labels stay because `set_entity_label` preserves
        // them when `is_auto = true`.
        clear_plan_auto_labels(&core.conn, plan_id)?;
        set_tx_plan_status(&core.conn, plan_id, TxPlanStatus::Cancelled)?;
        Ok(())
    }

    /// Seed this wallet's `address_labels` with the auto-labels of a
    /// spaced plan executed by *another* wallet. The cubit calls this
    /// on the destination wallet handle right after a `Migrate` plan
    /// is created — the source wallet can't reach the destination DB,
    /// so labels would otherwise be lost on receive.
    ///
    /// Each entry is tagged with the canonical
    /// `spaced_plan:{plan_id}:coin:{src_txid}:{src_vout}` source so the
    /// matching call to [`Self::clear_spaced_plan_labels`] can wipe
    /// them on cancel. Entries whose address already carries an
    /// explicit user label are skipped (the planner must never
    /// overwrite user input).
    ///
    /// Stored with `is_auto = false`: the user expects migrated coins
    /// on the destination wallet to look like *their own* labelled
    /// addresses, not as auto-inherited ones. The `source_entity` tag
    /// is still set so cancel cleanup can find and wipe them.
    #[frb(sync)]
    pub fn set_spaced_plan_address_labels(
        &self,
        entries: Vec<APISpacedPlanAddressLabel>,
    ) -> Result<()> {
        if entries.is_empty() {
            return Ok(());
        }
        let core = self.lock_wallet()?;
        for entry in &entries {
            if entry.label.is_empty() {
                continue;
            }
            if address_has_explicit_label(&core.conn, &entry.address)? {
                continue;
            }
            let source = plan_label_source(entry.plan_id, &entry.src_txid, entry.src_vout);
            set_address_label(
                &core.conn,
                &entry.address,
                &entry.label,
                false,
                Some(&source),
            )?;
        }
        Ok(())
    }

    /// Wipe every spaced-plan auto-label tagged with this `plan_id` on
    /// this wallet's DB. The cubit calls this on the destination
    /// wallet handle on cancel, mirroring the source-side cleanup in
    /// [`Self::cancel_spaced_plan`]. Explicit user labels are not
    /// affected (the sweep keys on `source_entity`, which is NULL for
    /// user labels).
    #[frb(sync)]
    pub fn clear_spaced_plan_labels(&self, plan_id: i64) -> Result<()> {
        let core = self.lock_wallet()?;
        clear_plan_auto_labels(&core.conn, plan_id)
    }
}

impl APIWallet {
    /// Shared precondition for batch-sign / merge / prepare paths: the
    /// plan must exist, be in DRAFT or SIGNED, and have at least one
    /// pending child PSBT. Returns the ordered child id list under one
    /// lock so callers don't race the plan status.
    fn assert_plan_signable(&self, plan_id: i64) -> Result<Vec<i64>> {
        let core = self.lock_wallet()?;
        let plan =
            get_tx_plan(&core.conn, plan_id)?.ok_or_else(|| anyhow!("Plan {plan_id} not found"))?;
        match plan.status {
            TxPlanStatus::Draft | TxPlanStatus::Signed => {}
            other => {
                return Err(anyhow!(
                    "Plan {plan_id} is in state {:?}; requires DRAFT or SIGNED",
                    other
                ));
            }
        }
        let ids = list_unsigned_tx_ids_for_plan(&core.conn, plan_id)?;
        if ids.is_empty() {
            return Err(anyhow!("Plan {plan_id} has no pending child PSBTs"));
        }
        Ok(ids)
    }

    fn assemble_plan_detail(&self, plan: TxPlanRow) -> Result<APISpacedPlanDetail> {
        let core = self.lock_wallet()?;
        let child_ids = list_unsigned_tx_ids_for_plan(&core.conn, plan.id)?;
        let mut rows = Vec::with_capacity(child_ids.len());
        for id in child_ids {
            let row = get_psbt_row(&core.conn, id)?;
            let info = super::row_to_api_psbt_loaded(row, &core.conn, &core.wallet);
            let (utxo_txid, utxo_vout) = first_input_outpoint(&info.psbt_base64)?;
            rows.push(APISpacedPlanDetailRow {
                psbt_id: info.id,
                utxo_txid,
                utxo_vout,
                amount_sat: info.amount_sat,
                fee_sat: info.fee_sat,
                abs_nlocktime: info.lock_time,
                auto_broadcast: info.auto_broadcast,
                has_spent_inputs: info.has_spent_inputs,
                recipients: info.recipients,
            });
        }
        Ok(APISpacedPlanDetail {
            plan_id: plan.id,
            kind: plan.kind.as_str().to_string(),
            dst_wallet_path: plan.dst_wallet_path,
            status: plan.status.as_str().to_string(),
            created_at: plan.created_at,
            updated_at: plan.updated_at,
            feerate_min_msatvb: plan.feerate_min_msatvb,
            feerate_max_msatvb: plan.feerate_max_msatvb,
            delay_blocks_min: plan.delay_blocks_min,
            delay_blocks_max: plan.delay_blocks_max,
            split_probability: plan.split_probability,
            min_split_output: plan.min_split_output,
            spend_path_id: plan.spend_path_id,
            rows,
        })
    }
}

/// Build the `source_entity` string used by spaced-plan auto-labels.
/// Format: `spaced_plan:{plan_id}:coin:{src_txid}:{src_vout}`. The
/// `LIKE` clause in [`clear_plan_auto_labels`] uses the
/// `spaced_plan:{plan_id}:%` prefix, so cancelling a plan wipes every
/// label propagated by any of its child PSBTs in one pass.
fn plan_label_source(plan_id: i64, src_txid: &str, src_vout: u32) -> String {
    format!("spaced_plan:{plan_id}:coin:{src_txid}:{src_vout}")
}

/// Resolve the label that this child PSBT will carry, copy it to the
/// PSBT row, and — for `Refresh` plans — to every destination address
/// in the source wallet's `address_labels`.
///
/// - PSBT label: directly mirrors the source coin label (or the
///   generated fallback) so the existing `try_auto_broadcast_one`
///   writes it onto `tx_labels` after broadcast.
/// - Destination address labels: only written for `Refresh` plans,
///   where the destination addresses live in the same wallet DB.
///   For `Migrate`, the destination addresses belong to a different
///   wallet — the caller (cubit) is responsible for opening that
///   wallet's handle and writing the labels there via
///   [`APIWallet::set_spaced_plan_address_labels`]. Writing them on
///   the source DB would only produce orphan rows.
///
/// When the source UTXO has no explicit label, falls back to a
/// generated descriptor — see [`default_plan_label`] — so the
/// resulting PSBT/tx and destination addresses still carry something
/// the user can recognise instead of staying blank.
///
/// Returns the resolved label so the caller can surface it in
/// `APISpacedPlanRow.label` (the cubit uses that value to write the
/// matching `address_labels` row in the destination wallet for
/// `Migrate` plans).
#[allow(clippy::too_many_arguments)]
fn propagate_source_label(
    conn: &rusqlite::Connection,
    plan_id: i64,
    psbt_id: i64,
    kind: TxPlanKind,
    src_txid: &str,
    src_vout: u32,
    dst_addresses: &[String],
    dst_wallet_name: Option<&str>,
) -> Result<String> {
    let outpoint_key = format!("{src_txid}:{src_vout}");
    let explicit = get_coin_label_with_flag(conn, &outpoint_key)?
        .map(|(l, _)| l)
        .filter(|l| !l.is_empty());
    // The "inheritable" label is the source UTXO's effective coin label
    // (or a generated fallback). It flows to the destination addresses
    // in both modes — directly here for `Refresh`, and via the cubit
    // (`set_spaced_plan_address_labels`) for `Migrate`. This is also
    // the value returned to the FFI summary so the Flutter side can
    // seed the destination wallet without re-reading the source DB.
    let inheritable = explicit.unwrap_or_else(|| default_plan_label(kind, src_txid, src_vout));

    // PSBT label: in `Refresh` it's the inheritable label, so the
    // tx-after-broadcast carries the user's own coin name forward. In
    // `Migrate` every child PSBT/tx gets the same `"Migration → <name>"`
    // string instead — the source wallet's history records the
    // migration intent as a whole, while the per-coin labels live on
    // the destination wallet's address rows.
    let psbt_label = match kind {
        TxPlanKind::Refresh => inheritable.clone(),
        TxPlanKind::Migrate => match dst_wallet_name {
            Some(name) if !name.is_empty() => format!("Migration → {name}"),
            _ => "Migration".to_string(),
        },
    };
    update_psbt_label(conn, psbt_id, Some(&psbt_label))?;

    if matches!(kind, TxPlanKind::Refresh) {
        let source = plan_label_source(plan_id, src_txid, src_vout);
        for addr in dst_addresses {
            set_address_if_none(conn, addr, &inheritable, &source)?;
        }
    }
    Ok(inheritable)
}

/// Friendly fallback label for a child PSBT whose source UTXO has no
/// explicit user label.
///
/// Format: `"<Kind> <YYYY-MM-DD> (<short_txid>:<vout>)"`, e.g.
/// `"Refresh 2026-05-19 (a3f2…b8c1:0)"`. The date is today UTC; the
/// short txid keeps the label unique per source UTXO without dragging
/// 64 hex chars into the UI.
fn default_plan_label(kind: TxPlanKind, src_txid: &str, src_vout: u32) -> String {
    let prefix = match kind {
        TxPlanKind::Migrate => "Migration",
        TxPlanKind::Refresh => "Refresh",
    };
    format!(
        "{prefix} {} ({})",
        today_utc_yyyy_mm_dd(),
        short_outpoint(src_txid, src_vout)
    )
}

fn short_outpoint(txid: &str, vout: u32) -> String {
    if txid.len() > 8 {
        let head = &txid[..4];
        let tail = &txid[txid.len() - 4..];
        format!("{head}…{tail}:{vout}")
    } else {
        format!("{txid}:{vout}")
    }
}

fn today_utc_yyyy_mm_dd() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let days = secs.div_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}-{m:02}-{d:02}")
}

/// Howard Hinnant's `civil_from_days`: convert days since 1970-01-01
/// (UTC, proleptic Gregorian) to (year, month, day). Pure integer math,
/// no external dependency.
fn civil_from_days(z: i64) -> (i32, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = (z - era * 146_097) as u64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    let y = if m <= 2 { y + 1 } else { y };
    (y as i32, m, d)
}

/// Wipe every spaced-plan auto-label whose `source_entity` carries this
/// plan's prefix. Used by `cancel_spaced_plan` so a cancelled plan
/// leaves no trail on destination address rows.
fn clear_plan_auto_labels(conn: &rusqlite::Connection, plan_id: i64) -> Result<()> {
    let pattern = format!("spaced_plan:{plan_id}:%");
    // Limited to the three tables the propagation pipeline writes to —
    // none of the spaced-plan code paths touch `tx_labels` directly, but
    // we sweep it too for safety against future propagation extensions.
    for table in ["address_labels", "coin_labels", "tx_labels"] {
        conn.execute(
            &format!("DELETE FROM {table} WHERE source_entity LIKE ?1"),
            rusqlite::params![pattern],
        )?;
    }
    Ok(())
}

fn first_input_outpoint(psbt_base64: &str) -> Result<(String, u32)> {
    let psbt = super::psbt_from_base64(psbt_base64)?;
    let outpoint = psbt
        .unsigned_tx
        .input
        .first()
        .ok_or_else(|| anyhow!("PSBT has no inputs"))?
        .previous_output;
    Ok((outpoint.txid.to_string(), outpoint.vout))
}

// ---------------------------------------------------------------------------
// Helpers — kept private to keep the FFI surface tidy.
// ---------------------------------------------------------------------------

impl APIWallet {
    fn collect_planner_inputs(
        &self,
        params: &APISpacedPlanParams,
    ) -> Result<(Vec<PlannerUtxo>, u32, u32)> {
        use std::collections::HashSet;

        let core = self.lock_wallet()?;
        let tip_height = core.wallet.latest_checkpoint().block_id().height;
        let rel_timelock = core
            .cached_spend_paths()
            .ok()
            .and_then(|paths| {
                paths
                    .iter()
                    .find(|p| p.id == params.spend_path_id)
                    .map(|p| p.rel_timelock)
            })
            .unwrap_or(0);

        let allow: Option<HashSet<(String, u32)>> = if params.selected_utxos.is_empty() {
            None
        } else {
            Some(
                params
                    .selected_utxos
                    .iter()
                    .map(|c| (c.txid.clone(), c.vout))
                    .collect(),
            )
        };

        let mut utxos = Vec::new();
        for local in core.wallet.list_unspent() {
            let conf_height = match &local.chain_position {
                bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } => {
                    Some(anchor.block_id.height)
                }
                _ => continue, // §3: confirmed only
            };

            let txid_s = local.outpoint.txid.to_string();
            let vout = local.outpoint.vout;
            if let Some(allow) = &allow {
                if !allow.contains(&(txid_s.clone(), vout)) {
                    continue;
                }
            }

            utxos.push(PlannerUtxo {
                outpoint_key: format!("{txid_s}:{vout}"),
                amount_sat: local.txout.value.to_sat(),
                conf_height,
            });
        }
        Ok((utxos, tip_height, rel_timelock))
    }

    fn build_intent_psbts(
        &self,
        plan_id: i64,
        kind: TxPlanKind,
        tip_height: u32,
        params: &APISpacedPlanParams,
        intents: Vec<crate::api::wallet::spaced_planner::PlanIntent>,
    ) -> Result<APISpacedPlanSummary> {
        let mut rows = Vec::with_capacity(intents.len());
        let mut total_amount: u64 = 0;
        let mut total_fee: u64 = 0;
        let mut dropped: u32 = 0;
        let mut addr_cursor: usize = 0;

        for intent in intents.into_iter() {
            let (utxo_txid, utxo_vout) = parse_outpoint_key(&intent.utxo.outpoint_key)?;
            let primary_addr = params.dst_addresses[addr_cursor].clone();
            let feerate_sat_per_vb = intent.feerate_msatvb as f64 / 1000.0;

            // 6a. Single-output preview — drives dust check, fee discovery, and
            //     the input to the split gate.
            let single = self.preview_single_output(
                params,
                &utxo_txid,
                utxo_vout,
                &primary_addr,
                feerate_sat_per_vb,
            )?;
            if single.insufficient_funds || single.send_sats < PLAN_DUST_THRESHOLD_SAT {
                dropped += 1;
                addr_cursor += 1;
                continue;
            }

            // 6b. Decide split vs single, materialise the chosen variant.
            let built = match intent.split {
                SplitIntent::Try { ratio }
                    if split_passes_gate(single.send_sats, ratio, params.min_split_output)
                        && addr_cursor + 1 < params.dst_addresses.len() =>
                {
                    let secondary_addr = params.dst_addresses[addr_cursor + 1].clone();
                    match self.try_build_split(
                        params,
                        &utxo_txid,
                        utxo_vout,
                        &primary_addr,
                        &secondary_addr,
                        feerate_sat_per_vb,
                        ratio,
                        single.send_sats,
                        intent.nlocktime_delta_blocks,
                    )? {
                        Some(built) => {
                            addr_cursor += 2;
                            built
                        }
                        None => {
                            // 2-output build would have produced a dust output
                            // or insufficient funds — fall back to 1-output.
                            let built = self.build_single_output(
                                params,
                                &utxo_txid,
                                utxo_vout,
                                &primary_addr,
                                &single,
                                intent.nlocktime_delta_blocks,
                            )?;
                            addr_cursor += 1;
                            built
                        }
                    }
                }
                _ => {
                    let built = self.build_single_output(
                        params,
                        &utxo_txid,
                        utxo_vout,
                        &primary_addr,
                        &single,
                        intent.nlocktime_delta_blocks,
                    )?;
                    addr_cursor += 1;
                    built
                }
            };

            // 6c. Link the new PSBT row to this plan + propagate the source
            //     UTXO's coin label so traceability survives the
            //     refresh/migration. Label flow:
            //       source coin → PSBT.label   (always — auto-stamped onto
            //                                   tx_label on broadcast)
            //       → destination addresses    (only in `Refresh`; for
            //                                   `Migrate` the cubit writes
            //                                   them on the destination
            //                                   wallet's DB via the
            //                                   `set_spaced_plan_address_labels`
            //                                   FFI, since the destination
            //                                   address rows live there).
            let label = {
                let core = self.lock_wallet()?;
                set_unsigned_tx_plan_id(&core.conn, built.psbt_id, Some(plan_id))?;
                propagate_source_label(
                    &core.conn,
                    plan_id,
                    built.psbt_id,
                    kind,
                    &utxo_txid,
                    utxo_vout,
                    &built.recipient_addresses,
                    params.dst_wallet_name.as_deref(),
                )?
            };

            total_amount = total_amount.saturating_add(built.net_out_sat);
            total_fee = total_fee.saturating_add(built.fee_sat);
            rows.push(APISpacedPlanRow {
                psbt_id: built.psbt_id,
                utxo_txid,
                utxo_vout,
                amount_sat: intent.utxo.amount_sat,
                conf_height: intent.utxo.conf_height,
                nlocktime_delta_blocks: intent.nlocktime_delta_blocks,
                abs_nlocktime: built.abs_nlocktime,
                feerate_sat_per_vb,
                fee_sat: built.fee_sat,
                net_out_sat: built.net_out_sat,
                recipient_addresses: built.recipient_addresses,
                recipient_amounts_sat: built.recipient_amounts_sat,
                split: built.split_ratio.is_some(),
                split_ratio: built.split_ratio,
                label,
            });
        }

        Ok(APISpacedPlanSummary {
            plan_id,
            tip_height,
            rows,
            total_amount_sat: total_amount,
            total_fee_sat: total_fee,
            dropped_utxo_count: dropped,
        })
    }

    fn preview_single_output(
        &self,
        params: &APISpacedPlanParams,
        utxo_txid: &str,
        utxo_vout: u32,
        addr: &str,
        feerate_sat_per_vb: f64,
    ) -> Result<crate::api::model::APITxPreview> {
        self.preview_psbt(
            vec![APIRecipient {
                address: addr.to_string(),
                amount_sat: 0,
                op_return_data: None,
            }],
            Some(0),
            Some(feerate_sat_per_vb),
            None,
            vec![APICoinControl {
                txid: utxo_txid.to_string(),
                vout: utxo_vout,
            }],
            params.policy_path.clone(),
            params.spend_path_id,
            vec![],
        )
    }

    fn build_single_output(
        &self,
        params: &APISpacedPlanParams,
        utxo_txid: &str,
        utxo_vout: u32,
        addr: &str,
        preview: &crate::api::model::APITxPreview,
        nlocktime_delta_blocks: u32,
    ) -> Result<BuiltIntent> {
        let psbt_info = self.create_psbt(
            vec![APIRecipient {
                address: addr.to_string(),
                amount_sat: 0,
                op_return_data: None,
            }],
            Some(0),
            preview.fee_sats,
            vec![APICoinControl {
                txid: utxo_txid.to_string(),
                vout: utxo_vout,
            }],
            params.policy_path.clone(),
            params.spend_path_id,
            params.threshold,
            params.mfps.clone(),
            Some(nlocktime_delta_blocks),
        )?;
        Ok(BuiltIntent {
            psbt_id: psbt_info.id,
            abs_nlocktime: psbt_info.lock_time,
            fee_sat: preview.fee_sats,
            net_out_sat: preview.send_sats,
            recipient_addresses: vec![addr.to_string()],
            recipient_amounts_sat: vec![preview.send_sats],
            split_ratio: None,
        })
    }

    /// Try to build a 2-output split tx. Returns `Ok(None)` when the
    /// resulting tx would have any output below dust or BDK reports
    /// insufficient funds — the caller falls back to 1-output.
    #[allow(clippy::too_many_arguments)]
    fn try_build_split(
        &self,
        params: &APISpacedPlanParams,
        utxo_txid: &str,
        utxo_vout: u32,
        primary_addr: &str,
        secondary_addr: &str,
        feerate_sat_per_vb: f64,
        ratio: f64,
        single_net_out_sat: u64,
        nlocktime_delta_blocks: u32,
    ) -> Result<Option<BuiltIntent>> {
        // Pick the explicit amount from the single-output net_out so the
        // realised ratio stays close to target without iterating. BDK assigns
        // the remainder to the drain output (`max_recipient_index = 1`).
        let amount_a = ((single_net_out_sat as f64) * ratio).floor() as u64;
        if amount_a < PLAN_DUST_THRESHOLD_SAT {
            return Ok(None);
        }

        let recipients = vec![
            APIRecipient {
                address: primary_addr.to_string(),
                amount_sat: amount_a,
                op_return_data: None,
            },
            APIRecipient {
                address: secondary_addr.to_string(),
                amount_sat: 0,
                op_return_data: None,
            },
        ];
        let coin = vec![APICoinControl {
            txid: utxo_txid.to_string(),
            vout: utxo_vout,
        }];

        let preview = self.preview_psbt(
            recipients.clone(),
            Some(1),
            Some(feerate_sat_per_vb),
            None,
            coin.clone(),
            params.policy_path.clone(),
            params.spend_path_id,
            vec![],
        )?;
        if preview.insufficient_funds {
            return Ok(None);
        }
        // Resolve per-output amounts from the preview (BDK assigns the drain
        // output's value). The order matches the order we passed in.
        let amounts: Vec<u64> = preview.recipients.iter().map(|r| r.amount_sat).collect();
        if amounts.len() != 2 {
            return Ok(None);
        }
        if amounts[0] < PLAN_DUST_THRESHOLD_SAT || amounts[1] < PLAN_DUST_THRESHOLD_SAT {
            return Ok(None);
        }

        let psbt_info = self.create_psbt(
            recipients,
            Some(1),
            preview.fee_sats,
            coin,
            params.policy_path.clone(),
            params.spend_path_id,
            params.threshold,
            params.mfps.clone(),
            Some(nlocktime_delta_blocks),
        )?;
        Ok(Some(BuiltIntent {
            psbt_id: psbt_info.id,
            abs_nlocktime: psbt_info.lock_time,
            fee_sat: preview.fee_sats,
            net_out_sat: preview.send_sats,
            recipient_addresses: vec![primary_addr.to_string(), secondary_addr.to_string()],
            recipient_amounts_sat: amounts,
            split_ratio: Some(ratio),
        }))
    }
}

struct BuiltIntent {
    psbt_id: i64,
    abs_nlocktime: u32,
    fee_sat: u64,
    net_out_sat: u64,
    recipient_addresses: Vec<String>,
    recipient_amounts_sat: Vec<u64>,
    split_ratio: Option<f64>,
}

fn run_planner(
    utxos: Vec<PlannerUtxo>,
    params: &PlannerParams,
    tip_height: u32,
    rel_timelock_blocks: u32,
    seed: Option<u64>,
) -> Result<Vec<crate::api::wallet::spaced_planner::PlanIntent>> {
    use rand::rngs::StdRng;
    use rand::SeedableRng;

    match seed {
        // Thread RNG is automatically reseeded from the OS — same security
        // properties as OsRng but implements `Rng` directly.
        None => {
            let mut rng = rand::rng();
            plan_intents(utxos, params, tip_height, rel_timelock_blocks, &mut rng)
        }
        Some(s) => {
            let mut rng = StdRng::seed_from_u64(s);
            plan_intents(utxos, params, tip_height, rel_timelock_blocks, &mut rng)
        }
    }
}

fn parse_outpoint_key(key: &str) -> Result<(String, u32)> {
    let mut parts = key.split(':');
    let txid = parts
        .next()
        .ok_or_else(|| anyhow!("malformed outpoint key {key}"))?
        .to_string();
    let vout: u32 = parts
        .next()
        .ok_or_else(|| anyhow!("malformed outpoint key {key}"))?
        .parse()
        .map_err(|_| anyhow!("non-numeric vout in {key}"))?;
    if parts.next().is_some() {
        return Err(anyhow!("malformed outpoint key {key}"));
    }
    Ok((txid, vout))
}

#[cfg(test)]
#[path = "spaced_plan_tests.rs"]
mod tests;
