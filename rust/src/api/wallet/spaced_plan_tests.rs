use crate::api::model::{
    APICoinControl, APINetwork, APIPolicyPath, APIProtectionType, APISecurityLevel,
    APISpacedPlanParams,
};
use crate::api::wallet::{create_wallet, open_wallet, APIWallet};
use crate::test_support::{inject_confirmed_utxo, KEY_HEX, MAINNET_DESC};
use bdk_wallet::KeychainKind;
use tempfile::tempdir;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn make_wallet_for(
    dir: &tempfile::TempDir,
    descriptor: &str,
    network: APINetwork,
    name: &str,
) -> APIWallet {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = create_wallet(
        wallets_dir,
        name.to_string(),
        descriptor.to_string(),
        network,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )
    .expect("create_wallet failed");
    open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None).expect("open_wallet failed")
}

fn peek_addresses(wallet: &APIWallet, count: u32) -> Vec<String> {
    // Offset by 10 so the test addresses never collide with the funded
    // address index 0 used by `inject_confirmed_utxo`.
    let core = wallet.lock_wallet().unwrap();
    (10..(10 + count))
        .map(|i| {
            core.wallet
                .peek_address(KeychainKind::External, i)
                .address
                .to_string()
        })
        .collect()
}

fn default_params(dst_addresses: Vec<String>) -> APISpacedPlanParams {
    APISpacedPlanParams {
        dst_wallet_path: "/tmp/dst.db".into(),
        dst_wallet_name: None,
        feerate_min_msatvb: 2_000,
        feerate_max_msatvb: 8_000,
        delay_blocks_min: 1,
        delay_blocks_max: 100,
        split_probability: 0.0, // step 4 is 1-output only
        min_split_output: 100_000,
        spend_path_id: 0,
        threshold: 2,
        mfps: vec!["c449c5c5".into(), "c61af686".into()],
        policy_path: Vec::<APIPolicyPath>::new(),
        dst_addresses,
        selected_utxos: vec![],
        rng_seed: Some(42),
    }
}

/// Variant of [`default_params`] for `Refresh` plans (destination ==
/// source). Used by the label-propagation tests, since for `Migrate`
/// plans the source DB no longer writes destination address labels.
fn refresh_params(src: &APIWallet, dst_addresses: Vec<String>) -> APISpacedPlanParams {
    let mut params = default_params(dst_addresses);
    params.dst_wallet_path = src.path.clone();
    params
}

/// Resolve the real `spend_path_id` for the wallet's first spend path.
/// `default_params` ships with `0` (a placeholder accepted by
/// `plan_spaced_txs` thanks to the `find().unwrap_or(0)` fallback), but
/// any code path that needs the persisted id to round-trip through
/// `cached_spend_paths` — `prepare_spaced_plan_psbts` is the first one —
/// must use this helper.
fn first_spend_path_id(wallet: &APIWallet) -> u32 {
    let core = wallet.lock_wallet().unwrap();
    core.cached_spend_paths().unwrap().first().unwrap().id
}

// ---------------------------------------------------------------------------
// Validation guards (no BDK state needed)
// ---------------------------------------------------------------------------

#[test]
fn kind_derives_migrate_when_dst_differs_from_source() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let params = default_params(peek_addresses(&dst, 2));
    let summary = src.plan_spaced_txs(params).unwrap();
    let detail = src.get_spaced_plan(summary.plan_id).unwrap();
    assert_eq!(detail.kind, "MIGRATE");
}

#[test]
fn kind_derives_refresh_when_dst_matches_source() {
    let src_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();

    let mut params = default_params(peek_addresses(&src, 2));
    params.dst_wallet_path = src.path.clone();
    let summary = src.plan_spaced_txs(params).unwrap();
    let detail = src.get_spaced_plan(summary.plan_id).unwrap();
    assert_eq!(detail.kind, "REFRESH");
}

#[test]
fn kind_derives_refresh_when_dst_path_is_empty() {
    let src_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();

    let mut params = default_params(peek_addresses(&src, 2));
    params.dst_wallet_path = String::new();
    let summary = src.plan_spaced_txs(params).unwrap();
    let detail = src.get_spaced_plan(summary.plan_id).unwrap();
    assert_eq!(detail.kind, "REFRESH");
}

#[test]
fn rejects_invalid_planner_params() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let mut params = default_params(vec!["dummy".into()]);
    params.feerate_min_msatvb = 9_000;
    params.feerate_max_msatvb = 8_000;
    assert!(wallet.plan_spaced_txs(params).is_err());
}

#[test]
fn rejects_when_no_confirmed_utxos() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let params = default_params(vec!["dummy".into()]);
    let err = wallet.plan_spaced_txs(params).unwrap_err().to_string();
    assert!(err.contains("No confirmed UTXOs"), "got: {err}");
}

#[test]
fn rejects_when_not_enough_destination_addresses() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();

    // Only 1 address supplied for 2 UTXOs.
    let params = default_params(peek_addresses(&dst, 1));
    let err = src.plan_spaced_txs(params).unwrap_err().to_string();
    assert!(err.contains("destination addresses"), "got: {err}");
}

// ---------------------------------------------------------------------------
// Happy path (with confirmed UTXOs)
// ---------------------------------------------------------------------------

