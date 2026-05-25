// Persistence for spaced-TX plans (feature/future-tx-planning).
//
// A `tx_plans` row groups N future-dated PSBTs (rows in `unsigned_txs`
// with `auto_broadcast = 1`) that together migrate or refresh a wallet
// over time. Each child PSBT carries its own `nLockTime`; broadcast
// happens automatically through the existing
// `try_auto_broadcast_due` pipeline.

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};

use super::labels::ensure_column;

// ---------------------------------------------------------------------------
// Row + enum types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TxPlanKind {
    Migrate,
    Refresh,
}

impl TxPlanKind {
    pub fn as_str(self) -> &'static str {
        match self {
            TxPlanKind::Migrate => "MIGRATE",
            TxPlanKind::Refresh => "REFRESH",
        }
    }

    pub fn parse(s: &str) -> Result<Self> {
        match s {
            "MIGRATE" => Ok(TxPlanKind::Migrate),
            "REFRESH" => Ok(TxPlanKind::Refresh),
            other => Err(anyhow!("unknown tx_plans.kind value: {other}")),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TxPlanStatus {
    Draft,
    Signed,
    Running,
    Done,
    Cancelled,
    Failed,
}

impl TxPlanStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            TxPlanStatus::Draft => "DRAFT",
            TxPlanStatus::Signed => "SIGNED",
            TxPlanStatus::Running => "RUNNING",
            TxPlanStatus::Done => "DONE",
            TxPlanStatus::Cancelled => "CANCELLED",
            TxPlanStatus::Failed => "FAILED",
        }
    }

    pub fn parse(s: &str) -> Result<Self> {
        match s {
            "DRAFT" => Ok(TxPlanStatus::Draft),
            "SIGNED" => Ok(TxPlanStatus::Signed),
            "RUNNING" => Ok(TxPlanStatus::Running),
            "DONE" => Ok(TxPlanStatus::Done),
            "CANCELLED" => Ok(TxPlanStatus::Cancelled),
            "FAILED" => Ok(TxPlanStatus::Failed),
            other => Err(anyhow!("unknown tx_plans.status value: {other}")),
        }
    }

    /// True for states that hold UTXOs earmarked from the source wallet's
    /// spendable balance (any state where child PSBTs may still broadcast).
    pub fn is_active(self) -> bool {
        matches!(
            self,
            TxPlanStatus::Draft | TxPlanStatus::Signed | TxPlanStatus::Running
        )
    }
}

#[derive(Debug, Clone)]
pub struct TxPlanRow {
    pub id: i64,
    pub kind: TxPlanKind,
    pub dst_wallet_path: String,
    pub spend_path_id: u32,
    pub feerate_min_msatvb: u64,
    pub feerate_max_msatvb: u64,
    pub delay_blocks_min: u32,
    pub delay_blocks_max: u32,
    pub split_probability: f64,
    pub min_split_output: u64,
    pub status: TxPlanStatus,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone)]
pub struct NewTxPlan {
    pub kind: TxPlanKind,
    pub dst_wallet_path: String,
    pub spend_path_id: u32,
    pub feerate_min_msatvb: u64,
    pub feerate_max_msatvb: u64,
    pub delay_blocks_min: u32,
    pub delay_blocks_max: u32,
    pub split_probability: f64,
    pub min_split_output: u64,
}

pub fn ensure_tx_plans_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS tx_plans (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            kind                TEXT NOT NULL,
            dst_wallet_path     TEXT NOT NULL,
            spend_path_id       INTEGER NOT NULL,
            feerate_min_msatvb  INTEGER NOT NULL,
            feerate_max_msatvb  INTEGER NOT NULL,
            delay_blocks_min    INTEGER NOT NULL,
            delay_blocks_max    INTEGER NOT NULL,
            split_probability   REAL    NOT NULL,
            min_split_output    INTEGER NOT NULL,
            status              TEXT NOT NULL,
            created_at          INTEGER NOT NULL,
            updated_at          INTEGER NOT NULL
        );",
    )?;
    // The `unsigned_txs` table is created elsewhere; this column ties each
    // child PSBT back to its plan. NULL = standalone PSBT (not part of a
    // plan). Cascade behaviour on plan cancel is enforced application-side
    // (we DELETE FROM unsigned_txs WHERE plan_id = ?) rather than via FK,
    // to stay consistent with the rest of the schema's no-FK style.
    ensure_column(conn, "unsigned_txs", "plan_id", "INTEGER")?;
    conn.execute_batch(
        "CREATE INDEX IF NOT EXISTS idx_unsigned_txs_plan_id
         ON unsigned_txs(plan_id);",
    )?;
    Ok(())
}

