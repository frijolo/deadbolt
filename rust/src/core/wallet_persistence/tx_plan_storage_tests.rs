use super::*;
use crate::core::wallet_persistence::migrations::run_wallet_migrations;
use crate::core::wallet_persistence::open_encrypted_connection;
use crate::test_support::KEY_HEX;
use std::collections::HashSet;
use tempfile::tempdir;

fn open_test_db() -> (Connection, tempfile::TempDir) {
    let dir = tempdir().unwrap();
    let path = dir.path().join("test.db").to_string_lossy().to_string();
    let conn = open_encrypted_connection(&path, KEY_HEX).unwrap();
    (conn, dir)
}

fn column_set(conn: &Connection, table: &str) -> HashSet<String> {
    conn.prepare(&format!("PRAGMA table_info({table})"))
        .unwrap()
        .query_map([], |r| r.get::<_, String>(1))
        .unwrap()
        .filter_map(|r| r.ok())
        .collect()
}

fn table_exists(conn: &Connection, name: &str) -> bool {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1",
        [name],
        |_| Ok(()),
    )
    .is_ok()
}

#[test]
fn migrations_create_tx_plans_table() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    assert!(table_exists(&conn, "tx_plans"));
    let cols = column_set(&conn, "tx_plans");
    for expected in [
        "id",
        "kind",
        "dst_wallet_path",
        "spend_path_id",
        "feerate_min_msatvb",
        "feerate_max_msatvb",
        "delay_blocks_min",
        "delay_blocks_max",
        "split_probability",
        "min_split_output",
        "status",
        "created_at",
        "updated_at",
    ] {
        assert!(cols.contains(expected), "missing column: {expected}");
    }
    Ok(())
}

#[test]
fn migrations_add_plan_id_to_unsigned_txs() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    assert!(column_set(&conn, "unsigned_txs").contains("plan_id"));
    Ok(())
}

#[test]
fn migrations_run_twice_safely() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    run_wallet_migrations(&conn)?;
    assert!(table_exists(&conn, "tx_plans"));
    assert!(column_set(&conn, "unsigned_txs").contains("plan_id"));
    Ok(())
}

#[test]
fn existing_psbt_rows_get_null_plan_id() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    conn.execute(
        "INSERT INTO unsigned_txs
         (psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
          spend_path_id, threshold, mfps, recipients_json)
         VALUES ('psbt', 'tx', NULL, 1700000000, 'r', 1, 1, 0, 1, '', NULL)",
        [],
    )?;
    run_wallet_migrations(&conn)?;
    let plan_id: Option<i64> =
        conn.query_row("SELECT plan_id FROM unsigned_txs LIMIT 1", [], |r| r.get(0))?;
    assert_eq!(plan_id, None);
    Ok(())
}

// ---------------------------------------------------------------------------
// CRUD helpers
// ---------------------------------------------------------------------------

fn sample_plan() -> NewTxPlan {
    NewTxPlan {
        kind: TxPlanKind::Migrate,
        dst_wallet_path: "/tmp/dst.db".into(),
        spend_path_id: 0,
        feerate_min_msatvb: 2_000,
        feerate_max_msatvb: 8_000,
        delay_blocks_min: 1,
        delay_blocks_max: 100,
        split_probability: 0.5,
        min_split_output: 100_000,
    }
}

fn insert_child_psbt(conn: &Connection, plan_id: Option<i64>) -> Result<i64> {
    conn.execute(
        "INSERT INTO unsigned_txs
         (psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
          spend_path_id, threshold, mfps, recipients_json, plan_id)
         VALUES ('psbt', 'tx', NULL, 1700000000, 'r', 1, 1, 0, 1, '', NULL, ?1)",
        [plan_id],
    )?;
    Ok(conn.last_insert_rowid())
}