#[test]
fn happy_path_creates_one_psbt_per_confirmed_utxo() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xcc, 102, 500_000).unwrap();

    let dst_addrs = peek_addresses(&dst, 8);
    let params = default_params(dst_addrs.clone());
    let summary = src.plan_spaced_txs(params).expect("plan must succeed");

    assert_eq!(summary.rows.len(), 3);
    assert!(summary.plan_id > 0);
    assert!(summary.total_fee_sat > 0);
    assert!(summary.total_amount_sat > 0);
    assert_eq!(summary.dropped_utxo_count, 0);

    // Every row references one of the supplied dst addresses, no duplicates.
    let mut seen = std::collections::HashSet::new();
    for row in &summary.rows {
        assert_eq!(row.recipient_addresses.len(), 1);
        assert_eq!(row.recipient_amounts_sat.len(), 1);
        let addr = &row.recipient_addresses[0];
        assert!(dst_addrs.contains(addr));
        assert!(seen.insert(addr.clone()));
        assert!(row.fee_sat > 0);
        assert!(row.net_out_sat > 0);
        assert!(row.amount_sat == 500_000);
        assert!(row.nlocktime_delta_blocks >= 1);
        assert!(row.abs_nlocktime > 0);
        assert!(!row.split);
        assert!(row.split_ratio.is_none());
    }
}

#[test]
fn split_probability_one_emits_two_output_rows() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 5_000_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 5_000_000).unwrap();

    let mut params = default_params(peek_addresses(&dst, 8));
    params.split_probability = 1.0;
    params.min_split_output = 100_000;

    let summary = src.plan_spaced_txs(params).expect("plan");
    assert_eq!(summary.rows.len(), 2);
    for row in &summary.rows {
        assert!(row.split, "row not split: {row:?}");
        assert_eq!(row.recipient_addresses.len(), 2);
        assert_eq!(row.recipient_amounts_sat.len(), 2);
        assert_ne!(row.recipient_addresses[0], row.recipient_addresses[1]);
        assert!(row.recipient_amounts_sat[0] >= 546);
        assert!(row.recipient_amounts_sat[1] >= 546);
        assert_eq!(
            row.recipient_amounts_sat.iter().sum::<u64>(),
            row.net_out_sat
        );
        let ratio = row.split_ratio.unwrap();
        assert!((0.2..=0.8).contains(&ratio));
    }
    // 2 split rows × 2 addresses = 4 unique destination addresses.
    let mut all = std::collections::HashSet::new();
    for row in &summary.rows {
        for a in &row.recipient_addresses {
            assert!(all.insert(a.clone()), "duplicate dst address {a}");
        }
    }
    assert_eq!(all.len(), 4);
}

#[test]
fn split_falls_back_to_single_when_gate_fails() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();

    let mut params = default_params(peek_addresses(&dst, 4));
    params.split_probability = 1.0;
    params.min_split_output = 10_000_000; // unreachable

    let summary = src.plan_spaced_txs(params).expect("plan");
    assert_eq!(summary.rows.len(), 1);
    assert!(!summary.rows[0].split);
    assert_eq!(summary.rows[0].recipient_addresses.len(), 1);
}

// ---------------------------------------------------------------------------
// commit_spaced_plan
// ---------------------------------------------------------------------------

/// Mark every input of a stored PSBT as "finalised" by injecting a placeholder
/// `final_script_witness`. `is_psbt_finalized` (used by `analyze_psbt`) only
/// checks for the *presence* of finalised witness/script data, not its
/// validity, so this short-circuits the sign-count audit in
/// `commit_spaced_plan` without requiring real keys.
fn force_finalise_stored_psbt(wallet: &APIWallet, psbt_id: i64) {
    use crate::core::wallet_persistence::psbt_storage::{get_psbt_row, update_psbt_data};
    use base64::{engine::general_purpose, Engine as _};
    use bdk_wallet::bitcoin::psbt::Psbt;
    use bdk_wallet::bitcoin::Witness;

    let core = wallet.lock_wallet().unwrap();
    let row = get_psbt_row(&core.conn, psbt_id).unwrap();
    let psbt_bytes = general_purpose::STANDARD.decode(&row.psbt).unwrap();
    let mut psbt = Psbt::deserialize(&psbt_bytes).unwrap();
    for input in &mut psbt.inputs {
        input.final_script_witness = Some(Witness::default());
    }
    let new_b64 = general_purpose::STANDARD.encode(psbt.serialize());
    update_psbt_data(&core.conn, psbt_id, &new_b64).unwrap();
}

#[test]
fn commit_rejects_unknown_plan() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let err = wallet.commit_spaced_plan(9_999).unwrap_err().to_string();
    assert!(err.contains("not found"), "got: {err}");
}

#[test]
fn commit_returns_uncommitted_when_children_unsigned() {
    use crate::core::wallet_persistence::tx_plan_storage::{get_tx_plan, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();

    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 4)))
        .unwrap();

    let report = src.commit_spaced_plan(summary.plan_id).unwrap();
    assert!(!report.committed);
    assert_eq!(report.total_count, 2);
    assert_eq!(report.signed_count, 0);
    assert_eq!(report.unsigned_psbt_ids.len(), 2);
    let summary_ids: std::collections::HashSet<i64> =
        summary.rows.iter().map(|r| r.psbt_id).collect();
    for id in &report.unsigned_psbt_ids {
        assert!(summary_ids.contains(id));
    }

    // Plan stays in DRAFT and child auto_broadcast flags stay off.
    let core = src.lock_wallet().unwrap();
    let plan = get_tx_plan(&core.conn, summary.plan_id).unwrap().unwrap();
    assert_eq!(plan.status, TxPlanStatus::Draft);
    for id in summary_ids {
        let row =
            crate::core::wallet_persistence::psbt_storage::get_psbt_row(&core.conn, id).unwrap();
        assert!(!row.auto_broadcast);
    }
}

#[test]
fn commit_transitions_to_signed_and_flips_auto_broadcast_when_finalised() {
    use crate::core::wallet_persistence::psbt_storage::get_psbt_row;
    use crate::core::wallet_persistence::tx_plan_storage::{get_tx_plan, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();

    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 4)))
        .unwrap();
    for row in &summary.rows {
        force_finalise_stored_psbt(&src, row.psbt_id);
    }

    let report = src.commit_spaced_plan(summary.plan_id).unwrap();
    assert!(report.committed);
    assert_eq!(report.total_count, 2);
    assert_eq!(report.signed_count, 2);
    assert!(report.unsigned_psbt_ids.is_empty());

    let core = src.lock_wallet().unwrap();
    let plan = get_tx_plan(&core.conn, summary.plan_id).unwrap().unwrap();
    assert_eq!(plan.status, TxPlanStatus::Signed);
    for row in &summary.rows {
        let psbt = get_psbt_row(&core.conn, row.psbt_id).unwrap();
        assert!(psbt.auto_broadcast, "child {} not armed", row.psbt_id);
    }
}

