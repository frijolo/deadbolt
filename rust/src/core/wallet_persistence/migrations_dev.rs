// DEV ZONE — REMOVE BEFORE MERGE TO MASTER
//
// Idempotent schema changes for the in-progress `feature/future-tx-planning`
// branch. Runs on every wallet open so we can iterate on the schema without
// bumping `WALLET_SCHEMA_VERSION` for each change.
//
// Rules:
//   - Every statement here MUST be safe to re-run (CREATE IF NOT EXISTS,
//     `ensure_column`, etc.).
//   - No destructive operations (DROP TABLE, DROP COLUMN with data) without
//     an explicit, documented wipe.
//   - Before merging the feature, collapse the body of `apply_dev_schema`
//     into a numbered `migrate_v1_to_v2` and bump `WALLET_SCHEMA_VERSION`.

use anyhow::Result;
use rusqlite::Connection;

pub fn apply_dev_schema(conn: &Connection) -> Result<()> {
    // future-tx-planning: auto-broadcast flag for time-locked PSBTs.
    // Ensure the table exists first so the ALTER below succeeds on freshly
    // created wallets (where `ensure_unsigned_txs_table` would otherwise only
    // run lazily on first PSBT use).
    super::psbt_storage::ensure_unsigned_txs_table(conn)?;
    super::labels::ensure_column(
        conn,
        "unsigned_txs",
        "auto_broadcast",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    // future-tx-planning: spaced TX plans. Adds `tx_plans` table plus the
    // `plan_id` column on `unsigned_txs` linking each child PSBT to its plan.
    super::tx_plan_storage::ensure_tx_plans_table(conn)?;
    Ok(())
}

#[cfg(test)]
#[path = "migrations_dev_tests.rs"]
mod tests;
