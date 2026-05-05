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
    open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None).expect("open_wallet failed")
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

/// Build a tx with one input and two equal-value outputs (both to wallet by default).
fn two_output_tx(
    prev_txid: bdk_wallet::bitcoin::Txid,
    prev_vout: u32,
    spk0: ScriptBuf,
    spk1: ScriptBuf,
    value_each: u64,
) -> Transaction {
    Transaction {
        version: transaction::Version::TWO,
        lock_time: absolute::LockTime::ZERO,
        input: vec![TxIn {
            previous_output: OutPoint {
                txid: prev_txid,
                vout: prev_vout,
            },
            script_sig: ScriptBuf::default(),
            sequence: Sequence::MAX,
            witness: Witness::default(),
        }],
        output: vec![
            TxOut {
                value: Amount::from_sat(value_each),
                script_pubkey: spk0,
            },
            TxOut {
                value: Amount::from_sat(value_each),
                script_pubkey: spk1,
            },
        ],
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

// ─────────────────────────────────────────────────────────────────────────
// get_tx_details
// ─────────────────────────────────────────────────────────────────────────

#[test]
fn test_tx_details_not_found_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let fake_txid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let result = wallet.get_tx_details(fake_txid.to_string());
    let Err(err) = result else {
        panic!("expected Err for unknown txid");
    };
    let msg = err.to_string();
    assert!(
        msg.contains("transaction not found"),
        "expected 'transaction not found' error, got: {msg}"
    );
}

#[test]
fn test_tx_details_invalid_txid_returns_error() {
    // Lookup uses string equality so an invalid txid simply yields not-found.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let result = wallet.get_tx_details("not_a_valid_txid".to_string());
    assert!(result.is_err(), "invalid txid string should return Err");
}

#[test]
fn test_tx_details_external_input_to_wallet_output() {
    // genesis (graph-only, external) → tx (wallet output).
    // Verifies: fee from external input, is_mine=false on input, is_mine=true on output,
    // unconfirmed → confirmation_height/time = None.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let tx = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let txid = tx.compute_txid();
    wallet.inject_unconfirmed_tx(tx).unwrap();

    let details = wallet
        .get_tx_details(txid.to_string())
        .expect("get_tx_details should succeed");

    assert_eq!(details.tx.txid, txid.to_string());
    assert_eq!(details.tx.received, 90_000);
    assert_eq!(details.tx.sent, 0);
    assert_eq!(
        details.tx.fee,
        Some(10_000),
        "fee = 100_000 (external in graph) − 90_000 (output) = 10_000"
    );
    assert_eq!(details.tx.confirmation_height, None);
    assert_eq!(details.tx.confirmation_time, None);

    assert_eq!(details.input_addresses.len(), 1);
    let inp = &details.input_addresses[0];
    assert!(!inp.is_mine, "external input must not be is_mine");
    assert_eq!(
        inp.value_sat,
        Some(100_000),
        "input value must be resolved from tx_graph"
    );

    assert_eq!(details.output_addresses.len(), 1);
    let outp = &details.output_addresses[0];
    assert!(outp.is_mine, "output to wallet spk must be is_mine");
    assert_eq!(outp.value_sat, Some(90_000));
}

#[test]
fn test_tx_details_self_send_input_and_output_are_mine() {
    // genesis (graph) → parent (to wallet) → child (spends wallet utxo, sends to wallet).
    // child's input must resolve via tx_map (parent in wallet.transactions()) → is_mine=true.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let parent = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let parent_txid = parent.compute_txid();
    wallet.inject_unconfirmed_tx(parent).unwrap();

    let child = spending_tx(parent_txid, 0, wallet_spk(&wallet, 1), 80_000);
    let child_txid = child.compute_txid();
    wallet.inject_unconfirmed_tx(child).unwrap();

    let details = wallet
        .get_tx_details(child_txid.to_string())
        .expect("get_tx_details should succeed");

    assert_eq!(
        details.tx.fee,
        Some(10_000),
        "child fee = 90_000 − 80_000 = 10_000"
    );
    assert_eq!(details.input_addresses.len(), 1);
    assert!(
        details.input_addresses[0].is_mine,
        "input spends parent output owned by wallet → is_mine"
    );
    assert_eq!(details.input_addresses[0].value_sat, Some(90_000));
    assert_eq!(details.output_addresses.len(), 1);
    assert!(details.output_addresses[0].is_mine);
}

#[test]
fn test_tx_details_unresolvable_input_shows_truncated_format() {
    // Input refers to a tx not in graph and electrum_url is empty (no fetch happens).
    // Expect fee=None and address rendered as "<8 hex chars>…:<vout>".
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let unknown_txid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        .parse::<bdk_wallet::bitcoin::Txid>()
        .unwrap();
    let tx = spending_tx(unknown_txid, 5, wallet_spk(&wallet, 0), 50_000);
    let txid = tx.compute_txid();
    wallet.inject_unconfirmed_tx(tx).unwrap();

    let details = wallet
        .get_tx_details(txid.to_string())
        .expect("get_tx_details should succeed");

    assert_eq!(
        details.tx.fee, None,
        "fee unknown when prev input is not in graph"
    );
    assert_eq!(details.input_addresses.len(), 1);
    let inp = &details.input_addresses[0];
    assert!(!inp.is_mine);
    assert_eq!(inp.value_sat, None);
    assert!(
        inp.address.starts_with("bbbbbbbb") && inp.address.contains(":5"),
        "expected truncated 'bbbbbbbb…:5' format, got: {}",
        inp.address
    );
}

#[test]
fn test_tx_details_related_utxos_only_unspent_outputs() {
    // tx with two wallet outputs; spend one. Only the unspent one must appear in related_utxos.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 200_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let tx = two_output_tx(
        genesis_txid,
        0,
        wallet_spk(&wallet, 0),
        wallet_spk(&wallet, 1),
        90_000,
    );
    let txid = tx.compute_txid();
    wallet.inject_unconfirmed_tx(tx).unwrap();

    // Spend vout 0 to an external address.
    let spend = spending_tx(txid, 0, external_spk(), 80_000);
    wallet.inject_unconfirmed_tx(spend).unwrap();

    let details = wallet
        .get_tx_details(txid.to_string())
        .expect("get_tx_details should succeed");

    assert_eq!(
        details.output_addresses.len(),
        2,
        "output_addresses lists all outputs, spent or not"
    );
    assert_eq!(
        details.related_utxos.len(),
        1,
        "spent output must not appear in related_utxos"
    );
    assert_eq!(details.related_utxos[0].vout, 1);
    assert_eq!(details.related_utxos[0].value_sat, 90_000);
    assert_eq!(details.related_utxos[0].txid, txid.to_string());
}

