use bdk_wallet::bitcoin::address::NetworkUnchecked;
use bdk_wallet::bitcoin::{Address, Amount, TxOut};

use crate::core::error::WalletError;

/// Returns the weight units (WU) of a transaction output sending to the given address.
///
/// The output weight is `4 * (8 + varint(script_len) + script_len)` because
/// all output data is non-witness. Network validation is skipped so any
/// mainnet/testnet/signet/regtest address is accepted.
pub fn address_output_wu(address: &str) -> Result<u64, WalletError> {
    let addr = address
        .parse::<Address<NetworkUnchecked>>()
        .map_err(|e| WalletError::InvalidAddress(e.to_string()))?
        .assume_checked();
    let txout = TxOut {
        value: Amount::ZERO,
        script_pubkey: addr.script_pubkey(),
    };
    Ok(txout.weight().to_wu())
}

#[cfg(test)]
#[path = "address_tests.rs"]
mod tests;