#[test]
fn commit_is_idempotent_on_already_signed_plan() {
    use crate::core::wallet_persistence::tx_plan_storage::{get_tx_plan, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .unwrap();
    for row in &summary.rows {
        force_finalise_stored_psbt(&src, row.psbt_id);
    }

    let first = src.commit_spaced_plan(summary.plan_id).unwrap();
    assert!(first.committed);
    let second = src.commit_spaced_plan(summary.plan_id).unwrap();
    assert!(second.committed);
    assert_eq!(second.signed_count, summary.rows.len() as u32);

    let core = src.lock_wallet().unwrap();
    let plan = get_tx_plan(&core.conn, summary.plan_id).unwrap().unwrap();
    assert_eq!(plan.status, TxPlanStatus::Signed);
}

#[test]
fn commit_rejects_terminal_plan_states() {
    use crate::core::wallet_persistence::tx_plan_storage::{set_tx_plan_status, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .unwrap();

    {
        let core = src.lock_wallet().unwrap();
        set_tx_plan_status(&core.conn, summary.plan_id, TxPlanStatus::Cancelled).unwrap();
    }
    let err = src
        .commit_spaced_plan(summary.plan_id)
        .unwrap_err()
        .to_string();
    assert!(err.contains("DRAFT"), "got: {err}");
}

// ---------------------------------------------------------------------------
// has_active / list / get / cancel
// ---------------------------------------------------------------------------

#[test]
fn has_active_tracks_plan_lifecycle() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    assert!(!src.has_active_spaced_plan().unwrap());
    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();

    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .unwrap();
    assert!(src.has_active_spaced_plan().unwrap());

    src.cancel_spaced_plan(summary.plan_id).unwrap();
    assert!(!src.has_active_spaced_plan().unwrap());
}

#[test]
fn list_returns_plans_newest_first_including_cancelled() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();

    let first = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .unwrap();
    src.cancel_spaced_plan(first.plan_id).unwrap();
    let second = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .unwrap();

    let listed = src.list_spaced_plans().unwrap();
    assert_eq!(listed.len(), 2);
    assert_eq!(listed[0].plan_id, second.plan_id, "newest first");
    assert_eq!(listed[0].status, "DRAFT");
    assert_eq!(listed[1].plan_id, first.plan_id);
    assert_eq!(listed[1].status, "CANCELLED");
    assert!(listed[1].rows.is_empty(), "cancelled plan has no children");
}

#[test]
fn get_returns_detail_with_child_rows() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();

    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 4)))
        .unwrap();
    let detail = src.get_spaced_plan(summary.plan_id).unwrap();

    assert_eq!(detail.plan_id, summary.plan_id);
    assert_eq!(detail.status, "DRAFT");
    assert_eq!(detail.kind, "MIGRATE");
    assert_eq!(detail.rows.len(), 2);
    for row in &detail.rows {
        assert!(row.fee_sat > 0);
        assert!(row.abs_nlocktime > 0);
        assert!(!row.auto_broadcast);
        assert!(!row.has_spent_inputs);
        assert!(!row.recipients.is_empty());
    }
    // The funded outpoint must appear in exactly one row's input.
    let outpoints: Vec<(String, u32)> = detail
        .rows
        .iter()
        .map(|r| (r.utxo_txid.clone(), r.utxo_vout))
        .collect();
    assert!(outpoints.contains(&(funded.txid.to_string(), funded.vout)));
}

#[test]
fn get_unknown_plan_errors() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let err = wallet.get_spaced_plan(9_999).unwrap_err().to_string();
    assert!(err.contains("not found"), "got: {err}");
}

#[test]
fn cancel_discards_children_and_marks_cancelled() {
    use crate::core::wallet_persistence::tx_plan_storage::{
        get_tx_plan, list_unsigned_tx_ids_for_plan, TxPlanStatus,
    };

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 4)))
        .unwrap();

    src.cancel_spaced_plan(summary.plan_id).unwrap();

    let core = src.lock_wallet().unwrap();
    let plan = get_tx_plan(&core.conn, summary.plan_id).unwrap().unwrap();
    assert_eq!(plan.status, TxPlanStatus::Cancelled);
    let remaining = list_unsigned_tx_ids_for_plan(&core.conn, summary.plan_id).unwrap();
    assert!(remaining.is_empty(), "child PSBTs not discarded");
}

#[test]
fn cancel_rejects_already_terminal_plan() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .unwrap();
    src.cancel_spaced_plan(summary.plan_id).unwrap();

    let err = src
        .cancel_spaced_plan(summary.plan_id)
        .unwrap_err()
        .to_string();
    assert!(err.contains("terminal"), "got: {err}");
}

#[test]
fn cancel_unknown_plan_errors() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let err = wallet.cancel_spaced_plan(9_999).unwrap_err().to_string();
    assert!(err.contains("not found"), "got: {err}");
}

// ---------------------------------------------------------------------------
// Label propagation
// ---------------------------------------------------------------------------