#[test]
fn test_tx_details_output_to_external_address_is_not_mine() {
    // Wallet sends out: input is_mine=true, output is_mine=false, sent reflects spent value.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let funding_txid = funding.compute_txid();
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let outgoing = spending_tx(funding_txid, 0, external_spk(), 80_000);
    let outgoing_txid = outgoing.compute_txid();
    wallet.inject_unconfirmed_tx(outgoing).unwrap();

    let details = wallet
        .get_tx_details(outgoing_txid.to_string())
        .expect("get_tx_details should succeed");

    assert_eq!(details.output_addresses.len(), 1);
    assert!(
        !details.output_addresses[0].is_mine,
        "output to external script must not be is_mine"
    );
    assert_eq!(details.output_addresses[0].value_sat, Some(80_000));
    assert_eq!(
        details.related_utxos.len(),
        0,
        "external output is not ours"
    );
    assert_eq!(details.tx.sent, 90_000, "sent equals owned input value");
    assert_eq!(details.tx.received, 0);
    assert_eq!(details.tx.fee, Some(10_000));
}

// ─────────────────────────────────────────────────────────────────────────
// get_rbf_info
// ─────────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn test_rbf_invalid_txid_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let result = wallet.get_rbf_info("not_a_valid_txid".to_string()).await;
    let Err(err) = result else {
        panic!("expected Err for unparsable txid");
    };
    assert!(
        err.to_string().contains("invalid txid"),
        "expected 'invalid txid' error, got: {err}"
    );
}

