use anyhow::{anyhow, Result};
use rusqlite::Connection;

use crate::core::key_protection::{generate_data_key, unwrap_key, wrap_key, ProtectionMeta};
use crate::core::wallet_meta::{meta_exists, read_meta, write_meta};
use crate::core::wallet_persistence::{open_encrypted_connection, SeedEntry};

pub fn project_seeds_db_path(app_support_dir: &str) -> String {
    format!("{}/project_seeds.db", app_support_dir)
}

/// Open (or create) the shared project-seeds SQLCipher database.
///
/// On first run: generates a random data key, wraps it with the device key,
/// writes the sidecar `.meta` file, and creates the schema.
/// On subsequent runs: reads the sidecar, unwraps the data key, opens the DB.
pub fn open_project_seeds_db(app_support_dir: &str, device_key_hex: &str) -> Result<Connection> {
    let db_path = project_seeds_db_path(app_support_dir);

    let data_key = if meta_exists(&db_path) {
        let meta = read_meta(&db_path)?;
        match meta {
            ProtectionMeta::DeviceKey { wrapped_key, .. } => {
                unwrap_key(&wrapped_key, device_key_hex)?
            }
            _ => {
                return Err(anyhow!(
                    "project_seeds.db uses an unsupported protection type"
                ))
            }
        }
    } else {
        let data_key = generate_data_key();
        let wrapped = wrap_key(&data_key, device_key_hex)?;
        let meta = ProtectionMeta::DeviceKey {
            version: 1,
            wrapped_key: wrapped,
        };
        write_meta(&db_path, &meta)?;
        data_key
    };

    let conn = open_encrypted_connection(&db_path, &data_key)?;
    ensure_project_seed_entries_table(&conn)?;
    Ok(conn)
}

pub fn ensure_project_seed_entries_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS project_seed_entries (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id  INTEGER NOT NULL,
            mfp         TEXT NOT NULL,
            seed_type   TEXT NOT NULL,
            mnemonic    TEXT,
            passphrase  TEXT NOT NULL DEFAULT '',
            xprv        TEXT,
            created_at  INTEGER NOT NULL,
            UNIQUE(project_id, mfp)
        );",
    )?;
    Ok(())
}

pub fn insert_project_seed_entry(
    conn: &Connection,
    project_id: i64,
    mfp: &str,
    seed_type: &str,
    mnemonic: Option<&str>,
    passphrase: &str,
    xprv: Option<&str>,
) -> Result<i64> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as i64;
    conn.execute(
        "INSERT OR REPLACE INTO project_seed_entries
         (project_id, mfp, seed_type, mnemonic, passphrase, xprv, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![project_id, mfp, seed_type, mnemonic, passphrase, xprv, now],
    )?;
    Ok(now)
}

pub fn list_project_seed_entries(conn: &Connection, project_id: i64) -> Result<Vec<SeedEntry>> {
    let mut stmt = conn.prepare(
        "SELECT mfp, seed_type, mnemonic, passphrase, xprv, created_at
         FROM project_seed_entries WHERE project_id = ?1 ORDER BY created_at ASC",
    )?;
    let entries = stmt
        .query_map(rusqlite::params![project_id], |row| {
            Ok(SeedEntry {
                mfp: row.get(0)?,
                seed_type: row.get(1)?,
                mnemonic: row.get(2)?,
                passphrase: row.get::<_, Option<String>>(3)?.unwrap_or_default(),
                xprv: row.get(4)?,
                created_at: row.get(5)?,
            })
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(entries)
}

pub fn delete_project_seed_entry(conn: &Connection, project_id: i64, mfp: &str) -> Result<()> {
    let n = conn.execute(
        "DELETE FROM project_seed_entries WHERE project_id = ?1 AND mfp = ?2",
        rusqlite::params![project_id, mfp],
    )?;
    if n == 0 {
        return Err(anyhow!(
            "No signing key with MFP {} found for project {}",
            mfp,
            project_id
        ));
    }
    Ok(())
}

/// Returns the mnemonic phrase or xprv string stored for the given key.
/// The SQLCipher layer already protects this data at rest.
pub fn reveal_project_seed_value(conn: &Connection, project_id: i64, mfp: &str) -> Result<String> {
    let result: Result<(Option<String>, Option<String>), _> = conn.query_row(
        "SELECT mnemonic, xprv FROM project_seed_entries
         WHERE project_id = ?1 AND mfp = ?2",
        rusqlite::params![project_id, mfp],
        |row| Ok((row.get(0)?, row.get(1)?)),
    );
    let (mnemonic, xprv) = result.map_err(|_| {
        anyhow!(
            "No signing key with MFP {} found for project {}",
            mfp,
            project_id
        )
    })?;
    mnemonic
        .or(xprv)
        .ok_or_else(|| anyhow!("Signing key entry for MFP {} has no seed data", mfp))
}

#[cfg(test)]
#[path = "project_seeds_tests.rs"]
mod tests;