#[test]
fn refresh_plan_propagates_source_coin_label_to_psbt_and_dst_addresses() {
    use crate::core::wallet_persistence::labels::{
        get_address_label_with_flag, get_coin_label_with_flag, set_coin_label,
    };
    use crate::core::wallet_persistence::psbt_storage::get_psbt_row;

    let src_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let outpoint = format!("{}:{}", funded.txid, funded.vout);

    // Attach an explicit label to the source UTXO.
    {
        let core = src.lock_wallet().unwrap();
        set_coin_label(&core.conn, &outpoint, "Salary Jan 2024", false, None).unwrap();
    }

    let dst_addrs = peek_addresses(&src, 4);
    let summary = src
        .plan_spaced_txs(refresh_params(&src, dst_addrs.clone()))
        .unwrap();
    assert_eq!(summary.rows.len(), 1);
    let row = &summary.rows[0];

    let core = src.lock_wallet().unwrap();

    // PSBT carries the label so auto-broadcast can stamp it onto the
    // eventual tx_label.
    let psbt = get_psbt_row(&core.conn, row.psbt_id).unwrap();
    assert_eq!(psbt.label.as_deref(), Some("Salary Jan 2024"));

    // The summary surfaces the same label so the cubit can mirror it
    // onto the destination wallet's DB for `Migrate` plans (here a
    // no-op extra; the assertion proves the field is wired).
    assert_eq!(row.label, "Salary Jan 2024");

    // For `Refresh` plans every destination address gets the auto-label
    // on the source DB (destination == source).
    for addr in &row.recipient_addresses {
        let labelled = get_address_label_with_flag(&core.conn, addr).unwrap();
        assert_eq!(
            labelled,
            Some(("Salary Jan 2024".to_string(), true)),
            "address {addr} not auto-labelled",
        );
    }

    // Coin label survives (we never touch coin_labels in propagation).
    assert_eq!(
        get_coin_label_with_flag(&core.conn, &outpoint).unwrap(),
        Some(("Salary Jan 2024".to_string(), false)),
    );
}

#[test]
fn refresh_plan_without_source_label_generates_friendly_fallback() {
    use crate::core::wallet_persistence::labels::get_address_label_with_flag;
    use crate::core::wallet_persistence::psbt_storage::get_psbt_row;

    let src_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(refresh_params(&src, peek_addresses(&src, 2)))
        .unwrap();

    // Fallback label format: "Refresh <YYYY-MM-DD> (<head>…<tail>:<vout>)".
    let txid = funded.txid.to_string();
    let head = &txid[..4];
    let tail = &txid[txid.len() - 4..];
    let suffix = format!("({head}…{tail}:{vout})", vout = funded.vout);

    let core = src.lock_wallet().unwrap();
    let psbt = get_psbt_row(&core.conn, summary.rows[0].psbt_id).unwrap();
    let psbt_label = psbt.label.expect("PSBT should carry the fallback label");
    assert!(
        psbt_label.starts_with("Refresh ") && psbt_label.ends_with(&suffix),
        "unexpected PSBT label: {psbt_label}"
    );
    assert_eq!(summary.rows[0].label, psbt_label);

    for addr in &summary.rows[0].recipient_addresses {
        let labelled = get_address_label_with_flag(&core.conn, addr)
            .unwrap()
            .unwrap_or_else(|| panic!("address {addr} should be auto-labelled"));
        assert_eq!(
            labelled.0, psbt_label,
            "destination address label should match the PSBT fallback"
        );
        assert!(labelled.1, "destination label must be flagged as auto");
    }
}

#[test]
fn migrate_plan_writes_psbt_label_but_no_source_address_labels() {
    // For `Migrate` plans the destination addresses live in another
    // wallet's DB, so the planner must not seed the source DB's
    // `address_labels` table. The cubit is responsible for mirroring
    // the labels onto the destination via `set_spaced_plan_address_labels`.
    use crate::core::wallet_persistence::labels::{get_address_label_with_flag, set_coin_label};
    use crate::core::wallet_persistence::psbt_storage::get_psbt_row;

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let outpoint = format!("{}:{}", funded.txid, funded.vout);
    {
        let core = src.lock_wallet().unwrap();
        set_coin_label(&core.conn, &outpoint, "Salary", false, None).unwrap();
    }

    let dst_addrs = peek_addresses(&dst, 2);
    let summary = src
        .plan_spaced_txs(default_params(dst_addrs.clone()))
        .unwrap();
    assert_eq!(summary.rows.len(), 1);

    let core = src.lock_wallet().unwrap();
    let psbt = get_psbt_row(&core.conn, summary.rows[0].psbt_id).unwrap();
    // PSBT label is the fixed Migrate marker — `default_params` leaves
    // `dst_wallet_name = None`, so the suffix is omitted.
    assert_eq!(psbt.label.as_deref(), Some("Migration"));
    // The "inheritable" label returned in the summary still mirrors
    // the source coin label — it's what the cubit feeds to the dst
    // wallet's `address_labels`.
    assert_eq!(summary.rows[0].label, "Salary");

    // The source DB must NOT carry any auto-label for the dst addresses.
    for addr in &summary.rows[0].recipient_addresses {
        let labelled = get_address_label_with_flag(&core.conn, addr).unwrap();
        assert!(
            labelled.is_none(),
            "MIGRATE wrote {addr} = {labelled:?} into source DB — should be cubit's job on dst",
        );
    }
}

#[test]
fn migrate_plan_psbt_label_includes_dst_wallet_name_when_provided() {
    // When the caller supplies `dst_wallet_name`, every child PSBT of
    // a Migrate plan carries `"Migration → <name>"` regardless of the
    // source coin's own label. The inheritable label (UTXO-derived)
    // still travels in `APISpacedPlanRow.label` for dst seeding.
    use crate::core::wallet_persistence::labels::set_coin_label;
    use crate::core::wallet_persistence::psbt_storage::get_psbt_row;

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let outpoint = format!("{}:{}", funded.txid, funded.vout);
    {
        let core = src.lock_wallet().unwrap();
        set_coin_label(&core.conn, &outpoint, "Salary", false, None).unwrap();
    }

    let dst_addrs = peek_addresses(&dst, 2);
    let mut params = default_params(dst_addrs);
    params.dst_wallet_name = Some("Cold".into());
    let summary = src.plan_spaced_txs(params).unwrap();
    assert_eq!(summary.rows.len(), 1);

    let core = src.lock_wallet().unwrap();
    let psbt = get_psbt_row(&core.conn, summary.rows[0].psbt_id).unwrap();
    assert_eq!(psbt.label.as_deref(), Some("Migration → Cold"));
    assert_eq!(summary.rows[0].label, "Salary");
}