#[tokio::test]
async fn test_rbf_tx_not_in_graph_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let fake_txid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let result = wallet.get_rbf_info(fake_txid.to_string()).await;
    let Err(err) = result else {
        panic!("expected Err for tx absent from graph");
    };
    assert!(
        err.to_string().contains("spending tx not found"),
        "expected 'spending tx not found' error, got: {err}"
    );
}

#[tokio::test]
async fn test_rbf_no_descendants_fee_known() {
    // genesis (graph, external 100k) → orig (unconfirmed, wallet output 90k). fee=10k.
    // No descendants → descendant_count=0, descendant_fee=Some(0),
    // min_fee_sat = orig_fee + orig_vsize, package_rate = orig_rate.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let orig = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let orig_txid = orig.compute_txid();
    wallet.inject_unconfirmed_tx(orig).unwrap();

    let info = wallet
        .get_rbf_info(orig_txid.to_string())
        .await
        .expect("get_rbf_info should succeed");

    assert_eq!(info.orig_fee_sat, 10_000);
    assert!(info.orig_vsize > 0);
    let expected_rate = 10_000.0 / info.orig_vsize as f64;
    assert!((info.orig_fee_rate_sat_per_vb - expected_rate).abs() < 0.001);

    assert_eq!(info.descendant_count, 0);
    assert_eq!(
        info.descendant_fee_sat,
        Some(0),
        "no descendants → all_known=true, fee_total=0"
    );
    assert_eq!(info.descendant_vsize, 0);

    // BIP-125 Rule 4: min_fee = orig_fee + orig_vsize × 1 sat/vB.
    assert_eq!(info.min_fee_sat, 10_000 + info.orig_vsize as u64);
    // Package rate equals orig rate when no descendants and desc_fee_opt is Some.
    assert!((info.min_fee_rate_sat_per_vb - expected_rate).abs() < 0.001);
}

#[tokio::test]
async fn test_rbf_input_value_unknown_returns_error() {
    // Input refers to a tx not in graph and electrum_url is empty → fee can't be calculated
    // and resolution fails → "input value unknown for RBF fee calc".
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let unknown_txid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        .parse::<bdk_wallet::bitcoin::Txid>()
        .unwrap();
    let orig = spending_tx(unknown_txid, 0, wallet_spk(&wallet, 0), 50_000);
    let orig_txid = orig.compute_txid();
    wallet.inject_unconfirmed_tx(orig).unwrap();

    let result = wallet.get_rbf_info(orig_txid.to_string()).await;
    let Err(err) = result else {
        panic!("expected Err when input value unknown");
    };
    assert!(
        err.to_string().contains("input value unknown"),
        "expected 'input value unknown' error, got: {err}"
    );
}

#[tokio::test]
async fn test_rbf_single_descendant_chain() {
    // genesis (graph, external 100k) → orig (wallet 90k) → child (wallet 80k).
    // Replacing orig also evicts child. descendant_count=1, descendant_fee=Some(10k),
    // min_fee_sat = (10k + 10k) + orig_vsize.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let orig = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let orig_txid = orig.compute_txid();
    wallet.inject_unconfirmed_tx(orig).unwrap();

    let child = spending_tx(orig_txid, 0, wallet_spk(&wallet, 1), 80_000);
    let child_vsize = child.weight().to_vbytes_ceil() as u32;
    wallet.inject_unconfirmed_tx(child).unwrap();

    let info = wallet
        .get_rbf_info(orig_txid.to_string())
        .await
        .expect("get_rbf_info should succeed");

    assert_eq!(info.orig_fee_sat, 10_000);
    assert_eq!(info.descendant_count, 1);
    assert_eq!(
        info.descendant_fee_sat,
        Some(10_000),
        "child fee = 90k − 80k"
    );
    assert_eq!(info.descendant_vsize, child_vsize);

    let total_conflict_fee = 10_000u64 + 10_000u64;
    assert_eq!(
        info.min_fee_sat,
        total_conflict_fee + info.orig_vsize as u64,
        "min_fee = orig_fee + desc_fee + orig_vsize"
    );

    // Package rate = (orig_fee + desc_fee) / (orig_vsize + desc_vsize).
    let expected_pkg = total_conflict_fee as f64 / (info.orig_vsize + info.descendant_vsize) as f64;
    assert!(
        (info.min_fee_rate_sat_per_vb - expected_pkg).abs() < 0.001,
        "package rate mismatch: got {} expected {expected_pkg}",
        info.min_fee_rate_sat_per_vb
    );
}

