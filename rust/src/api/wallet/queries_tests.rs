use super::*;
use bdk_wallet::bitcoin::{
    absolute, transaction, Amount, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Witness,
};
use tempfile::tempdir;

// ── Re-use the same descriptor / key from the mod.rs tests ──────────────
const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

fn make_wallet(dir: &tempfile::TempDir) -> APIWallet {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = create_wallet(
        wallets_dir,
        "CPFP Test Wallet".to_string(),
        MAINNET_DESC.to_string(),
        APINetwork::Bitcoin,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )
    .expect("create_wallet failed");
    open_wallet(info.wallet_path, KEY_HEX.to_string(), None).expect("open_wallet failed")
}

/// Return the scriptPubKey for external address at index `idx`.
fn wallet_spk(wallet: &APIWallet, idx: u32) -> ScriptBuf {
    let core = wallet.lock_wallet().unwrap();
    core.wallet
        .peek_address(bdk_wallet::KeychainKind::External, idx)
        .address
        .script_pubkey()
}

/// A P2WPKH scriptPubKey that is NOT in the wallet's SPK set.
/// Outputs to this script are invisible to `wallet.transactions()` while
/// still being available in `tx_graph.get_txout()` for fee calculation.
fn external_spk() -> ScriptBuf {
    // OP_0 <20 bytes of 0xde> — valid P2WPKH pattern, not in our wallet's SPK set.
    let mut bytes = vec![0x00u8, 0x14];
    bytes.extend_from_slice(&[0xde; 20]);
    ScriptBuf::from_bytes(bytes)
}

/// Build a genesis funding tx: sends `value_sat` to `spk`, no real inputs.
/// Insert via `inject_graph_tx` (with `external_spk()` as the spk) so the
/// tx is only present in the graph for txout lookups, not in `wallet.transactions()`.
fn genesis_tx(spk: ScriptBuf, value_sat: u64) -> Transaction {
    Transaction {
        version: transaction::Version::TWO,
        lock_time: absolute::LockTime::ZERO,
        input: vec![TxIn {
            previous_output: OutPoint::null(), // null → BFS will skip it
            script_sig: ScriptBuf::default(),
            sequence: Sequence::MAX,
            witness: Witness::default(),
        }],
        output: vec![TxOut {
            value: Amount::from_sat(value_sat),
            script_pubkey: spk,
        }],
    }
}

/// Build a spending transaction: one input spending `prev:vout`, one output to `spk`.
fn spending_tx(
    prev_txid: bdk_wallet::bitcoin::Txid,
    vout: u32,
    spk: ScriptBuf,
    value_sat: u64,
) -> Transaction {
    Transaction {
        version: transaction::Version::TWO,
        lock_time: absolute::LockTime::ZERO,
        input: vec![TxIn {
            previous_output: OutPoint {
                txid: prev_txid,
                vout,
            },
            script_sig: ScriptBuf::default(),
            sequence: Sequence::MAX,
            witness: Witness::default(),
        }],
        output: vec![TxOut {
            value: Amount::from_sat(value_sat),
            script_pubkey: spk,
        }],
    }
}

// ── Error cases ──────────────────────────────────────────────────────────

#[tokio::test]
async fn test_cpfp_empty_txids_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let result = wallet.get_cpfp_info(vec![]).await;
    assert!(result.is_err(), "empty txid list should return Err");
}

#[tokio::test]
async fn test_cpfp_invalid_txid_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let result = wallet
        .get_cpfp_info(vec!["not_a_valid_txid".to_string()])
        .await;
    assert!(result.is_err(), "invalid txid should return Err");
}

#[tokio::test]
async fn test_cpfp_no_unconfirmed_ancestor_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    // Valid txid but the tx is not in the wallet graph at all.
    let fake_txid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let result = wallet.get_cpfp_info(vec![fake_txid.to_string()]).await;
    assert!(
        result.is_err(),
        "txid not present in wallet should return Err"
    );
    let msg = result.unwrap_err().to_string();
    assert!(
        msg.contains("no unconfirmed ancestor"),
        "error message should mention 'no unconfirmed ancestor', got: {msg}"
    );
}

// ── Single parent, fee calculable ────────────────────────────────────────

#[tokio::test]
async fn test_cpfp_single_parent_fee_known() {
    // Setup: genesis (graph-only, external output) → parent (unconfirmed, wallet output).
    // genesis output = 100_000 sats, parent output = 90_000 sats → fee = 10_000 sats.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    // genesis goes to an external address → not wallet-relevant → not in wallet.transactions()
    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    // parent spends genesis:0 and sends to our wallet → wallet-relevant → in wallet.transactions()
    let parent = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let parent_txid = parent.compute_txid();
    wallet.inject_unconfirmed_tx(parent).unwrap();

    let info = wallet
        .get_cpfp_info(vec![parent_txid.to_string()])
        .await
        .expect("get_cpfp_info should succeed");

    assert_eq!(info.ancestor_count, 1, "should find exactly one ancestor");
    assert!(info.ancestor_vsize > 0, "vsize must be positive");
    assert_eq!(
        info.ancestor_fee_sat,
        Some(10_000),
        "fee should be 100_000 − 90_000 = 10_000 sats"
    );
    let expected_rate = 10_000.0 / info.ancestor_vsize as f64;
    assert!(
        (info.ancestor_fee_rate_sat_per_vb - expected_rate).abs() < 0.001,
        "fee rate should be fee / vsize"
    );
}