// ---------------------------------------------------------------------------
// CRUD
// ---------------------------------------------------------------------------

const PLAN_COLS: &str = "id, kind, dst_wallet_path, spend_path_id, \
     feerate_min_msatvb, feerate_max_msatvb, \
     delay_blocks_min, delay_blocks_max, \
     split_probability, min_split_output, \
     status, created_at, updated_at";

fn row_from_sql(row: &rusqlite::Row<'_>) -> rusqlite::Result<TxPlanRow> {
    let kind_s: String = row.get(1)?;
    let status_s: String = row.get(10)?;
    Ok(TxPlanRow {
        id: row.get(0)?,
        kind: TxPlanKind::parse(&kind_s).map_err(|e| {
            rusqlite::Error::FromSqlConversionFailure(1, rusqlite::types::Type::Text, e.into())
        })?,
        dst_wallet_path: row.get(2)?,
        spend_path_id: row.get::<_, i64>(3)? as u32,
        feerate_min_msatvb: row.get::<_, i64>(4)? as u64,
        feerate_max_msatvb: row.get::<_, i64>(5)? as u64,
        delay_blocks_min: row.get::<_, i64>(6)? as u32,
        delay_blocks_max: row.get::<_, i64>(7)? as u32,
        split_probability: row.get(8)?,
        min_split_output: row.get::<_, i64>(9)? as u64,
        status: TxPlanStatus::parse(&status_s).map_err(|e| {
            rusqlite::Error::FromSqlConversionFailure(10, rusqlite::types::Type::Text, e.into())
        })?,
        created_at: row.get(11)?,
        updated_at: row.get(12)?,
    })
}

fn now_secs() -> Result<i64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64)
}