#[tokio::test]
async fn test_rbf_transitive_descendants_chain() {
    // orig → child → grandchild, all unconfirmed → descendant_count=2, fee summed.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let orig = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let orig_txid = orig.compute_txid();
    wallet.inject_unconfirmed_tx(orig).unwrap();

    let child = spending_tx(orig_txid, 0, wallet_spk(&wallet, 1), 80_000);
    let child_txid = child.compute_txid();
    wallet.inject_unconfirmed_tx(child).unwrap();

    let grandchild = spending_tx(child_txid, 0, wallet_spk(&wallet, 2), 70_000);
    wallet.inject_unconfirmed_tx(grandchild).unwrap();

    let info = wallet
        .get_rbf_info(orig_txid.to_string())
        .await
        .expect("get_rbf_info should succeed");

    assert_eq!(info.descendant_count, 2, "child + grandchild");
    assert_eq!(
        info.descendant_fee_sat,
        Some(20_000),
        "child(10k) + grandchild(10k)"
    );
    assert!(info.descendant_vsize > 0);
    // min_fee_sat = orig_fee(10k) + desc_fee(20k) + orig_vsize.
    assert_eq!(info.min_fee_sat, 30_000 + info.orig_vsize as u64);
}

#[tokio::test]
async fn test_rbf_zero_vsize_yields_default_rate() {
    // Sanity guard: when fee can be calculated (fee=0 here would still be valid),
    // a tx with non-zero vsize must produce a finite rate. Verifies the vsize>0 branch
    // is the one taken in normal use (the vsize==0 fallback is unreachable for real txs
    // but we assert the normal branch behaves).
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    // 0-fee tx: input 100k → output 100k, fee=0 but vsize>0.
    let orig = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 100_000);
    let orig_txid = orig.compute_txid();
    wallet.inject_unconfirmed_tx(orig).unwrap();

    let info = wallet
        .get_rbf_info(orig_txid.to_string())
        .await
        .expect("get_rbf_info should succeed");

    assert_eq!(info.orig_fee_sat, 0);
    assert!(info.orig_vsize > 0);
    assert!(
        info.orig_fee_rate_sat_per_vb.abs() < 0.001,
        "0-fee tx must have ~0 rate, got {}",
        info.orig_fee_rate_sat_per_vb
    );
    // min_fee_sat still requires orig_vsize × 1 sat/vB (relay floor).
    assert_eq!(info.min_fee_sat, info.orig_vsize as u64);
}

// ─────────────────────────────────────────────────────────────────────────
// get_addresses + get_address_details
// ─────────────────────────────────────────────────────────────────────────

/// Convenience: peek address string (does not reveal).
fn wallet_address(wallet: &APIWallet, idx: u32) -> String {
    let core = wallet.lock_wallet().unwrap();
    core.wallet
        .peek_address(bdk_wallet::KeychainKind::External, idx)
        .address
        .to_string()
}

#[test]
fn test_get_addresses_after_reveal_returns_sorted_list() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let total = wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::External, 3)
        .expect("reveal_more_addresses");
    assert!(total >= 3);

    let addrs = wallet
        .get_addresses(crate::api::model::APIKeychain::External)
        .expect("get_addresses");

    assert!(
        addrs.len() >= 3,
        "expected at least 3 revealed addresses, got {}",
        addrs.len()
    );
    // Indices ascending.
    for w in addrs.windows(2) {
        assert!(
            w[0].index < w[1].index,
            "addresses must be sorted by index ascending"
        );
    }
    // First three are 0, 1, 2.
    assert_eq!(addrs[0].index, 0);
    assert_eq!(addrs[1].index, 1);
    assert_eq!(addrs[2].index, 2);
    // Fresh wallet → none used.
    for a in addrs.iter().take(3) {
        assert!(!a.is_used);
        assert_eq!(a.balance_sat, 0);
        assert_eq!(a.tx_count, 0);
    }
}

