//! Shared test fixtures for Deadbolt wallet tests.
//!
//! This module centralises constants and helpers that are duplicated across
//! `*_tests.rs` files, preventing drift when descriptors or keys need updating.
//!
//! Usage in a test file:
//! ```ignore
//! use crate::test_support::{MAINNET_DESC, KEY_HEX, make_wallet, inject_utxo, APIWallet};
//! ```

use anyhow::Result;

// Re-export for convenience so test files don't need the full path.
pub use crate::api::wallet::APIWallet;

// Re-export commonly used types.
pub use crate::api::model::{APINetwork, APIProtectionType, APISecurityLevel};

// ── Constants ────────────────────────────────────────────────────────────────

/// 2-of-2 mainnet WSH descriptor used by the majority of tests.
///
/// Two-path notation `<0;1>/*` for receive/change chains.
pub const MAINNET_DESC: &str =
    "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";

/// 32-byte test encryption key (not secret — test only).
pub const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

/// Signet taproot descriptor with a single heir branch gated by an
/// **absolute** timelock (`after(800000)` → block height 800 000, well below
/// the BIP-65 timestamp threshold). Used to cover `apply_timelock_fixup` for
/// CLTV-style spend paths. No checksum: BDK appends one when loading.
pub const SIGNET_ABSOLUTE_TIMELOCK_DESC: &str = "tr([bc0dbbce/48'/1'/0'/2']tpubDEpnZReLc2mqbLNeGbNckbVTw6GTgfnz2s8r8wWoWrJY3ZP7dJ2hPKTbFk7RTqdSVYKJiDXQgT3jiACt3EGP5QuYjXqWvf6q1c7gN68Ywp8/<0;1>/*,and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*),after(800000)))";

/// Absolute height referenced by the `after()` clause in
/// [SIGNET_ABSOLUTE_TIMELOCK_DESC].
pub const SIGNET_ABSOLUTE_TIMELOCK_HEIGHT: u32 = 800_000;

/// Reg25 signet taproot inheritance descriptor with 5 heir paths.
///
/// Heir timelocks: older(6)=heir5, older(13140)=heir1, older(26280)=heir2,
///                 older(39420)=heir3, older(52560)=heir4.
pub const SIGNET_INHERITANCE_DESC: &str =
    "tr([bc0dbbce/48'/1'/0'/2']tpubDEpnZReLc2mqbLNeGbNckbVTw6GTgfnz2s8r8wWoWrJY3ZP7dJ2hPKTbFk7RTqdSVYKJiDXQgT3jiACt3EGP5QuYjXqWvf6q1c7gN68Ywp8/<0;1>/*,{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*),older(6)),{and_v(v:pk([ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*),older(13140)),{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<2;3>/*),older(26280)),{and_v(v:pk([4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*),older(39420)),and_v(v:pk([ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<0;1>/*),older(52560))}}}})#xak7t3uv";

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Create a wallet and return the [APIWallet] handle.
///
/// Uses [KEY_HEX] as the device key and [APIProtectionType::DeviceKey].
pub fn make_wallet(dir: &tempfile::TempDir) -> Result<APIWallet> {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = crate::api::wallet::create_wallet(
        wallets_dir,
        "Test Wallet".to_string(),
        MAINNET_DESC.to_string(),
        APINetwork::Bitcoin,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )?;
    crate::api::wallet::open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None)
        .map_err(|e| anyhow::anyhow!("open_wallet failed: {e}"))
}

/// Create a wallet with a custom descriptor and network.
pub fn make_wallet_with(
    dir: &tempfile::TempDir,
    descriptor: &str,
    network: APINetwork,
) -> Result<APIWallet> {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = crate::api::wallet::create_wallet(
        wallets_dir,
        "Test".to_string(),
        descriptor.to_string(),
        network,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )?;
    crate::api::wallet::open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None)
        .map_err(|e| anyhow::anyhow!("open_wallet failed: {e}"))
}

/// Inject a 1 000 000 sat UTXO to external address index 0 and return the txid.
pub fn inject_utxo(wallet: &APIWallet) -> Result<bdk_wallet::bitcoin::Txid> {
    use bdk_wallet::bitcoin::{
        absolute, transaction, Amount, OutPoint, Sequence, Transaction, TxIn, TxOut,
    };

    let spk = {
        let core = wallet.lock_wallet()?;
        core.wallet
            .peek_address(bdk_wallet::KeychainKind::External, 0)
            .address
            .script_pubkey()
    };
    let fake_prev = OutPoint {
        txid: bdk_wallet::bitcoin::Txid::from_raw_hash(
            *bdk_wallet::bitcoin::hashes::sha256d::Hash::from_bytes_ref(&[1u8; 32]),
        ),
        vout: 0,
    };
    let funding_tx = Transaction {
        version: transaction::Version::TWO,
        lock_time: absolute::LockTime::ZERO,
        input: vec![TxIn {
            previous_output: fake_prev,
            script_sig: Default::default(),
            sequence: Sequence::MAX,
            ..Default::default()
        }],
        output: vec![TxOut {
            value: Amount::from_sat(1_000_000),
            script_pubkey: spk,
        }],
    };
    let txid = funding_tx.compute_txid();
    wallet.inject_unconfirmed_tx(funding_tx)?;
    Ok(txid)
}
