use anyhow::Result;
use rusqlite::Connection;
use std::collections::HashSet;

use super::descriptor_sig_storage::ensure_descriptor_sigs_table;
use super::fiat_storage::ensure_fiat_prices_table;
use super::labels::{
    ensure_address_labels_table, ensure_coin_labels_table, ensure_column, ensure_key_labels_table,
    ensure_path_labels_table, ensure_tx_labels_table,
};
use super::psbt_storage::ensure_unsigned_txs_table;
use super::seed_storage::ensure_seed_entries_table;
use super::tx_plan_storage::ensure_tx_plans_table;

/// Current target schema version for wallet databases.
/// Bump this constant and add a new migration step whenever the schema changes.
pub const WALLET_SCHEMA_VERSION: u32 = 2;

/// Run all pending schema migrations for a wallet database.
///
/// Uses `PRAGMA user_version` to track which migrations have already been applied.
/// All existing wallets start at version 0 (the pragma was never set before). New wallets
/// also start at 0 and go through the same migrations on first open.
///
/// After all migrations run, `user_version` is set to `WALLET_SCHEMA_VERSION` so
/// subsequent opens are a single PRAGMA read and immediate return.
pub fn run_wallet_migrations(conn: &Connection) -> Result<()> {
    let from = get_schema_version(conn)?;
    if from < WALLET_SCHEMA_VERSION {
        if from < 1 {
            migrate_v0_to_v1(conn)?;
        }
        if from < 2 {
            migrate_v1_to_v2(conn)?;
        }
    }
    Ok(())
}

fn get_schema_version(conn: &Connection) -> Result<u32> {
    Ok(conn.query_row("PRAGMA user_version", [], |row| row.get(0))?)
}

fn set_schema_version(conn: &Connection, version: u32) -> Result<()> {
    // user_version cannot be set with a bound parameter — format is required.
    conn.execute_batch(&format!("PRAGMA user_version = {version}"))?;
    Ok(())
}

/// Migration v0 → v1: introduce schema versioning.
///
/// - Creates all feature tables that may be absent in older wallet databases (idempotent).
/// - Fixes `descriptor_sigs` if it was created with an incompatible schema from a
///   provisional install that never shipped to production users.
fn migrate_v0_to_v1(conn: &Connection) -> Result<()> {
    ensure_tx_labels_table(conn)?;
    ensure_address_labels_table(conn)?;
    ensure_key_labels_table(conn)?;
    ensure_path_labels_table(conn)?;
    ensure_coin_labels_table(conn)?;
    ensure_seed_entries_table(conn)?;
    ensure_fiat_prices_table(conn)?;
    fix_descriptor_sigs_if_needed(conn)?;
    set_schema_version(conn, 1)?;
    Ok(())
}

/// Migration v1 → v2: spaced transaction planning.
///
/// - Ensures `unsigned_txs` exists (older v1 wallets only created it lazily on
///   first PSBT use; v2 needs it as the anchor for the new columns).
/// - Adds `unsigned_txs.auto_broadcast` — flag set on PSBTs the scheduler is
///   allowed to broadcast once their nLockTime matures.
/// - Adds `tx_plans` table + the `unsigned_txs.plan_id` column linking each
///   child PSBT to its parent spaced plan.
fn migrate_v1_to_v2(conn: &Connection) -> Result<()> {
    ensure_unsigned_txs_table(conn)?;
    ensure_column(
        conn,
        "unsigned_txs",
        "auto_broadcast",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    ensure_tx_plans_table(conn)?;
    set_schema_version(conn, 2)?;
    Ok(())
}

/// Ensures `descriptor_sigs` has the correct v1 schema.
///
/// Three cases:
/// - Table is absent → create it from scratch (normal path for wallets predating the feature).
/// - Table exists with all required columns → nothing to do (data is preserved).
/// - Table exists but is missing a required column → provisional install with incompatible
///   schema; drop and recreate (data in that table is expendable since it was never
///   deployed to production users).
fn fix_descriptor_sigs_if_needed(conn: &Connection) -> Result<()> {
    // PRAGMA table_info returns an empty result set for non-existent tables,
    // so a single call handles both the existence check and column inspection.
    let mut stmt = conn.prepare("PRAGMA table_info(descriptor_sigs)")?;
    let existing: HashSet<String> = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .filter_map(|r| r.ok())
        .collect();

    if existing.is_empty() {
        return ensure_descriptor_sigs_table(conn);
    }

    // Columns present in the original v1 schema — this list must never be extended.
    // Future columns are handled by ALTER TABLE ADD COLUMN in later migrations.
    let required: &[&str] = &[
        "id",
        "mfp",
        "xpub_entry",
        "sig_method",
        "sig_hex",
        "signed_at",
    ];
    if required.iter().all(|col| existing.contains(*col)) {
        return Ok(()); // schema is correct — preserve existing data
    }

    // Schema mismatch from a provisional install — drop and recreate.
    conn.execute_batch("DROP TABLE descriptor_sigs;")?;
    ensure_descriptor_sigs_table(conn)
}

#[cfg(test)]
#[path = "migrations_tests.rs"]
mod tests;