#[test]
fn refresh_plan_does_not_overwrite_explicit_destination_label() {
    use crate::core::wallet_persistence::labels::{
        get_address_label_with_flag, set_address_label, set_coin_label,
    };

    let src_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let outpoint = format!("{}:{}", funded.txid, funded.vout);
    let dst_addrs = peek_addresses(&src, 2);

    // The destination address is pre-labelled by the user. The plan must
    // not clobber that with an auto-label.
    {
        let core = src.lock_wallet().unwrap();
        set_coin_label(&core.conn, &outpoint, "Salary", false, None).unwrap();
        set_address_label(&core.conn, &dst_addrs[0], "User pick", false, None).unwrap();
    }

    src.plan_spaced_txs(refresh_params(&src, dst_addrs.clone()))
        .unwrap();

    let core = src.lock_wallet().unwrap();
    let kept = get_address_label_with_flag(&core.conn, &dst_addrs[0]).unwrap();
    assert_eq!(kept, Some(("User pick".to_string(), false)));
}

#[test]
fn cancel_clears_plan_auto_labels() {
    use crate::core::wallet_persistence::labels::{get_address_label_with_flag, set_coin_label};

    let src_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let outpoint = format!("{}:{}", funded.txid, funded.vout);
    {
        let core = src.lock_wallet().unwrap();
        set_coin_label(&core.conn, &outpoint, "Salary", false, None).unwrap();
    }

    // `Refresh` plan so the source DB carries the auto-labels we
    // expect cancel to sweep. `Migrate` plans write labels onto the
    // destination DB instead — covered by
    // `clear_spaced_plan_labels_sweeps_only_target_plan`.
    let dst_addrs = peek_addresses(&src, 2);
    let summary = src
        .plan_spaced_txs(refresh_params(&src, dst_addrs.clone()))
        .unwrap();

    // Pre-cancel: dst addresses carry the auto-label.
    {
        let core = src.lock_wallet().unwrap();
        for addr in &summary.rows[0].recipient_addresses {
            assert_eq!(
                get_address_label_with_flag(&core.conn, addr).unwrap(),
                Some(("Salary".to_string(), true)),
            );
        }
    }

    src.cancel_spaced_plan(summary.plan_id).unwrap();

    // Post-cancel: every plan-sourced auto-label is gone; the source
    // coin label survives.
    let core = src.lock_wallet().unwrap();
    for addr in &dst_addrs {
        let labelled = get_address_label_with_flag(&core.conn, addr).unwrap();
        assert!(labelled.is_none(), "{addr} still labelled after cancel");
    }
}

#[test]
fn set_spaced_plan_address_labels_seeds_dst_db_and_preserves_explicit() {
    use crate::api::model::APISpacedPlanAddressLabel;
    use crate::core::wallet_persistence::labels::{get_address_label_with_flag, set_address_label};

    // The destination wallet receives the labels via the cubit, which
    // calls this FFI on the destination handle. We simulate that
    // flow directly: skip the source-side plan, just call the FFI
    // and check that auto-labels land while explicit labels survive.
    let dst_dir = tempdir().unwrap();
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");
    let dst_addrs = peek_addresses(&dst, 3);

    {
        let core = dst.lock_wallet().unwrap();
        set_address_label(&core.conn, &dst_addrs[1], "User pick", false, None).unwrap();
    }

    let entries: Vec<APISpacedPlanAddressLabel> = dst_addrs
        .iter()
        .map(|addr| APISpacedPlanAddressLabel {
            plan_id: 42,
            src_txid: "a".repeat(64),
            src_vout: 0,
            address: addr.clone(),
            label: "Migration 2026 (aaaa…aaaa:0)".into(),
        })
        .collect();
    dst.set_spaced_plan_address_labels(entries).unwrap();

    let core = dst.lock_wallet().unwrap();
    // [0] and [2] picked up the seeded label. The flag is `false`
    // (own/explicit) on purpose: the dst wallet's UI must surface
    // migrated labels as the user's own, not as auto-inherited.
    for idx in [0_usize, 2] {
        assert_eq!(
            get_address_label_with_flag(&core.conn, &dst_addrs[idx]).unwrap(),
            Some(("Migration 2026 (aaaa…aaaa:0)".to_string(), false)),
        );
    }
    // [1] kept the user-supplied explicit label.
    assert_eq!(
        get_address_label_with_flag(&core.conn, &dst_addrs[1]).unwrap(),
        Some(("User pick".to_string(), false)),
    );
}

#[test]
fn clear_spaced_plan_labels_sweeps_only_target_plan() {
    use crate::api::model::APISpacedPlanAddressLabel;
    use crate::core::wallet_persistence::labels::get_address_label_with_flag;

    let dst_dir = tempdir().unwrap();
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");
    let dst_addrs = peek_addresses(&dst, 4);

    let entry = |plan_id: i64, address: &str, label: &str| APISpacedPlanAddressLabel {
        plan_id,
        src_txid: "b".repeat(64),
        src_vout: 0,
        address: address.into(),
        label: label.into(),
    };

    // Two plans seed the same destination wallet.
    dst.set_spaced_plan_address_labels(vec![
        entry(1, &dst_addrs[0], "plan-1 label"),
        entry(1, &dst_addrs[1], "plan-1 label"),
        entry(2, &dst_addrs[2], "plan-2 label"),
        entry(2, &dst_addrs[3], "plan-2 label"),
    ])
    .unwrap();

    dst.clear_spaced_plan_labels(1).unwrap();

    let core = dst.lock_wallet().unwrap();
    // Plan 1 entries swept.
    for idx in [0_usize, 1] {
        assert!(
            get_address_label_with_flag(&core.conn, &dst_addrs[idx])
                .unwrap()
                .is_none(),
            "plan-1 label on {} should have been cleared",
            dst_addrs[idx],
        );
    }
    // Plan 2 entries survive. `set_spaced_plan_address_labels` stores
    // them as own (is_auto = false); the sweep keys on source_entity,
    // not on the flag.
    for idx in [2_usize, 3] {
        assert_eq!(
            get_address_label_with_flag(&core.conn, &dst_addrs[idx]).unwrap(),
            Some(("plan-2 label".to_string(), false)),
        );
    }
}