#[test]
fn insert_get_and_list_roundtrip() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let id = insert_tx_plan(&conn, &sample_plan())?;
    let fetched = get_tx_plan(&conn, id)?.expect("plan present");
    assert_eq!(fetched.id, id);
    assert_eq!(fetched.kind, TxPlanKind::Migrate);
    assert_eq!(fetched.dst_wallet_path, "/tmp/dst.db");
    assert_eq!(fetched.status, TxPlanStatus::Draft);
    assert_eq!(fetched.feerate_min_msatvb, 2_000);
    assert_eq!(fetched.feerate_max_msatvb, 8_000);
    assert_eq!(fetched.split_probability, 0.5);
    let list = list_tx_plans(&conn)?;
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].id, id);
    Ok(())
}

#[test]
fn insert_rejects_invalid_ranges() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;

    let mut bad = sample_plan();
    bad.feerate_min_msatvb = 9_000;
    bad.feerate_max_msatvb = 8_000;
    assert!(insert_tx_plan(&conn, &bad).is_err());

    let mut bad = sample_plan();
    bad.delay_blocks_min = 200;
    bad.delay_blocks_max = 100;
    assert!(insert_tx_plan(&conn, &bad).is_err());

    let mut bad = sample_plan();
    bad.split_probability = 1.5;
    assert!(insert_tx_plan(&conn, &bad).is_err());

    Ok(())
}

#[test]
fn status_transitions_and_timestamps() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let id = insert_tx_plan(&conn, &sample_plan())?;
    let before = get_tx_plan(&conn, id)?.unwrap();
    // sleep would be flaky; just assert updated_at >= created_at across
    // the update and that the status changed.
    set_tx_plan_status(&conn, id, TxPlanStatus::Signed)?;
    let after = get_tx_plan(&conn, id)?.unwrap();
    assert_eq!(after.status, TxPlanStatus::Signed);
    assert!(after.updated_at >= before.updated_at);
    Ok(())
}

#[test]
fn set_status_unknown_id_errors() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    assert!(set_tx_plan_status(&conn, 999, TxPlanStatus::Done).is_err());
    Ok(())
}

#[test]
fn active_tx_plan_filters_terminal_states() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let id = insert_tx_plan(&conn, &sample_plan())?;

    assert!(has_active_tx_plan(&conn)?);
    set_tx_plan_status(&conn, id, TxPlanStatus::Signed)?;
    assert!(has_active_tx_plan(&conn)?);
    set_tx_plan_status(&conn, id, TxPlanStatus::Running)?;
    assert!(has_active_tx_plan(&conn)?);

    for terminal in [
        TxPlanStatus::Done,
        TxPlanStatus::Cancelled,
        TxPlanStatus::Failed,
    ] {
        set_tx_plan_status(&conn, id, terminal)?;
        assert!(
            !has_active_tx_plan(&conn)?,
            "{:?} should not be active",
            terminal
        );
    }
    Ok(())
}

#[test]
fn active_tx_plan_ignores_terminal_rows() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let cancelled = insert_tx_plan(&conn, &sample_plan())?;
    set_tx_plan_status(&conn, cancelled, TxPlanStatus::Cancelled)?;
    let active = insert_tx_plan(&conn, &sample_plan())?;

    let picked = active_tx_plan(&conn)?.expect("an active plan exists");
    assert_eq!(picked.id, active);
    assert!(picked.status.is_active());
    Ok(())
}

#[test]
fn delete_cascades_child_psbts() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let plan_id = insert_tx_plan(&conn, &sample_plan())?;
    let _c1 = insert_child_psbt(&conn, Some(plan_id))?;
    let _c2 = insert_child_psbt(&conn, Some(plan_id))?;
    let orphan = insert_child_psbt(&conn, None)?;

    delete_tx_plan(&conn, plan_id)?;

    assert!(get_tx_plan(&conn, plan_id)?.is_none());
    let remaining: i64 = conn.query_row(
        "SELECT COUNT(*) FROM unsigned_txs WHERE plan_id = ?1",
        [plan_id],
        |r| r.get(0),
    )?;
    assert_eq!(remaining, 0);
    // Orphan PSBT must survive — proves we only cascade children of this plan.
    let orphan_alive: i64 = conn.query_row(
        "SELECT COUNT(*) FROM unsigned_txs WHERE id = ?1",
        [orphan],
        |r| r.get(0),
    )?;
    assert_eq!(orphan_alive, 1);
    Ok(())
}

