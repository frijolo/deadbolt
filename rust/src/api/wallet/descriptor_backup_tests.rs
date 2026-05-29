use super::*;

// ---------------------------------------------------------------------------
// Protocol constant tests
// ---------------------------------------------------------------------------

#[test]
fn anchor_domain_tag_is_stable() {
    assert_eq!(ANCHOR_DOMAIN_TAG, b"deadbolt-anchor-v1");
}

#[test]
fn nums_xonly_hex_parses() {
    let bytes = hex::decode(NUMS_XONLY_HEX).unwrap();
    let _ = bdk_wallet::bitcoin::key::XOnlyPublicKey::from_slice(&bytes).unwrap();
}

#[test]
fn vault_tapscript_roundtrip_small() {
    let data = b"hello world";
    let ts = vault_tapscript(data);
    let bytes = ts.as_bytes();
    // OP_1(0x51) OP_FALSE(0x00) OP_IF(0x63) <push len=11> <data> OP_ENDIF(0x68)
    assert_eq!(bytes[0], 0x51);
    assert_eq!(bytes[1], 0x00);
    assert_eq!(bytes[2], 0x63);
    assert_eq!(bytes[3], 11);
    assert_eq!(&bytes[4..15], b"hello world");
    assert_eq!(*bytes.last().unwrap(), 0x68);
}

#[test]
fn vault_tapscript_roundtrip_large() {
    // Payload that spans multiple 520-byte chunks.
    let data: Vec<u8> = (0u8..=255).cycle().take(1200).collect();
    let ts = vault_tapscript(&data);
    let bytes = ts.as_bytes();
    assert_eq!(bytes[0], 0x51);
    assert_eq!(bytes[1], 0x00);
    assert_eq!(bytes[2], 0x63);
    assert_eq!(*bytes.last().unwrap(), 0x68);
}

#[test]
fn anchor_key_derivation_is_deterministic() {
    use std::str::FromStr;
    let secp = bdk_wallet::bitcoin::secp256k1::Secp256k1::new();
    let xpub_str = "tpubDELADszW6V8mwnjo4wyTCkmNWPrzoW9ivufEBKb8xsE6vJ47\
                    hKEyXW1aSK8sKgN2d4LonwDvJsbDU3h6jF8BNBfB97EoWEhpNPPfFwocKmA";
    let xpub = bdk_wallet::bitcoin::bip32::Xpub::from_str(xpub_str).unwrap();
    let k1 = derive_anchor_key(&secp, &xpub);
    let k2 = derive_anchor_key(&secp, &xpub);
    assert_eq!(k1.xonly, k2.xonly);
    assert_eq!(k1.privkey, k2.privkey);
}

#[test]
fn weight_calculations_are_positive() {
    for n in 1..=6usize {
        assert!(commit_weight(1, n, KEYPATH_INPUT_WU) > 0);
        assert!(reveal_weight(1536, n) > 0);
    }
}

#[test]
fn fee_from_weight_rounds_up() {
    // 4 WU = 1 vB; at 2.0 sat/vB that's 2 sats.
    assert_eq!(fee_from_weight(4, 2.0), 2);
    // 5 WU = 2 vB (ceil); at 1.5 sat/vB → ceil(2 * 1.5) = 3.
    assert_eq!(fee_from_weight(5, 1.5), 3);
}

#[test]
fn split_package_fees_low_rate_meets_relay_minimum() {
    // Simulate a TX_REVEAL with ~760 vB and TX_COMMIT with ~275 vB.
    // At 0.1 sat/vB the raw split would give reveal_fee = 76 sats,
    // below a typical 78-sat minimum relay fee.
    let commit_wu = 1096; // ~275 vB
    let reveal_wu = 3040; // ~760 vB
    let (commit_fee, reveal_fee) = split_package_fees(commit_wu, reveal_wu, 0.1, 1.0);

    // reveal_fee must be at least reveal_vbytes * 1.0 (min_fee_rate)
    let reveal_vbytes = reveal_wu.div_ceil(4);
    assert!(
        reveal_fee >= reveal_vbytes,
        "reveal_fee {} < min relay {} (reveal_vbytes)",
        reveal_fee,
        reveal_vbytes
    );

    // commit_fee must still be positive and based on min_fee_rate
    assert!(commit_fee > 0);
    let commit_vbytes = commit_wu.div_ceil(4);
    assert!(
        commit_fee > ((commit_vbytes as f64 * 1.0).ceil() as u64).max(1),
        "commit_fee {} too low for {}",
        commit_fee,
        commit_vbytes
    );
}

#[test]
fn split_package_fees_normal_rate_no_bump() {
    // At 2.0 sat/vB the total fee is large enough that no bump is needed.
    let commit_wu = 1096;
    let reveal_wu = 3040;
    let (commit_fee, reveal_fee) = split_package_fees(commit_wu, reveal_wu, 2.0, 1.0);

    let commit_vbytes = commit_wu.div_ceil(4);
    let reveal_vbytes = reveal_wu.div_ceil(4);
    let total_vbytes = commit_vbytes + reveal_vbytes;
    let expected_total = (total_vbytes as f64 * 2.0).ceil() as u64;
    let expected_commit = ((commit_vbytes as f64 * 1.0).ceil() as u64).max(1) + 1;

    assert_eq!(commit_fee, expected_commit);
    assert_eq!(reveal_fee, expected_total - expected_commit);
    // reveal_fee should already meet the minimum without bump.
    assert!(reveal_fee >= reveal_vbytes);
}

