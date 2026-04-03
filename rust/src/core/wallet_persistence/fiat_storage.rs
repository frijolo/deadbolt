use anyhow::Result;
use rusqlite::Connection;

/// Create the fiat_prices table if it does not already exist.
pub fn ensure_fiat_prices_table(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS fiat_prices (
            txid     TEXT NOT NULL,
            currency TEXT NOT NULL,
            price    REAL NOT NULL,
            PRIMARY KEY (txid, currency)
        );",
    )?;
    Ok(())
}

/// Store (or replace) the BTC price in `currency` at the time of a transaction.
pub fn store_fiat_price(conn: &Connection, txid: &str, currency: &str, price: f64) -> Result<()> {
    conn.execute(
        "INSERT OR REPLACE INTO fiat_prices (txid, currency, price) VALUES (?1, ?2, ?3)",
        rusqlite::params![txid, currency, price],
    )?;
    Ok(())
}

/// Return all stored prices for the given currency as a `Vec<(txid, price)>`.
pub fn get_fiat_prices(conn: &Connection, currency: &str) -> Result<Vec<(String, f64)>> {
    let mut stmt = conn.prepare("SELECT txid, price FROM fiat_prices WHERE currency = ?1")?;
    let rows = stmt
        .query_map(rusqlite::params![currency], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, f64>(1)?))
        })?
        .filter_map(|r| r.ok())
        .collect();
    Ok(rows)
}

/// Remove all stored fiat prices.
pub fn clear_fiat_prices(conn: &Connection) -> Result<()> {
    conn.execute("DELETE FROM fiat_prices", [])?;
    Ok(())
}