#[test]
fn delete_unknown_id_errors() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    assert!(delete_tx_plan(&conn, 999).is_err());
    Ok(())
}

#[test]
fn set_and_list_unsigned_tx_links() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let plan_id = insert_tx_plan(&conn, &sample_plan())?;
    let a = insert_child_psbt(&conn, None)?;
    let b = insert_child_psbt(&conn, None)?;

    set_unsigned_tx_plan_id(&conn, a, Some(plan_id))?;
    set_unsigned_tx_plan_id(&conn, b, Some(plan_id))?;
    let ids = list_unsigned_tx_ids_for_plan(&conn, plan_id)?;
    assert_eq!(ids, vec![a, b]);

    // Unlinking sets it back to NULL and the plan listing shrinks.
    set_unsigned_tx_plan_id(&conn, a, None)?;
    let ids = list_unsigned_tx_ids_for_plan(&conn, plan_id)?;
    assert_eq!(ids, vec![b]);
    Ok(())
}

#[test]
fn set_unsigned_tx_plan_id_unknown_errors() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    let plan_id = insert_tx_plan(&conn, &sample_plan())?;
    assert!(set_unsigned_tx_plan_id(&conn, 999, Some(plan_id)).is_err());
    Ok(())
}

#[test]
fn kind_and_status_parse_round_trip() -> Result<()> {
    for k in [TxPlanKind::Migrate, TxPlanKind::Refresh] {
        assert_eq!(TxPlanKind::parse(k.as_str())?, k);
    }
    for s in [
        TxPlanStatus::Draft,
        TxPlanStatus::Signed,
        TxPlanStatus::Running,
        TxPlanStatus::Done,
        TxPlanStatus::Cancelled,
        TxPlanStatus::Failed,
    ] {
        assert_eq!(TxPlanStatus::parse(s.as_str())?, s);
    }
    assert!(TxPlanKind::parse("nope").is_err());
    assert!(TxPlanStatus::parse("nope").is_err());
    Ok(())
}

// ---------------------------------------------------------------------------
// Step 1 — raw schema (kept for regression).
// ---------------------------------------------------------------------------

#[test]
fn plan_id_can_be_set_and_queried() -> Result<()> {
    let (conn, _dir) = open_test_db();
    run_wallet_migrations(&conn)?;
    conn.execute(
        "INSERT INTO tx_plans
         (kind, dst_wallet_path, spend_path_id,
          feerate_min_msatvb, feerate_max_msatvb,
          delay_blocks_min, delay_blocks_max,
          split_probability, min_split_output,
          status, created_at, updated_at)
         VALUES ('MIGRATE', '/tmp/dst.db', 0,
                 2000, 8000,
                 1, 100,
                 0.5, 100000,
                 'DRAFT', 1700000000, 1700000000)",
        [],
    )?;
    let plan_id = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO unsigned_txs
         (psbt, txid, label, created_at, recipient, amount_sat, fee_sat,
          spend_path_id, threshold, mfps, recipients_json, plan_id)
         VALUES ('psbt', 'tx', NULL, 1700000000, 'r', 1, 1, 0, 1, '', NULL, ?1)",
        [plan_id],
    )?;
    let stored: i64 =
        conn.query_row("SELECT plan_id FROM unsigned_txs LIMIT 1", [], |r| r.get(0))?;
    assert_eq!(stored, plan_id);
    Ok(())
}