#[test]
fn split_propagates_label_to_both_destination_addresses() {
    use crate::core::wallet_persistence::labels::{get_address_label_with_flag, set_coin_label};

    let src_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");

    let funded = inject_confirmed_utxo(&src, 0xaa, 100, 5_000_000).unwrap();
    let outpoint = format!("{}:{}", funded.txid, funded.vout);
    {
        let core = src.lock_wallet().unwrap();
        set_coin_label(&core.conn, &outpoint, "Inheritance refresh", false, None).unwrap();
    }

    // `Refresh` plan so the source DB is where the auto-labels land
    // (MIGRATE delegates that write to the destination wallet via the
    // cubit; covered by the dedicated `set_spaced_plan_address_labels` tests).
    let dst_addrs = peek_addresses(&src, 8);
    let mut params = refresh_params(&src, dst_addrs.clone());
    params.split_probability = 1.0;
    let summary = src.plan_spaced_txs(params).unwrap();
    let row = &summary.rows[0];
    assert!(row.split);
    assert_eq!(row.recipient_addresses.len(), 2);

    let core = src.lock_wallet().unwrap();
    for addr in &row.recipient_addresses {
        assert_eq!(
            get_address_label_with_flag(&core.conn, addr).unwrap(),
            Some(("Inheritance refresh".to_string(), true)),
        );
    }
}

#[test]
fn split_requires_two_addresses_per_utxo_upfront() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();

    let mut params = default_params(peek_addresses(&dst, 3)); // 3 < 2 * 2
    params.split_probability = 0.5;
    let err = src.plan_spaced_txs(params).unwrap_err().to_string();
    assert!(err.contains("destination addresses"), "got: {err}");
}

#[test]
fn happy_path_persists_draft_plan_and_links_psbts() {
    use crate::core::wallet_persistence::tx_plan_storage::{
        get_tx_plan, list_unsigned_tx_ids_for_plan, TxPlanStatus,
    };

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();

    let params = default_params(peek_addresses(&dst, 4));
    let summary = src.plan_spaced_txs(params).expect("plan must succeed");

    let core = src.lock_wallet().unwrap();
    let plan = get_tx_plan(&core.conn, summary.plan_id)
        .unwrap()
        .expect("plan persisted");
    assert_eq!(plan.status, TxPlanStatus::Draft);
    let child_ids = list_unsigned_tx_ids_for_plan(&core.conn, summary.plan_id).unwrap();
    assert_eq!(child_ids.len(), 2);
    let summary_ids: Vec<i64> = summary.rows.iter().map(|r| r.psbt_id).collect();
    for id in &summary_ids {
        assert!(child_ids.contains(id));
    }
}

#[test]
fn deterministic_seed_produces_same_nlocktime_distribution() {
    let src_dir_a = tempdir().unwrap();
    let dst_dir_a = tempdir().unwrap();
    let src_dir_b = tempdir().unwrap();
    let dst_dir_b = tempdir().unwrap();

    let mut summaries = Vec::new();
    for (src_dir, dst_dir) in [(&src_dir_a, &dst_dir_a), (&src_dir_b, &dst_dir_b)] {
        let src = make_wallet_for(src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
        let dst = make_wallet_for(dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");
        for (seed, height) in [(0xaa_u8, 100u32), (0xbb, 101), (0xcc, 102)] {
            inject_confirmed_utxo(&src, seed, height, 500_000).unwrap();
        }
        let mut params = default_params(peek_addresses(&dst, 8));
        params.rng_seed = Some(7);
        let summary = src.plan_spaced_txs(params).unwrap();
        summaries.push(summary);
    }
    let [a, b]: [_; 2] = summaries.try_into().unwrap();
    let order_a: Vec<u32> = a.rows.iter().map(|r| r.nlocktime_delta_blocks).collect();
    let order_b: Vec<u32> = b.rows.iter().map(|r| r.nlocktime_delta_blocks).collect();
    assert_eq!(order_a, order_b, "same seed must produce same delays");
}

#[test]
fn second_plan_blocked_until_first_is_cancelled() {
    use crate::core::wallet_persistence::tx_plan_storage::delete_tx_plan;

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();

    let params1 = default_params(peek_addresses(&dst, 2));
    let first = src.plan_spaced_txs(params1).expect("first plan");

    let params2 = default_params(peek_addresses(&dst, 2));
    let err = src.plan_spaced_txs(params2).unwrap_err().to_string();
    assert!(err.contains("active plan"), "got: {err}");

    // After cascade-cancelling, a new plan should be allowed.
    {
        let core = src.lock_wallet().unwrap();
        delete_tx_plan(&core.conn, first.plan_id).unwrap();
    }
    let params3 = default_params(peek_addresses(&dst, 2));
    assert!(src.plan_spaced_txs(params3).is_ok());
}

#[test]
fn selected_utxos_filter_restricts_plan_to_subset() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    let kept = inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xcc, 102, 500_000).unwrap();

    let mut params = default_params(peek_addresses(&dst, 4));
    params.selected_utxos = vec![APICoinControl {
        txid: kept.txid.to_string(),
        vout: kept.vout,
    }];

    let summary = src.plan_spaced_txs(params).expect("plan");
    assert_eq!(summary.rows.len(), 1);
    assert_eq!(summary.rows[0].utxo_txid, kept.txid.to_string());
}