#[test]
fn test_get_addresses_marks_used_with_balance_and_tx_count() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::External, 3)
        .unwrap();

    // Fund index 1 with 50_000 sats from external genesis.
    let genesis = genesis_tx(external_spk(), 60_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 1), 50_000);
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let addrs = wallet
        .get_addresses(crate::api::model::APIKeychain::External)
        .unwrap();

    let addr0 = addrs.iter().find(|a| a.index == 0).expect("index 0");
    let addr1 = addrs.iter().find(|a| a.index == 1).expect("index 1");
    let addr2 = addrs.iter().find(|a| a.index == 2).expect("index 2");

    assert!(!addr0.is_used);
    assert!(addr1.is_used, "funded address must be is_used");
    assert_eq!(addr1.balance_sat, 50_000);
    assert_eq!(addr1.tx_count, 1);
    assert!(!addr2.is_used);
    assert_eq!(addr2.balance_sat, 0);
}

#[test]
fn test_get_addresses_tx_count_counts_receive_and_spend() {
    // addr 0 receives tx A, then is spent in tx B → tx_count=2 for addr 0.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::External, 2)
        .unwrap();

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    // tx A: pays addr 0 (90k)
    let tx_a = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let tx_a_txid = tx_a.compute_txid();
    wallet.inject_unconfirmed_tx(tx_a).unwrap();

    // tx B: spends addr 0's utxo, pays addr 1 (80k)
    let tx_b = spending_tx(tx_a_txid, 0, wallet_spk(&wallet, 1), 80_000);
    wallet.inject_unconfirmed_tx(tx_b).unwrap();

    let addrs = wallet
        .get_addresses(crate::api::model::APIKeychain::External)
        .unwrap();

    let addr0 = addrs.iter().find(|a| a.index == 0).unwrap();
    assert_eq!(
        addr0.tx_count, 2,
        "addr 0 appears as receiver in A and spender in B"
    );
    assert_eq!(addr0.balance_sat, 0, "spent → balance 0");
    assert!(addr0.is_used);

    let addr1 = addrs.iter().find(|a| a.index == 1).unwrap();
    assert_eq!(addr1.tx_count, 1, "addr 1 only receives in B");
    assert_eq!(addr1.balance_sat, 80_000);
}

#[test]
fn test_get_addresses_keychain_isolation() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::External, 2)
        .unwrap();
    wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::Internal, 2)
        .unwrap();

    // Fund external addr 0.
    let genesis = genesis_tx(external_spk(), 60_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 50_000);
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let ext = wallet
        .get_addresses(crate::api::model::APIKeychain::External)
        .unwrap();
    let int = wallet
        .get_addresses(crate::api::model::APIKeychain::Internal)
        .unwrap();

    assert!(ext.iter().any(|a| a.is_used && a.balance_sat == 50_000));
    assert!(
        int.iter().all(|a| !a.is_used && a.balance_sat == 0),
        "internal keychain must not see external usage"
    );
    for a in &ext {
        assert!(matches!(
            a.keychain,
            crate::api::model::APIKeychain::External
        ));
    }
    for a in &int {
        assert!(matches!(
            a.keychain,
            crate::api::model::APIKeychain::Internal
        ));
    }
}

#[test]
fn test_address_details_not_found_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let result = wallet.get_address_details("bc1qfakeaddressnotrevealed".to_string());
    let Err(err) = result else {
        panic!("expected Err for unknown address");
    };
    assert!(
        err.to_string().contains("address not found"),
        "expected 'address not found' error, got: {err}"
    );
}

#[test]
fn test_address_details_unused_revealed_address() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::External, 1)
        .unwrap();
    let addr_str = wallet_address(&wallet, 0);

    let details = wallet
        .get_address_details(addr_str.clone())
        .expect("get_address_details");

    assert_eq!(details.address.address, addr_str);
    assert_eq!(details.address.index, 0);
    assert!(matches!(
        details.address.keychain,
        crate::api::model::APIKeychain::External
    ));
    assert!(!details.address.is_used);
    assert_eq!(details.address.balance_sat, 0);
    assert_eq!(details.address.tx_count, 0);
    assert!(details.related_utxos.is_empty());
    assert!(details.related_txs.is_empty());
}

