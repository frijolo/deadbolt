use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use bdk_wallet::rusqlite::Connection;
use bdk_wallet::{KeychainKind, PersistedWallet, Wallet};
use std::sync::Arc;

use crate::core::seed::{
    make_private_descriptor, root_xprv_to_mfp, seed_entry_to_root_xprv, split_multipath_descriptor,
    strip_descriptor_checksum,
};
use crate::core::wallet_persistence::{list_seed_entries, load_or_create_wallet};

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

    /// Re-key the SQLCipher database to a new encryption key.
    /// Runs `PRAGMA rekey` on the already-open connection — no need to close
    /// the wallet. After this call the on-disk file is re-encrypted with the
    /// new key; the current connection remains fully operational.
    pub fn rekey(&mut self, new_key_hex: &str) -> Result<()> {
        self.conn
            .execute_batch(&format!("PRAGMA rekey = \"x'{}'\"", new_key_hex))?;
        Ok(())
    }

    /// Load private-key signers from stored seed entries into the wallet's signer set.
    ///
    /// Clears any previously loaded signers first, then re-adds one signer per matching
    /// seed entry. Call this after opening the wallet and after any seed entry change.
    pub fn load_signers(&mut self, descriptor: &str, network: Network) -> Result<()> {
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        // `bdk_wallet::wallet::signer` was deprecated in BDK 2.2.0 ("PSBT signing moved to
        // bitcoin::psbt"), but `add_signer` / `get_signers` / `SignerOrdering` have no
        // drop-in replacement for runtime signer injection in BDK 2.3.0.  Remove once BDK
        // exposes a stable API for injecting custom signers into a persisted wallet.
        #[allow(deprecated)]
        use bdk_wallet::signer::SignerOrdering;

        // Clear existing signers for both keychains so refresh works correctly.
        self.wallet
            .set_keymap(KeychainKind::External, Default::default());
        self.wallet
            .set_keymap(KeychainKind::Internal, Default::default());

        let (seeds, _corrupt) = list_seed_entries(&self.conn)?;
        let secp = Secp256k1::new();

        for seed in &seeds {
            let root_xprv = seed_entry_to_root_xprv(
                &seed.seed_type,
                seed.mnemonic.as_deref(),
                &seed.passphrase,
                seed.xprv.as_deref(),
                network,
            )?;

            let mfp = root_xprv_to_mfp(&root_xprv, &secp);
            if !descriptor.contains(&mfp) {
                continue;
            }

            let private_desc = match make_private_descriptor(descriptor, &root_xprv, &secp) {
                Ok(d) => d,
                Err(e) => {
                    // Soft failure: skip this seed rather than aborting the whole load.
                    // Output to stderr (logcat on Android) until a proper log crate is wired up.
                    eprintln!("[load_signers] make_private_descriptor failed for mfp={mfp}: {e}");
                    continue;
                }
            };
            // Strip checksum — xpub→xprv replacement invalidates it.
            let private_desc = strip_descriptor_checksum(&private_desc);

            // Build a temporary wallet just to extract properly-contextualized signers.
            // The temp wallet is never used for signing — its sole purpose is to let BDK
            // create SignerWrapper instances with the correct SignerContext (Segwitv0, Tap, etc.)
            // based on the private descriptor.
            //
            // BDK cannot create a wallet from a multi-path descriptor that contains an xprv
            // (any `<n;m>` suffix with a private key trips a miniscript limitation). We split
            // the two-path descriptor into a standard external+internal pair first.
            let (ext_desc, int_desc) = split_multipath_descriptor(&private_desc);
            let temp = match Wallet::create(ext_desc, int_desc)
                .network(network)
                .create_wallet_no_persist()
            {
                Ok(w) => w,
                Err(e) => {
                    // Soft failure: skip this seed rather than aborting the whole load.
                    // Output to stderr (logcat on Android) until a proper log crate is wired up.
                    eprintln!("[load_signers] temp wallet creation failed for mfp={mfp}: {e}");
                    continue;
                }
            };

            // Copy signers into the main wallet (which has the synced address index).
            // `get_signers` / `add_signer` are deprecated alongside the signer module —
            // see comment above.
            for keychain in [KeychainKind::External, KeychainKind::Internal] {
                #[allow(deprecated)]
                for signer in temp.get_signers(keychain).signers() {
                    #[allow(deprecated)]
                    self.wallet
                        .add_signer(keychain, SignerOrdering(200), Arc::clone(signer));
                }
            }
        }

        Ok(())
    }
}

// ---------------------------------------------------------------------------
// BDK wallet query utilities (used by the API layer)
// ---------------------------------------------------------------------------

/// Compute the maximum confirmation height of the UTXOs spent by `psbt`.
/// Returns `None` if no input UTXO is confirmed.
pub fn psbt_max_utxo_conf_height(
    wallet: &bdk_wallet::Wallet,
    psbt: &bdk_wallet::bitcoin::psbt::Psbt,
) -> Option<i64> {
    // Build txid → confirmation_height for all wallet transactions.
    // This covers ghost UTXOs that BDK removed from list_unspent() because a
    // mempool tx is spending them — wallet.get_utxo() misses those.
    let tx_conf_heights: std::collections::HashMap<bdk_wallet::bitcoin::Txid, i64> = wallet
        .transactions()
        .filter_map(|t| {
            if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } = &t.chain_position {
                Some((t.tx_node.txid, anchor.block_id.height as i64))
            } else {
                None
            }
        })
        .collect();

    psbt.unsigned_tx
        .input
        .iter()
        .filter_map(|txin| {
            // Fast path: UTXO is still in BDK's unspent set (normal spend).
            if let Some(utxo) = wallet.get_utxo(txin.previous_output) {
                if let bdk_wallet::chain::ChainPosition::Confirmed { anchor, .. } =
                    utxo.chain_position
                {
                    return Some(anchor.block_id.height as i64);
                }
            }
            // Fallback: ghost UTXO (being spent in mempool for RBF).
            // Look up the confirmation height of the tx that created this output.
            tx_conf_heights.get(&txin.previous_output.txid).copied()
        })
        .reduce(i64::max)
}

/// True when `recipient` is one of this wallet's own addresses (self-transfer).
pub fn is_psbt_self_transfer(wallet: &bdk_wallet::Wallet, recipient: &str) -> bool {
    use bdk_wallet::bitcoin::Address;
    use std::str::FromStr;
    let Ok(addr) = Address::from_str(recipient) else {
        return false;
    };
    let Ok(addr) = addr.require_network(wallet.network()) else {
        return false;
    };
    wallet
        .spk_index()
        .index_of_spk(addr.script_pubkey())
        .is_some()
}

/// Build the set of outpoints that are still "live": either unspent or being
/// spent by an unconfirmed (mempool) wallet transaction.  Any PSBT input
/// absent from this set has been confirmed-spent by another transaction and
/// can no longer be broadcast.
pub fn build_valid_outpoints(
    wallet: &bdk_wallet::Wallet,
) -> std::collections::HashSet<bdk_wallet::bitcoin::OutPoint> {
    use bdk_wallet::chain::ChainPosition;
    let mut valid = std::collections::HashSet::new();
    for utxo in wallet.list_unspent() {
        valid.insert(utxo.outpoint);
    }
    for tx in wallet.transactions() {
        if matches!(tx.chain_position, ChainPosition::Unconfirmed { .. }) {
            for txin in &tx.tx_node.tx.input {
                if !txin.previous_output.is_null() {
                    valid.insert(txin.previous_output);
                }
            }
        }
    }
    valid
}

#[cfg(test)]
#[path = "wallet_tests.rs"]
mod tests;