// ---------------------------------------------------------------------------
// prepare_spaced_plan_psbts
// ---------------------------------------------------------------------------

#[test]
fn prepare_rejects_unknown_plan() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let err = wallet
        .prepare_spaced_plan_psbts(9_999)
        .unwrap_err()
        .to_string();
    assert!(err.contains("not found"), "got: {err}");
}

#[test]
fn prepare_returns_bundle_with_every_pending_child() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xcc, 102, 500_000).unwrap();

    let mut params = default_params(peek_addresses(&dst, 4));
    params.spend_path_id = first_spend_path_id(&src);
    let summary = src.plan_spaced_txs(params).expect("plan");

    let bundle = src
        .prepare_spaced_plan_psbts(summary.plan_id)
        .expect("prepare");

    // Plan-level fields are populated from the wallet, not duplicated per child.
    assert_eq!(bundle.plan_id, summary.plan_id);
    assert!(!bundle.descriptor.is_empty());
    assert_eq!(bundle.network, APINetwork::Bitcoin);
    assert_eq!(bundle.threshold, 2);
    assert_eq!(bundle.mfps.len(), 2);
    // key_changes carries one entry per cosigner of the chosen spend path.
    for mfp in &bundle.mfps {
        assert!(
            bundle.key_changes.contains_key(mfp),
            "mfp {mfp} missing from key_changes"
        );
    }

    // One entry per persisted child, none finalised, signers populated.
    assert_eq!(bundle.children.len(), 3);
    let mut ids: Vec<i64> = bundle.children.iter().map(|c| c.psbt_id).collect();
    ids.sort();
    let mut expected: Vec<i64> = summary.rows.iter().map(|r| r.psbt_id).collect();
    expected.sort();
    assert_eq!(ids, expected);
    for child in &bundle.children {
        assert!(!child.psbt_b64.is_empty());
        assert!(!child.is_finalized);
        assert_eq!(child.signers.len(), 2);
        for s in &child.signers {
            assert!(!s.has_signed);
        }
    }
}

#[test]
fn prepare_marks_finalised_children() {
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();

    let mut params = default_params(peek_addresses(&dst, 4));
    params.spend_path_id = first_spend_path_id(&src);
    let summary = src.plan_spaced_txs(params).expect("plan");

    let target_id = summary.rows[0].psbt_id;
    force_finalise_stored_psbt(&src, target_id);

    let bundle = src
        .prepare_spaced_plan_psbts(summary.plan_id)
        .expect("prepare");
    let target = bundle
        .children
        .iter()
        .find(|c| c.psbt_id == target_id)
        .unwrap();
    let other = bundle
        .children
        .iter()
        .find(|c| c.psbt_id != target_id)
        .unwrap();
    assert!(target.is_finalized);
    assert!(!other.is_finalized);
}

#[test]
fn prepare_works_on_signed_plan() {
    use crate::core::wallet_persistence::tx_plan_storage::{get_tx_plan, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let mut params = default_params(peek_addresses(&dst, 2));
    params.spend_path_id = first_spend_path_id(&src);
    let summary = src.plan_spaced_txs(params).expect("plan");

    // Move plan to SIGNED by finalising the child and committing.
    let child_id = summary.rows[0].psbt_id;
    force_finalise_stored_psbt(&src, child_id);
    let report = src.commit_spaced_plan(summary.plan_id).expect("commit");
    assert!(report.committed);
    {
        let core = src.lock_wallet().unwrap();
        assert_eq!(
            get_tx_plan(&core.conn, summary.plan_id)
                .unwrap()
                .unwrap()
                .status,
            TxPlanStatus::Signed
        );
    }

    let bundle = src
        .prepare_spaced_plan_psbts(summary.plan_id)
        .expect("prepare");
    assert_eq!(bundle.children.len(), 1);
}

#[test]
fn prepare_rejects_terminal_plan() {
    use crate::core::wallet_persistence::tx_plan_storage::{set_tx_plan_status, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let mut params = default_params(peek_addresses(&dst, 2));
    params.spend_path_id = first_spend_path_id(&src);
    let summary = src.plan_spaced_txs(params).expect("plan");

    {
        let core = src.lock_wallet().unwrap();
        set_tx_plan_status(&core.conn, summary.plan_id, TxPlanStatus::Cancelled).unwrap();
    }
    let err = src
        .prepare_spaced_plan_psbts(summary.plan_id)
        .unwrap_err()
        .to_string();
    assert!(
        err.contains("Cancelled") || err.contains("requires DRAFT"),
        "got: {err}"
    );
}

#[test]
fn prepare_errors_when_plan_has_no_children() {
    use crate::core::wallet_persistence::psbt_storage::delete_psbt_row;
    use crate::core::wallet_persistence::tx_plan_storage::list_unsigned_tx_ids_for_plan;

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let mut params = default_params(peek_addresses(&dst, 2));
    params.spend_path_id = first_spend_path_id(&src);
    let summary = src.plan_spaced_txs(params).expect("plan");

    {
        let core = src.lock_wallet().unwrap();
        for id in list_unsigned_tx_ids_for_plan(&core.conn, summary.plan_id).unwrap() {
            delete_psbt_row(&core.conn, id).unwrap();
        }
    }
    let err = src
        .prepare_spaced_plan_psbts(summary.plan_id)
        .unwrap_err()
        .to_string();
    assert!(err.contains("no pending"), "got: {err}");
}

// ---------------------------------------------------------------------------
// sign_spaced_plan_with_hot_key
// ---------------------------------------------------------------------------

#[test]
fn sign_with_hot_key_rejects_unknown_plan() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let err = wallet
        .sign_spaced_plan_with_hot_key(9_999, "c449c5c5".into())
        .unwrap_err()
        .to_string();
    assert!(err.contains("not found"), "got: {err}");
}

#[test]
fn sign_with_hot_key_rejects_terminal_plan() {
    use crate::core::wallet_persistence::tx_plan_storage::{set_tx_plan_status, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .expect("plan");

    {
        let core = src.lock_wallet().unwrap();
        set_tx_plan_status(&core.conn, summary.plan_id, TxPlanStatus::Cancelled).unwrap();
    }
    let err = src
        .sign_spaced_plan_with_hot_key(summary.plan_id, "c449c5c5".into())
        .unwrap_err()
        .to_string();
    assert!(err.contains("requires DRAFT"), "got: {err}");
}

#[test]
fn sign_with_hot_key_reports_per_row_failure_for_unknown_mfp() {
    // The wallet has no seeds loaded (cosigner xpubs only), so every row
    // fails with the "no signer for mfp" error path inside
    // `sign_psbt_with_key`. This exercises the orchestration without
    // requiring a real signing seed.
    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 4)))
        .expect("plan");

    let report = src
        .sign_spaced_plan_with_hot_key(summary.plan_id, "deadbeef".into())
        .expect("batch must not abort");
    assert_eq!(report.plan_id, summary.plan_id);
    assert_eq!(report.total, 2);
    assert!(report.signed_ids.is_empty());
    assert_eq!(report.failed.len(), 2);
    let failed_ids: std::collections::HashSet<i64> =
        report.failed.iter().map(|f| f.psbt_id).collect();
    for row in &summary.rows {
        assert!(failed_ids.contains(&row.psbt_id));
    }
}