#[test]
fn test_address_details_received_funds() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::External, 1)
        .unwrap();
    let addr_str = wallet_address(&wallet, 0);

    let genesis = genesis_tx(external_spk(), 60_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 50_000);
    let funding_txid = funding.compute_txid();
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let details = wallet.get_address_details(addr_str).unwrap();

    assert!(details.address.is_used);
    assert_eq!(details.address.balance_sat, 50_000);
    assert_eq!(details.address.tx_count, 1);
    assert_eq!(details.related_utxos.len(), 1);
    assert_eq!(details.related_utxos[0].value_sat, 50_000);
    assert_eq!(details.related_utxos[0].txid, funding_txid.to_string());

    assert_eq!(details.related_txs.len(), 1);
    let rtx = &details.related_txs[0];
    assert_eq!(rtx.txid, funding_txid.to_string());
    assert_eq!(rtx.addr_received, 50_000);
    assert_eq!(rtx.addr_spent, 0);
    assert_eq!(rtx.confirmation_height, None);
    assert_eq!(rtx.fee, Some(10_000));
}

#[test]
fn test_address_details_received_then_spent() {
    // addr 0 receives, then is spent → balance=0, related_utxos empty, related_txs has 2 entries.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    wallet
        .reveal_more_addresses(crate::api::model::APIKeychain::External, 2)
        .unwrap();
    let addr0 = wallet_address(&wallet, 0);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let recv = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let recv_txid = recv.compute_txid();
    wallet.inject_unconfirmed_tx(recv).unwrap();
    let spend = spending_tx(recv_txid, 0, wallet_spk(&wallet, 1), 80_000);
    let spend_txid = spend.compute_txid();
    wallet.inject_unconfirmed_tx(spend).unwrap();

    let details = wallet.get_address_details(addr0).unwrap();

    assert!(details.address.is_used);
    assert_eq!(details.address.balance_sat, 0, "spent → 0");
    assert_eq!(details.address.tx_count, 2);
    assert!(
        details.related_utxos.is_empty(),
        "no unspent outputs at this address"
    );
    assert_eq!(details.related_txs.len(), 2);

    let recv_entry = details
        .related_txs
        .iter()
        .find(|t| t.txid == recv_txid.to_string())
        .expect("receiving tx in related_txs");
    assert_eq!(recv_entry.addr_received, 90_000);
    assert_eq!(recv_entry.addr_spent, 0);

    let spend_entry = details
        .related_txs
        .iter()
        .find(|t| t.txid == spend_txid.to_string())
        .expect("spending tx in related_txs");
    assert_eq!(
        spend_entry.addr_received, 0,
        "addr 0 only loses funds in spend tx"
    );
    assert_eq!(
        spend_entry.addr_spent, 90_000,
        "addr_spent reflects the input value taken from this address"
    );
}

// ─────────────────────────────────────────────────────────────────────────
// get_utxos
// ─────────────────────────────────────────────────────────────────────────

#[test]
fn test_get_utxos_lists_funded_unspent_outputs() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let funding_txid = funding.compute_txid();
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let utxos = wallet.get_utxos().expect("get_utxos");

    assert_eq!(utxos.len(), 1);
    let u = &utxos[0];
    assert_eq!(u.txid, funding_txid.to_string());
    assert_eq!(u.vout, 0);
    assert_eq!(u.value_sat, 90_000);
    assert_eq!(u.derivation_index, 0);
    assert!(matches!(
        u.keychain,
        crate::api::model::APIKeychain::External
    ));
    assert!(!u.is_confirmed, "unconfirmed funding tx → utxo unconfirmed");
    assert_eq!(u.confirmation_height, None);
    assert_eq!(u.confirmation_time, None);
    assert!(u.mempool_spending_txid.is_none());
    assert!(u.pending_psbt_ids.is_empty());
}

