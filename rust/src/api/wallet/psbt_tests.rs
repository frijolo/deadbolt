use super::*;
use crate::api::model::{APICoinControl, APIPolicyPath, APIRecipient};
use crate::core::descriptor::DescriptorAnalyzer;
use crate::test_support::{
    KEY_HEX, MAINNET_DESC, SIGNET_ABSOLUTE_TIMELOCK_DESC, SIGNET_ABSOLUTE_TIMELOCK_HEIGHT,
    SIGNET_INHERITANCE_DESC,
};
use bdk_wallet::bitcoin::{absolute, transaction, Amount, OutPoint, Sequence, Transaction, TxIn};
use bdk_wallet::KeychainKind;
use tempfile::tempdir;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn make_wallet(dir: &tempfile::TempDir, descriptor: &str, network: APINetwork) -> APIWallet {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = create_wallet(
        wallets_dir,
        "Test".to_string(),
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

/// Inject a 1 000 000 sat UTXO to address index 0 and return the funding txid.
fn inject_utxo(wallet: &APIWallet) -> bdk_wallet::bitcoin::Txid {
    let spk = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 0)
            .address
            .script_pubkey()
    };
    let fake_prev = OutPoint {
        txid: bdk_wallet::bitcoin::Txid::from_raw_hash(
            *bdk_wallet::bitcoin::hashes::sha256d::Hash::from_bytes_ref(&[1u8; 32]),
        ),
        vout: 0,
    };
    let funding_tx = Transaction {
        version: transaction::Version::TWO,
        lock_time: absolute::LockTime::ZERO,
        input: vec![TxIn {
            previous_output: fake_prev,
            sequence: Sequence::MAX,
            ..Default::default()
        }],
        output: vec![bdk_wallet::bitcoin::TxOut {
            value: Amount::from_sat(1_000_000),
            script_pubkey: spk,
        }],
    };
    let txid = funding_tx.compute_txid();
    wallet
        .inject_unconfirmed_tx(funding_tx)
        .expect("inject_unconfirmed_tx failed");
    txid
}

/// Build a PSBT for the given spend path, delete the stored record, and return the raw base64.
/// Simulates the originating party exporting the PSBT to a QR / file.
fn create_and_export_psbt(
    wallet: &APIWallet,
    funding_txid: bdk_wallet::bitcoin::Txid,
    sp: &crate::core::spend_path::SpendPath,
    recv_addr: &str,
) -> anyhow::Result<String> {
    let policy_path = APIPolicyPath::from_spendpath(sp)?;
    let psbt_info = wallet.create_psbt(
        vec![APIRecipient {
            address: recv_addr.to_string(),
            amount_sat: 500_000,
            op_return_data: None,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        policy_path,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
        None,
    )?;
    let base64 = psbt_info.psbt_base64.clone();
    wallet.delete_psbt(psbt_info.id)?;
    Ok(base64)
}

/// Core of the import-infers-spend-path tests. Creates a PSBT for the spend path that
/// matches `rel_tl` and verifies that `import_psbt` reconstructs the correct metadata.
fn assert_import_infers_spend_path(rel_tl: u32) -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);

    let analyzer = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let core_paths = analyzer.spend_paths()?;
    let sp = core_paths
        .iter()
        .find(|sp| sp.rel_timelock == rel_tl && sp.abs_timelock == 0)
        .unwrap_or_else(|| panic!("spend path with rel_tl={} not in descriptor", rel_tl));

    let recv_addr = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 1)
            .address
            .to_string()
    };

    let psbt_base64 = create_and_export_psbt(&wallet, funding_txid, sp, &recv_addr)?;
    let result = wallet.import_psbt(psbt_base64)?;

    assert_eq!(result.psbt.spend_path_id, sp.id, "spend_path_id mismatch");
    assert_eq!(
        result.psbt.threshold, sp.threshold as u32,
        "threshold mismatch"
    );
    assert_eq!(result.psbt.mfps, sp.mfps, "mfps mismatch");

    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// import_psbt must infer the heir1 (older(13140)) spend path from nSequence.
#[test]
fn test_import_psbt_infers_heir_spend_path_id() -> anyhow::Result<()> {
    assert_import_infers_spend_path(13140)
}

/// import_psbt must infer the owner (key-path, no timelock) spend path.
#[test]
fn test_import_psbt_infers_owner_spend_path_id() -> anyhow::Result<()> {
    assert_import_infers_spend_path(0)
}