// ── Single parent, fee unknown (parent input not in graph) ───────────────

#[tokio::test]
async fn test_cpfp_single_parent_fee_unknown() {
    // Parent's input txout is NOT in the graph → fee cannot be calculated.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let unknown_txid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        .parse::<bdk_wallet::bitcoin::Txid>()
        .unwrap();
    // Output to our wallet → wallet-relevant → in wallet.transactions()
    let parent = spending_tx(unknown_txid, 0, wallet_spk(&wallet, 0), 50_000);
    let parent_txid = parent.compute_txid();
    wallet.inject_unconfirmed_tx(parent).unwrap();

    let info = wallet
        .get_cpfp_info(vec![parent_txid.to_string()])
        .await
        .expect("get_cpfp_info should succeed even when fee is unknown");

    assert_eq!(info.ancestor_count, 1);
    assert!(info.ancestor_vsize > 0);
    assert_eq!(
        info.ancestor_fee_sat, None,
        "fee should be None when parent inputs are not in the graph"
    );
    assert_eq!(
        info.ancestor_fee_rate_sat_per_vb, 0.0,
        "fee rate should be 0.0 when fee is unknown"
    );
}

// ── Transitive ancestors (grandparent chain) ─────────────────────────────

#[tokio::test]
async fn test_cpfp_transitive_ancestor_chain() {
    // genesis (graph-only, external) → grandparent (unconfirmed) → parent (unconfirmed)
    // BFS from parent should count both grandparent and parent: ancestor_count=2, fee=20k.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    // grandparent: spends genesis:0, output to wallet addr #0
    let grandparent = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let grandparent_txid = grandparent.compute_txid();
    wallet.inject_unconfirmed_tx(grandparent).unwrap();

    // parent: spends grandparent:0, output to wallet addr #1
    let parent = spending_tx(grandparent_txid, 0, wallet_spk(&wallet, 1), 80_000);
    let parent_txid = parent.compute_txid();
    wallet.inject_unconfirmed_tx(parent).unwrap();

    let info = wallet
        .get_cpfp_info(vec![parent_txid.to_string()])
        .await
        .expect("get_cpfp_info should succeed");

    assert_eq!(
        info.ancestor_count, 2,
        "should include grandparent and parent"
    );
    assert_eq!(
        info.ancestor_fee_sat,
        Some(20_000),
        "total fee: (100k−90k) + (90k−80k) = 20_000 sats"
    );
    assert!(info.ancestor_vsize > 0);
    let expected_rate = 20_000.0 / info.ancestor_vsize as f64;
    assert!((info.ancestor_fee_rate_sat_per_vb - expected_rate).abs() < 0.001);
}

// ── Multiple roots (multi-parent CPFP) ───────────────────────────────────

#[tokio::test]
async fn test_cpfp_multiple_roots_aggregated() {
    // Two independent unconfirmed parents (each with a known fee).
    // Passing both txids should aggregate ancestor_count=2, total_fee=20k.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    // Parent A: genesis_a (external, 100k) → parent_a (wallet addr #0, 90k), fee=10k
    let genesis_a = genesis_tx(external_spk(), 100_000);
    let genesis_a_txid = genesis_a.compute_txid();
    wallet.inject_graph_tx(genesis_a).unwrap();
    let parent_a = spending_tx(genesis_a_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let parent_a_txid = parent_a.compute_txid();
    wallet.inject_unconfirmed_tx(parent_a).unwrap();

    // Parent B: genesis_b (external, 60k) → parent_b (wallet addr #1, 50k), fee=10k
    // genesis_b has a different value so it has a distinct txid from genesis_a.
    let genesis_b = genesis_tx(external_spk(), 60_000);
    let genesis_b_txid = genesis_b.compute_txid();
    wallet.inject_graph_tx(genesis_b).unwrap();
    let parent_b = spending_tx(genesis_b_txid, 0, wallet_spk(&wallet, 1), 50_000);
    let parent_b_txid = parent_b.compute_txid();
    wallet.inject_unconfirmed_tx(parent_b).unwrap();

    let info = wallet
        .get_cpfp_info(vec![parent_a_txid.to_string(), parent_b_txid.to_string()])
        .await
        .expect("get_cpfp_info should succeed");

    assert_eq!(
        info.ancestor_count, 2,
        "should count both independent parents"
    );
    assert_eq!(
        info.ancestor_fee_sat,
        Some(20_000),
        "total fee: (100k−90k) + (60k−50k) = 20_000 sats"
    );
    assert!(info.ancestor_vsize > 0);
}

// ── Deduplication: same txid supplied twice ───────────────────────────────

#[tokio::test]
async fn test_cpfp_duplicate_txids_not_counted_twice() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let parent = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let parent_txid = parent.compute_txid();
    wallet.inject_unconfirmed_tx(parent).unwrap();

    // Supply the same txid twice — must count only once.
    let info = wallet
        .get_cpfp_info(vec![parent_txid.to_string(), parent_txid.to_string()])
        .await
        .expect("get_cpfp_info should succeed");

    assert_eq!(
        info.ancestor_count, 1,
        "duplicate txids must not inflate ancestor_count"
    );
    assert_eq!(info.ancestor_fee_sat, Some(10_000));
}