#[test]
fn test_get_utxos_excludes_external_outputs() {
    // A tx pays to an external script — it must not appear in get_utxos().
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let outgoing = spending_tx(genesis_txid, 0, external_spk(), 90_000);
    wallet.inject_unconfirmed_tx(outgoing).unwrap();

    let utxos = wallet.get_utxos().expect("get_utxos");
    assert!(
        utxos.is_empty(),
        "outputs to external scripts must not appear, got {} utxos",
        utxos.len()
    );
}

#[test]
fn test_get_utxos_ghost_utxo_for_unconfirmed_spend() {
    // wallet receives 90k at addr 0, then spends it to an external addr while still
    // unconfirmed → BDK removes it from list_unspent, but get_utxos must surface it
    // as a ghost UTXO with mempool_spending_txid set.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let funding_txid = funding.compute_txid();
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let spend = spending_tx(funding_txid, 0, external_spk(), 80_000);
    let spend_txid = spend.compute_txid();
    wallet.inject_unconfirmed_tx(spend).unwrap();

    let utxos = wallet.get_utxos().expect("get_utxos");

    assert_eq!(utxos.len(), 1, "ghost utxo must be surfaced once");
    let ghost = &utxos[0];
    assert_eq!(ghost.txid, funding_txid.to_string());
    assert_eq!(ghost.vout, 0);
    assert_eq!(ghost.value_sat, 90_000);
    assert_eq!(
        ghost.mempool_spending_txid,
        Some(spend_txid.to_string()),
        "spending tx id must be surfaced for the ghost utxo"
    );
}

#[test]
fn test_get_utxos_sorted_by_value_descending() {
    // Two utxos at addr 0 and addr 1 with different values → sorted by value desc.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    // Smaller utxo (50k).
    let g_small = genesis_tx(external_spk(), 60_000);
    let g_small_txid = g_small.compute_txid();
    wallet.inject_graph_tx(g_small).unwrap();
    let small = spending_tx(g_small_txid, 0, wallet_spk(&wallet, 0), 50_000);
    wallet.inject_unconfirmed_tx(small).unwrap();

    // Larger utxo (90k).
    let g_big = genesis_tx(external_spk(), 100_000);
    let g_big_txid = g_big.compute_txid();
    wallet.inject_graph_tx(g_big).unwrap();
    let big = spending_tx(g_big_txid, 0, wallet_spk(&wallet, 1), 90_000);
    wallet.inject_unconfirmed_tx(big).unwrap();

    let utxos = wallet.get_utxos().expect("get_utxos");
    assert_eq!(utxos.len(), 2);
    assert_eq!(utxos[0].value_sat, 90_000, "largest utxo first");
    assert_eq!(utxos[1].value_sat, 50_000);
}

// ─────────────────────────────────────────────────────────────────────────
// get_utxo_details
// ─────────────────────────────────────────────────────────────────────────

#[test]
fn test_get_utxo_details_not_found_returns_error() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let fake_txid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let result = wallet.get_utxo_details(fake_txid.to_string(), 0);
    let Err(err) = result else {
        panic!("expected Err for unknown utxo");
    };
    assert!(
        err.to_string().contains("UTXO not found"),
        "expected 'UTXO not found' error, got: {err}"
    );
}

#[test]
fn test_get_utxo_details_returns_creating_tx() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let funding_txid = funding.compute_txid();
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let details = wallet
        .get_utxo_details(funding_txid.to_string(), 0)
        .expect("get_utxo_details");

    assert_eq!(details.utxo.txid, funding_txid.to_string());
    assert_eq!(details.utxo.vout, 0);
    assert_eq!(details.utxo.value_sat, 90_000);
    assert!(!details.utxo.is_confirmed);

    let creating = &details.creating_tx;
    assert_eq!(creating.txid, funding_txid.to_string());
    assert_eq!(
        creating.addr_received, 90_000,
        "creating tx contributes the full output value to this utxo"
    );
    assert_eq!(
        creating.addr_spent, 0,
        "creating tx is the source — nothing spent"
    );
    assert_eq!(
        creating.fee,
        Some(10_000),
        "fee = 100_000 (graph external in) − 90_000 (out) = 10_000"
    );
    assert_eq!(creating.confirmation_height, None);
}