/// import_psbt must infer heir5 (older(6), the smallest relative timelock) from nSequence.
#[test]
fn test_import_psbt_infers_heir5_spend_path_id() -> anyhow::Result<()> {
    assert_import_infers_spend_path(6)
}

/// import_psbt must succeed even when the PSBT carries a non-zero lock_time set by
/// BDK's anti-fee-sniping (a block height, not a miniscript absolute timelock).
#[test]
fn test_import_psbt_ignores_antifee_sniping_locktime() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);

    let analyzer = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let paths = analyzer.spend_paths()?;
    // Owner spend path: key-path only, rel_tl = 0, abs_tl = 0.
    let owner_sp = paths
        .iter()
        .find(|sp| sp.rel_timelock == 0 && sp.abs_timelock == 0)
        .expect("owner spend path not found");

    let recv_addr = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 1)
            .address
            .to_string()
    };

    let psbt_base64 = create_and_export_psbt(&wallet, funding_txid, owner_sp, &recv_addr)?;

    // Patch lock_time to a block height simulating BDK anti-fee-sniping.
    // This must NOT be interpreted as an absolute timelock during import.
    let mut psbt = psbt_from_base64(&psbt_base64)?;
    psbt.unsigned_tx.lock_time = bdk_wallet::bitcoin::absolute::LockTime::from_height(234_567)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let patched = psbt_to_base64(&psbt);

    let result = wallet.import_psbt(patched)?;
    assert_eq!(
        result.psbt.spend_path_id, owner_sp.id,
        "spend_path_id mismatch"
    );
    assert!(!result.was_merged, "expected new import, not merge");

    Ok(())
}

/// A PSBT whose nSequence encodes a timelock not present in the wallet's descriptor
/// must be rejected with an error (not silently stored with spend_path_id = 0).
#[test]
fn test_import_psbt_wrong_wallet_returns_error() -> anyhow::Result<()> {
    let dir_a = tempdir()?;
    let wallet_a = make_wallet(&dir_a, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let txid_a = inject_utxo(&wallet_a);

    let analyzer_a = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let paths_a = analyzer_a.spend_paths()?;
    let heir1 = paths_a.iter().find(|sp| sp.rel_timelock == 13140).unwrap();

    let recv_addr_a = {
        let core = wallet_a.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 1)
            .address
            .to_string()
    };

    let psbt_base64 = create_and_export_psbt(&wallet_a, txid_a, heir1, &recv_addr_a)?;

    // The 2-of-2 wallet has a single spend path with rel_tl=0; older(13140) won't match.
    let dir_b = tempdir()?;
    let wallet_b = make_wallet(&dir_b, MAINNET_DESC, APINetwork::Bitcoin);

    let result = wallet_b.import_psbt(psbt_base64);
    assert!(
        result.is_err(),
        "importing a PSBT from a different wallet must return an error"
    );

    Ok(())
}

// ---------------------------------------------------------------------------
// preview_psbt tests
// ---------------------------------------------------------------------------

/// Build a recipient address (External index 1) for the given wallet.
fn recv_addr_for(wallet: &APIWallet) -> String {
    let core = wallet.lock_wallet().unwrap();
    core.wallet
        .peek_address(KeychainKind::External, 1)
        .address
        .to_string()
}

/// Owner (key-path) spend path of the inheritance descriptor — no timelocks.
fn owner_spend_path() -> crate::core::spend_path::SpendPath {
    let analyzer = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC).unwrap();
    analyzer
        .spend_paths()
        .unwrap()
        .into_iter()
        .find(|sp| sp.rel_timelock == 0 && sp.abs_timelock == 0)
        .expect("owner spend path not found")
}

/// Single-recipient drain: send_sats == input − fee, has_change == false.
#[test]
fn test_preview_drain_single_recipient() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let preview = wallet.preview_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 0, // ignored for drain
            op_return_data: None,
        }],
        Some(0),
        Some(2.0),
        None,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        vec![],
    )?;

    assert!(!preview.insufficient_funds);
    assert!(!preview.has_change, "drain must not have a change output");
    assert_eq!(preview.change_sats, 0);
    assert_eq!(
        preview.send_sats + preview.fee_sats,
        1_000_000,
        "drain must consume the full input (send + fee == input)"
    );
    assert_eq!(preview.recipients.len(), 1);
    assert_eq!(preview.recipients[0].amount_sat, preview.send_sats);
    Ok(())
}