/// Insert a new plan in `DRAFT` status. Returns the new row's id.
pub fn insert_tx_plan(conn: &Connection, plan: &NewTxPlan) -> Result<i64> {
    if plan.feerate_min_msatvb > plan.feerate_max_msatvb {
        return Err(anyhow!("feerate_min_msatvb > feerate_max_msatvb"));
    }
    if plan.delay_blocks_min > plan.delay_blocks_max {
        return Err(anyhow!("delay_blocks_min > delay_blocks_max"));
    }
    if !(0.0..=1.0).contains(&plan.split_probability) {
        return Err(anyhow!("split_probability must be in [0, 1]"));
    }
    let now = now_secs()?;
    conn.execute(
        "INSERT INTO tx_plans
         (kind, dst_wallet_path, spend_path_id,
          feerate_min_msatvb, feerate_max_msatvb,
          delay_blocks_min, delay_blocks_max,
          split_probability, min_split_output,
          status, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'DRAFT', ?10, ?10)",
        params![
            plan.kind.as_str(),
            plan.dst_wallet_path,
            plan.spend_path_id as i64,
            plan.feerate_min_msatvb as i64,
            plan.feerate_max_msatvb as i64,
            plan.delay_blocks_min as i64,
            plan.delay_blocks_max as i64,
            plan.split_probability,
            plan.min_split_output as i64,
            now,
        ],
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn get_tx_plan(conn: &Connection, id: i64) -> Result<Option<TxPlanRow>> {
    let row = conn
        .query_row(
            &format!("SELECT {PLAN_COLS} FROM tx_plans WHERE id = ?1"),
            [id],
            row_from_sql,
        )
        .optional()?;
    Ok(row)
}

pub fn list_tx_plans(conn: &Connection) -> Result<Vec<TxPlanRow>> {
    let mut stmt = conn.prepare(&format!(
        "SELECT {PLAN_COLS} FROM tx_plans ORDER BY created_at DESC, id DESC"
    ))?;
    let rows = stmt
        .query_map([], row_from_sql)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

/// Returns the single active plan (DRAFT/SIGNED/RUNNING) if any.
///
/// Enforces the §3 invariant of "one active plan per source wallet"; callers
/// must check this before creating a new plan. If two ever appear (data
/// corruption), the most recently updated one wins.
pub fn active_tx_plan(conn: &Connection) -> Result<Option<TxPlanRow>> {
    let row = conn
        .query_row(
            &format!(
                "SELECT {PLAN_COLS} FROM tx_plans
                 WHERE status IN ('DRAFT','SIGNED','RUNNING')
                 ORDER BY updated_at DESC, id DESC
                 LIMIT 1"
            ),
            [],
            row_from_sql,
        )
        .optional()?;
    Ok(row)
}

pub fn has_active_tx_plan(conn: &Connection) -> Result<bool> {
    Ok(active_tx_plan(conn)?.is_some())
}

/// Sweep any active plan whose children have all been auto-broadcast (i.e. no
/// remaining `unsigned_txs` rows for that `plan_id`) and flip it to `Done`.
///
/// Idempotent. Used as a self-heal on every read path that routes the UI so
/// wallets that crossed a broken release survive without manual SQL surgery.
pub fn reconcile_completed_tx_plans(conn: &Connection) -> Result<()> {
    let mut stmt = conn.prepare(
        "SELECT p.id FROM tx_plans p
         WHERE p.status IN ('DRAFT','SIGNED','RUNNING')
           AND NOT EXISTS (
                 SELECT 1 FROM unsigned_txs u WHERE u.plan_id = p.id
             )",
    )?;
    let ids = stmt
        .query_map([], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    for id in ids {
        set_tx_plan_status(conn, id, TxPlanStatus::Done)?;
    }
    Ok(())
}

pub fn set_tx_plan_status(conn: &Connection, id: i64, status: TxPlanStatus) -> Result<()> {
    let now = now_secs()?;
    let changed = conn.execute(
        "UPDATE tx_plans SET status = ?1, updated_at = ?2 WHERE id = ?3",
        params![status.as_str(), now, id],
    )?;
    if changed == 0 {
        return Err(anyhow!("tx_plans row {id} not found"));
    }
    Ok(())
}

/// Cascade-delete a plan and every child PSBT linked to it.
///
/// Used by the cancel-and-discard flow. Earmarks (derived from child rows)
/// vanish automatically.
pub fn delete_tx_plan(conn: &Connection, id: i64) -> Result<()> {
    conn.execute("DELETE FROM unsigned_txs WHERE plan_id = ?1", [id])?;
    let changed = conn.execute("DELETE FROM tx_plans WHERE id = ?1", [id])?;
    if changed == 0 {
        return Err(anyhow!("tx_plans row {id} not found"));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Plan ↔ PSBT linking
// ---------------------------------------------------------------------------

pub fn set_unsigned_tx_plan_id(
    conn: &Connection,
    unsigned_tx_id: i64,
    plan_id: Option<i64>,
) -> Result<()> {
    let changed = conn.execute(
        "UPDATE unsigned_txs SET plan_id = ?1 WHERE id = ?2",
        params![plan_id, unsigned_tx_id],
    )?;
    if changed == 0 {
        return Err(anyhow!("unsigned_txs row {unsigned_tx_id} not found"));
    }
    Ok(())
}

pub fn list_unsigned_tx_ids_for_plan(conn: &Connection, plan_id: i64) -> Result<Vec<i64>> {
    let mut stmt = conn.prepare(
        "SELECT id FROM unsigned_txs WHERE plan_id = ?1 ORDER BY created_at ASC, id ASC",
    )?;
    let ids = stmt
        .query_map([plan_id], |r| r.get::<_, i64>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(ids)
}

#[cfg(test)]
#[path = "tx_plan_storage_tests.rs"]
mod tests;
