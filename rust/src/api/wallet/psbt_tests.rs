use super::*;
use crate::api::model::{APICoinControl, APIPolicyPath, APIRecipient};
use crate::core::descriptor::DescriptorAnalyzer;
use bdk_wallet::bitcoin::{absolute, transaction, Amount, OutPoint, Sequence, Transaction, TxIn};
use bdk_wallet::KeychainKind;
use tempfile::tempdir;

const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

// Reg25 signet taproot inheritance descriptor: owner (bc0dbbce) + 5 heir paths.
// Heir timelocks: older(6)=heir5, older(13140)=heir1, older(26280)=heir2,
//                 older(39420)=heir3, older(52560)=heir4.
const SIGNET_INHERITANCE_DESC: &str =
    "tr([bc0dbbce/48'/1'/0'/2']tpubDEpnZReLc2mqbLNeGbNckbVTw6GTgfnz2s8r8wWoWrJY3ZP7dJ2hPKTbFk7RTqdSVYKJiDXQgT3jiACt3EGP5QuYjXqWvf6q1c7gN68Ywp8/<0;1>/*,{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*),older(6)),{and_v(v:pk([ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*),older(13140)),{and_v(v:pk([f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<2;3>/*),older(26280)),{and_v(v:pk([4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*),older(39420)),and_v(v:pk([ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<0;1>/*),older(52560))}}}})#xak7t3uv";

// Simple 2-of-2 P2WSH descriptor (mainnet, single spend path, no timelocks).
const MAINNET_2OF2_DESC: &str =
    "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn make_wallet(dir: &tempfile::TempDir, descriptor: &str, network: APINetwork) -> APIWallet {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = create_wallet(
        wallets_dir,
        "Test".to_string(),
        descriptor.to_string(),
        network,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )
    .expect("create_wallet failed");
    open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None).expect("open_wallet failed")
}

/// Inject a 1 000 000 sat UTXO to address index 0 and return the funding txid.
fn inject_utxo(wallet: &APIWallet) -> bdk_wallet::bitcoin::Txid {
    let spk = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 0)
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
            sequence: Sequence::MAX,
            ..Default::default()
        }],
        output: vec![bdk_wallet::bitcoin::TxOut {
            value: Amount::from_sat(1_000_000),
            script_pubkey: spk,
        }],
    };
    let txid = funding_tx.compute_txid();
    wallet
        .inject_unconfirmed_tx(funding_tx)
        .expect("inject_unconfirmed_tx failed");
    txid
}

/// Build a PSBT for the given spend path, delete the stored record, and return the raw base64.
/// Simulates the originating party exporting the PSBT to a QR / file.
fn create_and_export_psbt(
    wallet: &APIWallet,
    funding_txid: bdk_wallet::bitcoin::Txid,
    sp: &crate::core::spend_path::SpendPath,
    recv_addr: &str,
) -> anyhow::Result<String> {
    let policy_path = APIPolicyPath::from_spendpath(sp)?;
    let psbt_info = wallet.create_psbt(
        vec![APIRecipient {
            address: recv_addr.to_string(),
            amount_sat: 500_000,
        }],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        policy_path,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
    )?;
    let base64 = psbt_info.psbt_base64.clone();
    wallet.delete_psbt(psbt_info.id)?;
    Ok(base64)
}

/// Core of the import-infers-spend-path tests. Creates a PSBT for the spend path that
/// matches `rel_tl` and verifies that `import_psbt` reconstructs the correct metadata.
fn assert_import_infers_spend_path(rel_tl: u32) -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);

    let analyzer = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let core_paths = analyzer.spend_paths()?;
    let sp = core_paths
        .iter()
        .find(|sp| sp.rel_timelock == rel_tl && sp.abs_timelock == 0)
        .unwrap_or_else(|| panic!("spend path with rel_tl={} not in descriptor", rel_tl));

    let recv_addr = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 1)
            .address
            .to_string()
    };

    let psbt_base64 = create_and_export_psbt(&wallet, funding_txid, sp, &recv_addr)?;
    let result = wallet.import_psbt(psbt_base64)?;

    assert_eq!(result.psbt.spend_path_id, sp.id, "spend_path_id mismatch");
    assert_eq!(
        result.psbt.threshold, sp.threshold as u32,
        "threshold mismatch"
    );
    assert_eq!(result.psbt.mfps, sp.mfps, "mfps mismatch");

    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// import_psbt must infer the heir1 (older(13140)) spend path from nSequence.