/// Explicit amount with change: change_sats > 0 and >= dust limit, send + change + fee == input.
#[test]
fn test_preview_explicit_amount_with_change() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let preview = wallet.preview_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 600_000,
            op_return_data: None,
        }],
        None,
        Some(2.0),
        None,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        vec![],
    )?;

    assert!(!preview.insufficient_funds);
    assert!(preview.has_change, "should produce a change output");
    assert!(preview.change_sats >= 546, "change must be above dust");
    assert_eq!(preview.send_sats, 600_000);
    assert_eq!(
        preview.send_sats + preview.change_sats + preview.fee_sats,
        1_000_000,
        "send + change + fee == input"
    );
    Ok(())
}

/// Insufficient funds is reported as a flag, not as an error — UI must keep rendering.
#[test]
fn test_preview_insufficient_funds_flag() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let preview = wallet.preview_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 2_000_000, // > balance
            op_return_data: None,
        }],
        None,
        Some(2.0),
        None,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        vec![],
    )?;

    assert!(preview.insufficient_funds);
    assert_eq!(preview.fee_sats, 0);
    assert_eq!(preview.send_sats, 0);
    Ok(())
}

/// preview must reject the absent / both-set fee inputs at the API boundary.
#[test]
fn test_preview_requires_exactly_one_fee_input() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let utxos = vec![APICoinControl {
        txid: funding_txid.to_string(),
        vout: 0,
    }];
    let policy = APIPolicyPath::from_spendpath(&sp)?;

    // Neither set → error.
    let neither = wallet.preview_psbt(
        vec![APIRecipient {
            address: recv.clone(),
            amount_sat: 100_000,
            op_return_data: None,
        }],
        None,
        None,
        None,
        utxos.clone(),
        policy.clone(),
        sp.id,
        vec![],
    );
    assert!(neither.is_err());

    // Both set → error.
    let both = wallet.preview_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 100_000,
            op_return_data: None,
        }],
        None,
        Some(2.0),
        Some(500),
        utxos,
        policy,
        sp.id,
        vec![],
    );
    assert!(both.is_err());
    Ok(())
}

/// Rate ↔ Absolute round-trip: preview with rate r produces fee F. Preview with absolute F
/// produces a rate within ±1 sat/vB of r (the +1 sat drift the old Dart code worked around).
#[test]
fn test_preview_rate_abs_idempotence() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let utxos = vec![APICoinControl {
        txid: funding_txid.to_string(),
        vout: 0,
    }];
    let policy = APIPolicyPath::from_spendpath(&sp)?;

    let recipients = vec![APIRecipient {
        address: recv,
        amount_sat: 600_000,
        op_return_data: None,
    }];

    let by_rate = wallet.preview_psbt(
        recipients.clone(),
        None,
        Some(3.5),
        None,
        utxos.clone(),
        policy.clone(),
        sp.id,
        vec![],
    )?;
    let by_abs = wallet.preview_psbt(
        recipients,
        None,
        None,
        Some(by_rate.fee_sats),
        utxos,
        policy,
        sp.id,
        vec![],
    )?;

    assert_eq!(
        by_rate.fee_sats, by_abs.fee_sats,
        "fee must be invariant under rate→abs round-trip"
    );
    assert_eq!(
        by_rate.total_wu, by_abs.total_wu,
        "weight must be invariant"
    );
    assert!(
        (by_rate.fee_rate_sat_per_vb - by_abs.fee_rate_sat_per_vb).abs() < 0.01,
        "rate must round-trip within rounding tolerance: rate={} abs_rate={}",
        by_rate.fee_rate_sat_per_vb,
        by_abs.fee_rate_sat_per_vb
    );
    Ok(())
}

