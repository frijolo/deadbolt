use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use bdk_wallet::rusqlite::Connection;
use bdk_wallet::PersistedWallet;

use crate::core::wallet_persistence::load_or_create_wallet;

#[derive(Debug, Clone, PartialEq)]
pub enum WalletType {
    P2PKH,
    P2WPKH,
    P2SH,
    P2WSH,
    P2TR,
    #[allow(non_camel_case_types)]
    P2SH_WPKH,
    #[allow(non_camel_case_types)]
    P2SH_WSH,
    Unknown,
}

/// Live wallet handle: open once, reuse across multiple operations.
pub struct CoreWallet {
    pub wallet: PersistedWallet<Connection>,
    pub conn: Connection,
}

impl CoreWallet {
    /// Open (or create) the encrypted BDK wallet at `path`.
    pub fn open(path: &str, descriptor: &str, network: Network, key_hex: &str) -> Result<Self> {
        let (wallet, conn) = load_or_create_wallet(path, descriptor, network, key_hex)?;
        Ok(Self { wallet, conn })
    }

    /// Persist any pending wallet state to the SQLite file.
    pub fn persist(&mut self) -> Result<bool> {
        Ok(self.wallet.persist(&mut self.conn)?)
    }
}