#[test]
fn test_import_psbt_infers_heir_spend_path_id() -> anyhow::Result<()> {
    assert_import_infers_spend_path(13140)
}

/// import_psbt must infer the owner (key-path, no timelock) spend path.
#[test]
fn test_import_psbt_infers_owner_spend_path_id() -> anyhow::Result<()> {
    assert_import_infers_spend_path(0)
}

/// import_psbt must infer heir5 (older(6), the smallest relative timelock) from nSequence.
#[test]
fn test_import_psbt_infers_heir5_spend_path_id() -> anyhow::Result<()> {
    assert_import_infers_spend_path(6)
}

/// import_psbt must succeed even when the PSBT carries a non-zero lock_time set by
/// BDK's anti-fee-sniping (a block height, not a miniscript absolute timelock).
#[test]
fn test_import_psbt_ignores_antifee_sniping_locktime() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let funding_txid = inject_utxo(&wallet);

    let analyzer = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let paths = analyzer.spend_paths()?;
    // Owner spend path: key-path only, rel_tl = 0, abs_tl = 0.
    let owner_sp = paths
        .iter()
        .find(|sp| sp.rel_timelock == 0 && sp.abs_timelock == 0)
        .expect("owner spend path not found");

    let recv_addr = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 1)
            .address
            .to_string()
    };

    let psbt_base64 = create_and_export_psbt(&wallet, funding_txid, owner_sp, &recv_addr)?;

    // Patch lock_time to a block height simulating BDK anti-fee-sniping.
    // This must NOT be interpreted as an absolute timelock during import.
    let mut psbt = psbt_from_base64(&psbt_base64)?;
    psbt.unsigned_tx.lock_time = bdk_wallet::bitcoin::absolute::LockTime::from_height(234_567)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let patched = psbt_to_base64(&psbt);

    let result = wallet.import_psbt(patched)?;
    assert_eq!(
        result.psbt.spend_path_id, owner_sp.id,
        "spend_path_id mismatch"
    );
    assert!(!result.was_merged, "expected new import, not merge");

    Ok(())
}

/// A PSBT whose nSequence encodes a timelock not present in the wallet's descriptor
/// must be rejected with an error (not silently stored with spend_path_id = 0).
#[test]
fn test_import_psbt_wrong_wallet_returns_error() -> anyhow::Result<()> {
    let dir_a = tempdir()?;
    let wallet_a = make_wallet(&dir_a, SIGNET_INHERITANCE_DESC, APINetwork::Signet);
    let txid_a = inject_utxo(&wallet_a);

    let analyzer_a = DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)?;
    let paths_a = analyzer_a.spend_paths()?;
    let heir1 = paths_a.iter().find(|sp| sp.rel_timelock == 13140).unwrap();

    let recv_addr_a = {
        let core = wallet_a.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 1)
            .address
            .to_string()
    };

    let psbt_base64 = create_and_export_psbt(&wallet_a, txid_a, heir1, &recv_addr_a)?;

    // The 2-of-2 wallet has a single spend path with rel_tl=0; older(13140) won't match.
    let dir_b = tempdir()?;
    let wallet_b = make_wallet(&dir_b, MAINNET_2OF2_DESC, APINetwork::Bitcoin);

    let result = wallet_b.import_psbt(psbt_base64);
    assert!(
        result.is_err(),
        "importing a PSBT from a different wallet must return an error"
    );

    Ok(())
}