#[test]
fn split_package_fees_zero_rate_still_valid() {
    // Even with 0.0 fee rate, reveal_fee must meet minimum relay.
    let commit_wu = 1096;
    let reveal_wu = 3040;
    let (_commit_fee, reveal_fee) = split_package_fees(commit_wu, reveal_wu, 0.0, 1.0);

    let reveal_vbytes = reveal_wu.div_ceil(4);
    assert!(
        reveal_fee >= reveal_vbytes,
        "reveal_fee {} < min relay {}",
        reveal_fee,
        reveal_vbytes
    );
}

// ---------------------------------------------------------------------------
// Reveal detection: tell a real TX_REVEAL apart from a change-spend
// ---------------------------------------------------------------------------

fn dummy_input(witness: Witness) -> TxIn {
    TxIn {
        previous_output: OutPoint::null(),
        script_sig: ScriptBuf::default(),
        sequence: Sequence::ENABLE_RBF_NO_LOCKTIME,
        witness,
    }
}

fn tx_with_input(witness: Witness) -> Transaction {
    Transaction {
        version: bdk_wallet::bitcoin::transaction::Version(2),
        lock_time: LockTime::ZERO,
        input: vec![dummy_input(witness)],
        output: vec![],
    }
}

#[test]
fn tx_has_inscription_envelope_detects_real_reveal() {
    // A reveal's vault input is a script-path spend: witness =
    // [tapscript_envelope, control_block]. The envelope wraps zstd-compressed
    // bytes, matching what extract_raw_from_tapscript expects.
    let payload = zstd_compress(b"{\"descriptor\":\"tr(...)\"}");
    let tapscript = vault_tapscript(&payload);
    let mut control_block = vec![0xc0u8]; // leaf version | parity
    control_block.extend_from_slice(&[0u8; 32]); // internal key x-only
    let witness = Witness::from_slice(&[tapscript.as_bytes(), control_block.as_slice()]);

    assert!(tx_has_inscription_envelope(&tx_with_input(witness)));
}

#[test]
fn tx_has_inscription_envelope_rejects_change_spend() {
    // A plain key-path spend (e.g. spending the commit's change output) has a
    // single witness element and no script-path control block.
    let witness = Witness::from_slice(&[[0x01u8; 64]]);
    assert!(!tx_has_inscription_envelope(&tx_with_input(witness)));
}

#[test]
fn tx_has_inscription_envelope_rejects_non_taproot_control_block() {
    // Two witness elements but the last is not a taproot control block
    // (first byte != 0xc0/0xc1), e.g. a P2WSH multisig spend.
    let witness = Witness::from_slice(&[[0x30u8; 71].as_slice(), &[0x52u8, 0x21]]);
    assert!(!tx_has_inscription_envelope(&tx_with_input(witness)));
}

// ---------------------------------------------------------------------------
// Integration: replicate check_backup_health against live signet.
// Requires network. Run with: cargo test --lib check_backup_health_signet -- --ignored --nocapture
// ---------------------------------------------------------------------------