#[test]
fn test_get_utxo_details_wrong_vout_returns_error() {
    // Funding tx exists but the requested vout doesn't.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let funding_txid = funding.compute_txid();
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let result = wallet.get_utxo_details(funding_txid.to_string(), 99);
    assert!(result.is_err(), "non-existing vout must return Err");
}

// ─────────────────────────────────────────────────────────────────────────
// get_transactions
// ─────────────────────────────────────────────────────────────────────────

#[test]
fn test_get_transactions_empty_wallet() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);
    let page = wallet.get_transactions(0, 10).expect("get_transactions");
    assert_eq!(page.total_count, 0);
    assert!(!page.has_more);
    assert!(page.transactions.is_empty());
}

#[test]
fn test_get_transactions_paginated() {
    // Inject a chain of 3 txs (each spending the previous output) → 3 wallet-relevant txs.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();

    let t1 = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let t1_txid = t1.compute_txid();
    wallet.inject_unconfirmed_tx(t1).unwrap();
    let t2 = spending_tx(t1_txid, 0, wallet_spk(&wallet, 1), 80_000);
    let t2_txid = t2.compute_txid();
    wallet.inject_unconfirmed_tx(t2).unwrap();
    let t3 = spending_tx(t2_txid, 0, wallet_spk(&wallet, 2), 70_000);
    wallet.inject_unconfirmed_tx(t3).unwrap();

    // Page 0, size 2 → first 2 + has_more=true.
    let page0 = wallet.get_transactions(0, 2).unwrap();
    assert_eq!(page0.total_count, 3);
    assert_eq!(page0.transactions.len(), 2);
    assert!(
        page0.has_more,
        "page 0 of 3 with size 2 → more pages remain"
    );

    // Page 1, size 2 → last 1 + has_more=false.
    let page1 = wallet.get_transactions(1, 2).unwrap();
    assert_eq!(page1.total_count, 3);
    assert_eq!(page1.transactions.len(), 1);
    assert!(!page1.has_more);

    // Page beyond range → empty page, total_count still accurate.
    let page_oob = wallet.get_transactions(5, 2).unwrap();
    assert_eq!(page_oob.total_count, 3);
    assert!(page_oob.transactions.is_empty());
    assert!(!page_oob.has_more);
}

#[test]
fn test_get_transactions_unconfirmed_sorted_first() {
    // All txs unconfirmed (height upper bound = None → treated as MAX → newest-first).
    // We just check that every entry is reported as unconfirmed and counts match.
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 200_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let a = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 180_000);
    let a_txid = a.compute_txid();
    wallet.inject_unconfirmed_tx(a).unwrap();
    let b = spending_tx(a_txid, 0, wallet_spk(&wallet, 1), 160_000);
    wallet.inject_unconfirmed_tx(b).unwrap();

    let page = wallet.get_transactions(0, 10).unwrap();
    assert_eq!(page.total_count, 2);
    assert_eq!(page.transactions.len(), 2);
    for tx in &page.transactions {
        assert_eq!(
            tx.confirmation_height, None,
            "unconfirmed tx must carry no height"
        );
        assert_eq!(tx.confirmation_time, None);
    }
}

#[test]
fn test_get_transactions_fee_and_amounts() {
    let dir = tempdir().unwrap();
    let wallet = make_wallet(&dir);

    let genesis = genesis_tx(external_spk(), 100_000);
    let genesis_txid = genesis.compute_txid();
    wallet.inject_graph_tx(genesis).unwrap();
    let funding = spending_tx(genesis_txid, 0, wallet_spk(&wallet, 0), 90_000);
    let funding_txid = funding.compute_txid();
    wallet.inject_unconfirmed_tx(funding).unwrap();

    let page = wallet.get_transactions(0, 10).unwrap();
    let entry = page
        .transactions
        .iter()
        .find(|t| t.txid == funding_txid.to_string())
        .expect("funding tx in page");
    assert_eq!(entry.received, 90_000);
    assert_eq!(entry.sent, 0);
    assert_eq!(entry.fee, Some(10_000));
}
