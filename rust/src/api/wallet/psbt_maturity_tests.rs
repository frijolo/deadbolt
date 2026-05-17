use super::*;
use crate::api::model::{
    APIAbsoluteTimelock, APIAbsoluteTimelockType, APIPsbtInfo, APIRecipient, APIRelativeTimelock,
    APISpendPath,
};
use std::collections::HashMap;

fn make_info(lock_time: u32, utxo_max_conf_height: Option<i64>) -> APIPsbtInfo {
    APIPsbtInfo {
        id: 1,
        psbt_base64: String::new(),
        txid: String::from("aa"),
        label: None,
        effective_label: None,
        is_auto: false,
        is_self_transfer: false,
        created_at: 0,
        recipient: String::from("bc1q"),
        amount_sat: 1000,
        recipients: vec![APIRecipient {
            address: String::from("bc1q"),
            amount_sat: 1000,
            op_return_data: None,
        }],
        fee_sat: 100,
        spend_path_id: 0,
        threshold: 1,
        mfps: vec![],
        utxo_max_conf_height,
        has_spent_inputs: false,
        lock_time,
        auto_broadcast: false,
    }
}

fn make_spend_path(
    rel_value: u32,
    rel_type: APIRelativeTimelockType,
    abs_value: u32,
    abs_type: APIAbsoluteTimelockType,
) -> APISpendPath {
    APISpendPath {
        id: 1,
        policy_path: vec![],
        threshold: 1,
        mfps: vec![],
        rel_timelock: APIRelativeTimelock {
            timelock_type: rel_type,
            value: rel_value,
        },
        abs_timelock: APIAbsoluteTimelock {
            timelock_type: abs_type,
            value: abs_value,
        },
        wu_base: 0,
        wu_in: 0,
        wu_out: 0,
        tr_depth: -1,
        key_changes: HashMap::new(),
        vb_sweep: 0.0,
    }
}

#[test]
fn no_timelock_is_ready() {
    let info = make_info(0, None);
    assert_eq!(
        psbt_broadcast_readiness(&info, None, 800_000, 1_700_000_000),
        BroadcastReadiness::Ready
    );
}

#[test]
fn absolute_blocks_locked_when_tip_below_locktime() {
    let info = make_info(800_010, None);
    assert_eq!(
        psbt_broadcast_readiness(&info, None, 800_000, 1_700_000_000),
        BroadcastReadiness::Locked
    );
}

#[test]
fn absolute_blocks_ready_at_locktime() {
    let info = make_info(800_010, None);
    assert_eq!(
        psbt_broadcast_readiness(&info, None, 800_010, 1_700_000_000),
        BroadcastReadiness::Ready
    );
}

#[test]
fn absolute_blocks_ready_when_tip_above_locktime() {
    let info = make_info(800_010, None);
    assert!(psbt_is_broadcastable_now(
        &info,
        None,
        800_011,
        1_700_000_000
    ));
}

#[test]
fn absolute_blocks_unknown_tip_means_sync_required() {
    let info = make_info(800_010, None);
    assert_eq!(
        psbt_broadcast_readiness(&info, None, 0, 1_700_000_000),
        BroadcastReadiness::SyncRequired
    );
}

#[test]
fn absolute_timestamp_locked_when_now_below_locktime() {
    let info = make_info(1_800_000_000, None);
    assert_eq!(
        psbt_broadcast_readiness(&info, None, 800_000, 1_700_000_000),
        BroadcastReadiness::Locked
    );
}

#[test]
fn absolute_timestamp_ready_when_now_at_or_above_locktime() {
    let info = make_info(1_700_000_000, None);
    assert!(psbt_is_broadcastable_now(
        &info,
        None,
        800_000,
        1_700_000_000
    ));
    let info = make_info(1_700_000_000, None);
    assert!(psbt_is_broadcastable_now(
        &info,
        None,
        800_000,
        1_700_000_005
    ));
}