/// rbf_min_fee_sats = sum(orig_fee + descendant_fees) + new_vbytes + 1.
/// Empty rbf_infos → None.
#[test]
fn test_preview_rbf_min_fee_sats() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let utxos = vec![APICoinControl {
        txid: funding_txid.to_string(),
        vout: 0,
    }];
    let policy = APIPolicyPath::from_spendpath(&sp)?;
    let recipients = vec![APIRecipient {
        address: recv,
        amount_sat: 600_000,
        op_return_data: None,
    }];

    let no_rbf = wallet.preview_psbt(
        recipients.clone(),
        None,
        Some(2.0),
        None,
        utxos.clone(),
        policy.clone(),
        sp.id,
        vec![],
    )?;
    assert!(no_rbf.rbf_min_fee_sats.is_none());

    let with_rbf = wallet.preview_psbt(
        recipients,
        None,
        Some(2.0),
        None,
        utxos,
        policy,
        sp.id,
        vec![APIRbfInfo {
            orig_fee_sat: 1_000,
            orig_vsize: 100,
            orig_fee_rate_sat_per_vb: 10.0,
            descendant_count: 1,
            descendant_fee_sat: Some(500),
            descendant_vsize: 50,
            min_fee_sat: 1_500,
            min_fee_rate_sat_per_vb: 10.0,
        }],
    )?;
    let new_vbytes = ((with_rbf.total_wu as f64) / 4.0).ceil() as u64;
    assert_eq!(
        with_rbf.rbf_min_fee_sats,
        Some(1_000 + 500 + new_vbytes + 1),
        "rbf_min must equal orig_fee + descendant_fees + new_vbytes + 1"
    );
    Ok(())
}

/// Drain plus an explicit recipient: drain output gets remainder; non-drain has explicit amount.
#[test]
fn test_preview_drain_with_other_recipient() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();

    // Two distinct receive addresses.
    let recv0 = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 1)
            .address
            .to_string()
    };
    let recv1 = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 2)
            .address
            .to_string()
    };

    let preview = wallet.preview_psbt(
        vec![
            APIRecipient {
                address: recv0,
                amount_sat: 100_000,
                op_return_data: None,
            },
            APIRecipient {
                address: recv1,
                amount_sat: 0, // ignored — this is the drain
                op_return_data: None,
            },
        ],
        Some(1),
        Some(2.0),
        None,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        vec![],
    )?;

    assert!(!preview.insufficient_funds);
    assert!(
        !preview.has_change,
        "drain absorbs leftover, no change output"
    );
    assert_eq!(
        preview.recipients[0].amount_sat, 100_000,
        "non-drain keeps explicit amount"
    );
    let drain_amount = preview.recipients[1].amount_sat;
    assert!(drain_amount > 0, "drain recipient must receive something");
    assert_eq!(
        100_000 + drain_amount + preview.fee_sats,
        1_000_000,
        "explicit + drain + fee == input"
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// Custom nLockTime broadcast delay tests
// ---------------------------------------------------------------------------

#[test]
fn test_create_psbt_no_delta_no_inheritance_lock() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let info = wallet.create_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 500_000,
            op_return_data: None,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
        None,
    )?;

    assert_eq!(info.lock_time, 0);
    Ok(())
}

#[test]
fn test_create_psbt_with_user_delta() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let tip = wallet.get_tip_height()?;
    let delta: u32 = 144; // ~1 day
    let info = wallet.create_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 500_000,
            op_return_data: None,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
        Some(delta),
    )?;

    assert_eq!(info.lock_time, tip + delta);
    Ok(())
}

#[test]
fn test_create_psbt_inheritance_with_delta() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_ABSOLUTE_TIMELOCK_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let recv = recv_addr_for(&wallet);

    let analyzer = DescriptorAnalyzer::analyze(SIGNET_ABSOLUTE_TIMELOCK_DESC)?;
    let paths = analyzer.spend_paths()?;
    let heir = paths
        .iter()
        .find(|sp| sp.abs_timelock > 0)
        .expect("descriptor must expose an absolute-timelock heir path");
    assert_eq!(heir.abs_timelock, SIGNET_ABSOLUTE_TIMELOCK_HEIGHT);
    let heir_id = heir.id;
    let heir_abs_timelock = heir.abs_timelock;
    let heir_threshold = heir.threshold as u32;
    let heir_mfps = heir.mfps.clone();
    let heir_policy = APIPolicyPath::from_spendpath(heir)?;

    let tip = wallet.get_tip_height()?;
    let delta: u32 = 6; // ~1 hour
    let info = wallet.create_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 500_000,
            op_return_data: None,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        heir_policy,
        heir_id,
        heir_threshold,
        heir_mfps,
        Some(delta),
    )?;

    let expected = tip.max(heir_abs_timelock) + delta;
    assert_eq!(info.lock_time, expected);
    Ok(())
}

