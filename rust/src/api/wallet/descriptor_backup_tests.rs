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
        assert!(commit_weight(1, n) > 0);
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