#[test]
#[ignore]
fn check_backup_health_signet_complex_multipath() {
    use bdk_electrum::electrum_client::ElectrumApi;
    use bdk_wallet::bitcoin::bip32::Xpub;
    use bdk_wallet::bitcoin::{Network, ScriptBuf};
    use std::collections::HashSet;
    use std::str::FromStr as _;

    let descriptor = "tr(tpubD6NzVbkrYhZ4XrnSGVhdFaTQhftAEKC7tEXQCsV73DBCwBzLQFXSFH6DHjJicwtJPMRyA8wu5XAo9qvUE1JeTGwYFeuVtrQ5Rp3Fk2hhPtP/<0;1>/*,{{and_v(v:pk([6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<0;1>/*),pk([dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<0;1>/*)),{and_v(v:multi_a(2,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<2;3>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<2;3>/*,[e4d0e6ca/48'/1'/0'/2']tpubDEk2ocixY8gJr4Xxo838JABCuNVg4Ybq82e1zAUikd2GQkNujboMcCVae9LFJeUHfGupQHRkJxDzi5XtpDwB1oDAdrEhHjhywMnq19kgjkR/<0;1>/*),older(6)),and_v(v:multi_a(2,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<4;5>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<4;5>/*,[e8b5d6bc/48'/1'/0'/2']tpubDF1uPjUDidqLh15zq1t2GYBGpfsbaiw52v4cNmBnPrUQUpRXKjWAczn5HTbnGD339UUFYKYkgHDkaUi2VrfF8W7dsYmBQMawkVTnHcFSjcz/<0;1>/*),older(6))}},{and_v(v:multi_a(2,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<6;7>/*,[c98cc679/48'/1'/0'/2']tpubDFDZZTwBjF5LTjAo6M5UmxugwHCZKcWYZ4t3Djf5rE3fXuY2mg5WUf4yvktnbP88nHf8BZvQBq9igncbQhdU7HxEeWRv9T3YbmU2NfbmUPL/<0;1>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<6;7>/*),older(6)),{and_v(v:multi_a(1,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<8;9>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<8;9>/*),older(12)),and_v(v:multi_a(1,[c98cc679/48'/1'/0'/2']tpubDFDZZTwBjF5LTjAo6M5UmxugwHCZKcWYZ4t3Djf5rE3fXuY2mg5WUf4yvktnbP88nHf8BZvQBq9igncbQhdU7HxEeWRv9T3YbmU2NfbmUPL/<2;3>/*,[e4d0e6ca/48'/1'/0'/2']tpubDEk2ocixY8gJr4Xxo838JABCuNVg4Ybq82e1zAUikd2GQkNujboMcCVae9LFJeUHfGupQHRkJxDzi5XtpDwB1oDAdrEhHjhywMnq19kgjkR/<2;3>/*,[e8b5d6bc/48'/1'/0'/2']tpubDF1uPjUDidqLh15zq1t2GYBGpfsbaiw52v4cNmBnPrUQUpRXKjWAczn5HTbnGD339UUFYKYkgHDkaUi2VrfF8W7dsYmBQMawkVTnHcFSjcz/<2;3>/*),older(18))}}})#qc5f98nd";
    let network = Network::Signet;
    let electrum_url = "ssl://mempool.space:60602";

    let secp = bdk_wallet::bitcoin::secp256k1::Secp256k1::new();
    let triples = participant_triples(descriptor);
    let n = triples.len();
    println!("participants: {n}");
    assert!(n > 0);

    let wallet_first_addr_hash = crate::api::wallet::discovery::first_address_from_descriptor(
        descriptor.to_string(),
        crate::api::model::APINetwork::Signet,
    )
    .map(crate::api::wallet::discovery::sha256_hex)
    .unwrap_or_default();
    println!("wallet_first_addr_hash: {wallet_first_addr_hash:?}");

    let anchor_spks: Vec<ScriptBuf> = triples
        .iter()
        .map(|(_, xpub, _)| {
            let x = Xpub::from_str(xpub).unwrap();
            let k = derive_anchor_key(&secp, &x);
            anchor_p2tr_address(&secp, &k, network).script_pubkey()
        })
        .collect();

    let client = crate::api::wallet::create_raw_electrum_client(electrum_url).unwrap();

    let anchor_histories: Vec<Vec<_>> = anchor_spks
        .iter()
        .map(|spk| {
            client
                .script_get_history(spk.as_script())
                .unwrap_or_default()
        })
        .collect();
    for (i, h) in anchor_histories.iter().enumerate() {
        println!("anchor {i}: {} history entries", h.len());
    }

    let mut seen: HashSet<bdk_wallet::bitcoin::Txid> = HashSet::new();
    let mut candidates: Vec<(bdk_wallet::bitcoin::Txid, i32)> = Vec::new();
    for history in &anchor_histories {
        for item in history {
            if seen.insert(item.tx_hash) {
                candidates.push((item.tx_hash, item.height));
            }
        }
    }
    println!("candidates: {}", candidates.len());
    let height_key = |h: i32| if h <= 0 { i64::MAX } else { h as i64 };
    candidates.sort_by_key(|c| std::cmp::Reverse(height_key(c.1)));

    let mut found = false;
    for (txid, height) in &candidates {
        let tx = match client.transaction_get(txid) {
            Ok(tx) => tx,
            Err(_) => continue,
        };
        let out_spks: HashSet<&ScriptBuf> = tx.output.iter().map(|o| &o.script_pubkey).collect();
        let all_anchors = anchor_spks.iter().all(|spk| out_spks.contains(spk));
        println!("candidate {txid} (h={height}): all_anchors={all_anchors}");
        if !all_anchors {
            continue;
        }
        match find_reveal_tx_for_commit(&client, &tx, *txid, &anchor_spks) {
            Some((rtxid, rtx, _)) => {
                println!("  reveal found: {rtxid}");
                let verified = !wallet_first_addr_hash.is_empty()
                    && triples.iter().any(|(_, xpub, _)| {
                        extract_descriptor_from_reveal(&rtx, xpub)
                            .ok()
                            .map(|(d, _, _)| {
                                let rh =
                                    crate::api::wallet::discovery::first_address_from_descriptor(
                                        d.clone(),
                                        crate::api::model::APINetwork::Signet,
                                    )
                                    .map(crate::api::wallet::discovery::sha256_hex)
                                    .unwrap_or_default();
                                !rh.is_empty() && rh == wallet_first_addr_hash
                            })
                            .unwrap_or(false)
                    });
                println!("  descriptor_verified: {verified}");
                if verified {
                    found = true;
                    break;
                }
            }
            None => println!("  reveal NOT found"),
        }
    }
    println!("FINAL found = {found}");
    assert!(found, "check_backup_health logic did not detect the backup");
}