#[test]
fn test_create_psbt_rejects_excessive_delta() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_spend_path();
    let recv = recv_addr_for(&wallet);

    let result = wallet.create_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 500_000,
            op_return_data: None,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
        Some(crate::api::wallet::psbt::MAX_NLOCKTIME_DELTA_BLOCKS + 1),
    );

    assert!(result.is_err());
    Ok(())
}

/// User-requested nLockTime delay on top of a spend path that carries a
/// **relative** timelock (`older()` / OP_CSV). The two mechanisms are
/// independent — nLockTime gates broadcast on absolute height, nSequence/CSV
/// gates on UTXO age — so combining them must not produce a contradictory
/// PSBT: BDK keeps the CSV sequence on the input (bit 31 clear, value =
/// spend path's `rel_timelock`) and our fixup pushes the absolute nLockTime
/// to `tip + delta`.
#[test]
fn test_create_psbt_relative_timelock_with_delta() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let recv = recv_addr_for(&wallet);

    // Inheritance descriptor heirs all use `older(N)` → relative timelock.
    let analyzer = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let paths = analyzer.spend_paths()?;
    let heir = paths
        .iter()
        .filter(|sp| sp.rel_timelock > 0 && sp.abs_timelock == 0)
        .min_by_key(|sp| sp.rel_timelock)
        .expect("descriptor must expose at least one relative-timelock heir path");
    let heir_id = heir.id;
    let heir_rel = heir.rel_timelock;
    let heir_threshold = heir.threshold as u32;
    let heir_mfps = heir.mfps.clone();
    let heir_policy = APIPolicyPath::from_spendpath(heir)?;

    let tip = wallet.get_tip_height()?;
    let delta: u32 = 144; // ~1 day
    let info = wallet.create_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 500_000,
            op_return_data: None,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        heir_policy,
        heir_id,
        heir_threshold,
        heir_mfps,
        Some(delta),
    )?;

    // Absolute nLockTime: spend path has no abs_timelock, so it's purely tip + delta.
    assert_eq!(info.lock_time, tip + delta);

    // The CSV sequence imposed by the spend path must survive on the input:
    // bit 31 clear (so OP_CSV is enforced), encoded value == rel_timelock, and
    // strictly less than MAX (otherwise consensus would ignore nLockTime).
    let psbt = crate::api::wallet::psbt::psbt_from_base64(&info.psbt_base64)?;
    let seq = psbt.unsigned_tx.input[0].sequence.to_consensus_u32();
    assert_eq!(seq >> 31, 0, "CSV bit 31 must be clear");
    assert_eq!(
        seq & 0x0000_FFFF,
        heir_rel & 0x0000_FFFF,
        "nSequence must encode the spend path's relative timelock"
    );
    assert!(
        seq < u32::MAX,
        "nSequence must be < MAX so the forced nLockTime is enforced"
    );
    Ok(())
}

/// Regression for the BB02 batch-sign failure in spaced TX planning: when the
/// chosen spend path declares `older(N)`, every internal input of the resulting
/// PSBT must carry `nSequence == N` exactly — not just a value that happens to
/// satisfy BIP68 at mempool level (e.g. the real UTXO age). Strict HW signers
/// validate the tx against the registered policy and reject any other value.
///
/// Covers the path with `delta = None`, which used to short-circuit the fixup
/// when no foreign inputs were present.
#[test]
fn test_create_psbt_forces_canonical_nsequence_for_rel_timelock() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);
    let recv = recv_addr_for(&wallet);

    let analyzer = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let paths = analyzer.spend_paths()?;
    let heir = paths
        .iter()
        .filter(|sp| sp.rel_timelock > 0 && sp.abs_timelock == 0)
        .min_by_key(|sp| sp.rel_timelock)
        .expect("descriptor must expose at least one relative-timelock heir path");

    let info = wallet.create_psbt(
        vec![APIRecipient {
            address: recv,
            amount_sat: 500_000,
            op_return_data: None,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(heir)?,
        heir.id,
        heir.threshold as u32,
        heir.mfps.clone(),
        None,
    )?;

    let psbt = crate::api::wallet::psbt::psbt_from_base64(&info.psbt_base64)?;
    for (i, txin) in psbt.unsigned_tx.input.iter().enumerate() {
        assert_eq!(
            txin.sequence.to_consensus_u32(),
            heir.rel_timelock,
            "input {i}: nSequence must equal the spend path's rel_timelock exactly"
        );
    }
    Ok(())
}
