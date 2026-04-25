use std::str::FromStr;

use bdk_wallet::bitcoin::address::NetworkUnchecked;
use bdk_wallet::bitcoin::{Address, Amount, TxOut};

use crate::core::error::WalletError;

/// Parse and validate an address string, requiring [net].
///
/// Returns an error if the string is not a valid address or if the address
/// network does not match [net]. Callers may wrap the returned error in a
/// context-specific message via `anyhow::anyhow!("{msg}: {e}")`.
pub fn parse_address(address: &str, net: bdk_wallet::bitcoin::Network) -> anyhow::Result<Address> {
    let addr = Address::from_str(address).map_err(|e| anyhow::anyhow!("{e}"))?;
    addr.require_network(net)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

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