// ---------------------------------------------------------------------------
// apply_spaced_plan_signed_psbts
// ---------------------------------------------------------------------------

#[test]
fn apply_rejects_unknown_plan() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet_for(&dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let err = wallet
        .apply_spaced_plan_signed_psbts(9_999, vec![])
        .unwrap_err()
        .to_string();
    assert!(err.contains("not found"), "got: {err}");
}

#[test]
fn apply_rejects_terminal_plan() {
    use crate::core::wallet_persistence::tx_plan_storage::{set_tx_plan_status, TxPlanStatus};

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .expect("plan");

    {
        let core = src.lock_wallet().unwrap();
        set_tx_plan_status(&core.conn, summary.plan_id, TxPlanStatus::Cancelled).unwrap();
    }
    let err = src
        .apply_spaced_plan_signed_psbts(summary.plan_id, vec![])
        .unwrap_err()
        .to_string();
    assert!(err.contains("requires DRAFT"), "got: {err}");
}

#[test]
fn apply_reports_unknown_psbt_id_under_failed() {
    use crate::api::model::APISignedChildPsbt;

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .expect("plan");

    let report = src
        .apply_spaced_plan_signed_psbts(
            summary.plan_id,
            vec![APISignedChildPsbt {
                psbt_id: 4_242,
                signed_b64: "garbage".into(),
            }],
        )
        .expect("batch must not abort");
    assert_eq!(report.total, 1);
    assert!(report.signed_ids.is_empty());
    assert_eq!(report.failed.len(), 1);
    assert_eq!(report.failed[0].psbt_id, 4_242);
    assert!(
        report.failed[0].error.contains("does not belong"),
        "got: {}",
        report.failed[0].error
    );
}

#[test]
fn apply_reports_merge_errors_per_row() {
    use crate::api::model::APISignedChildPsbt;

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 2)))
        .expect("plan");

    let psbt_id = summary.rows[0].psbt_id;
    let report = src
        .apply_spaced_plan_signed_psbts(
            summary.plan_id,
            vec![APISignedChildPsbt {
                psbt_id,
                signed_b64: "not-a-real-psbt".into(),
            }],
        )
        .expect("batch must not abort");
    assert_eq!(report.total, 1);
    assert!(report.signed_ids.is_empty());
    assert_eq!(report.failed.len(), 1);
    assert_eq!(report.failed[0].psbt_id, psbt_id);
}

#[test]
fn apply_happy_path_merges_when_signed_b64_matches_stored() {
    // Pass the stored PSBT back as if it were "signed". `Psbt::combine`
    // accepts identical inputs (no new sigs to merge), so the call
    // succeeds and the row goes to `signed_ids` even though no real
    // signatures changed. This covers the merge orchestration without
    // needing hot-key material.
    use crate::api::model::APISignedChildPsbt;
    use crate::core::wallet_persistence::psbt_storage::get_psbt_row;

    let src_dir = tempdir().unwrap();
    let dst_dir = tempdir().unwrap();
    let src = make_wallet_for(&src_dir, MAINNET_DESC, APINetwork::Bitcoin, "src");
    let dst = make_wallet_for(&dst_dir, MAINNET_DESC, APINetwork::Bitcoin, "dst");

    inject_confirmed_utxo(&src, 0xaa, 100, 500_000).unwrap();
    inject_confirmed_utxo(&src, 0xbb, 101, 500_000).unwrap();
    let summary = src
        .plan_spaced_txs(default_params(peek_addresses(&dst, 4)))
        .expect("plan");

    let mut signed_input = Vec::new();
    {
        let core = src.lock_wallet().unwrap();
        for row in &summary.rows {
            let r = get_psbt_row(&core.conn, row.psbt_id).unwrap();
            signed_input.push(APISignedChildPsbt {
                psbt_id: row.psbt_id,
                signed_b64: r.psbt,
            });
        }
    }
    let report = src
        .apply_spaced_plan_signed_psbts(summary.plan_id, signed_input)
        .expect("apply");
    assert_eq!(report.total, 2);
    assert!(
        report.failed.is_empty(),
        "unexpected failures: {:?}",
        report.failed
    );
    let mut signed = report.signed_ids.clone();
    signed.sort();
    let mut expected: Vec<i64> = summary.rows.iter().map(|r| r.psbt_id).collect();
    expected.sort();
    assert_eq!(signed, expected);
}