#[test]
fn relative_blocks_locked_when_utxo_too_young() {
    // PSBT itself has no nLockTime, but the chosen spend path requires
    // 144 blocks of confirmations on every input. utxo_max_conf_height = 799_900,
    // tip = 800_000 → only 100 confirmations.
    let info = make_info(0, Some(799_900));
    let path = make_spend_path(
        144,
        APIRelativeTimelockType::Blocks,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert_eq!(
        psbt_broadcast_readiness(&info, Some(&path), 800_000, 1_700_000_000),
        BroadcastReadiness::Locked
    );
}

#[test]
fn relative_blocks_ready_one_block_before_strict_maturity() {
    // BIP68 regression: with rel=1 and the UTXO confirmed at tip (1 confirmation),
    // the next mined block (tip+1) satisfies the sequence lock, so the PSBT is
    // ready. A naive `tip < conf + rel` check would incorrectly mark it Locked.
    let info = make_info(0, Some(800_000));
    let path = make_spend_path(
        1,
        APIRelativeTimelockType::Blocks,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert_eq!(
        psbt_broadcast_readiness(&info, Some(&path), 800_000, 1_700_000_000),
        BroadcastReadiness::Ready
    );
}

#[test]
fn relative_blocks_locked_two_blocks_before_strict_maturity() {
    // Sanity: one block earlier than the BIP68 boundary is still locked.
    let info = make_info(0, Some(800_000));
    let path = make_spend_path(
        2,
        APIRelativeTimelockType::Blocks,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert_eq!(
        psbt_broadcast_readiness(&info, Some(&path), 800_000, 1_700_000_000),
        BroadcastReadiness::Locked
    );
}

#[test]
fn relative_blocks_ready_when_utxo_mature() {
    let info = make_info(0, Some(799_900));
    let path = make_spend_path(
        100,
        APIRelativeTimelockType::Blocks,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert_eq!(
        psbt_broadcast_readiness(&info, Some(&path), 800_000, 1_700_000_000),
        BroadcastReadiness::Ready
    );
}

#[test]
fn relative_blocks_without_utxo_height_means_sync_required() {
    let info = make_info(0, None);
    let path = make_spend_path(
        100,
        APIRelativeTimelockType::Blocks,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert_eq!(
        psbt_broadcast_readiness(&info, Some(&path), 800_000, 1_700_000_000),
        BroadcastReadiness::SyncRequired
    );
}

#[test]
fn relative_time_is_unsupported_for_now() {
    let info = make_info(0, Some(799_900));
    let path = make_spend_path(
        3600,
        APIRelativeTimelockType::Time,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert_eq!(
        psbt_broadcast_readiness(&info, Some(&path), 800_000, 1_700_000_000),
        BroadcastReadiness::Unsupported
    );
}

#[test]
fn absolute_blocks_ok_but_relative_blocks_still_locked() {
    let mut info = make_info(800_010, Some(799_990));
    info.utxo_max_conf_height = Some(799_990);
    // Tip is at lock_time but rel timelock needs 144 more blocks past 799_990.
    let path = make_spend_path(
        144,
        APIRelativeTimelockType::Blocks,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert_eq!(
        psbt_broadcast_readiness(&info, Some(&path), 800_010, 1_700_000_000),
        BroadcastReadiness::Locked
    );
}

#[test]
fn both_locks_satisfied_is_ready() {
    let info = make_info(800_010, Some(799_900));
    let path = make_spend_path(
        50,
        APIRelativeTimelockType::Blocks,
        0,
        APIAbsoluteTimelockType::Blocks,
    );
    assert!(psbt_is_broadcastable_now(
        &info,
        Some(&path),
        800_010,
        1_700_000_000
    ));
}

#[test]
fn has_spent_inputs_blocks_broadcast_even_when_unlocked() {
    let mut info = make_info(0, None);
    info.has_spent_inputs = true;
    assert_eq!(
        psbt_broadcast_readiness(&info, None, 800_000, 1_700_000_000),
        BroadcastReadiness::Locked
    );
}
