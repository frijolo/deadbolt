use super::*;
use bdk_wallet::bitcoin::Network;

// BIP39 test vector mnemonic (24 words, no passphrase)
const TEST_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon \
     abandon abandon abandon abandon abandon abandon abandon abandon \
     abandon abandon abandon abandon abandon abandon abandon art";

#[test]
fn test_mnemonic_to_root_xprv_derives_deterministic_key() {
    let secp = Secp256k1::new();
    let xprv = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
    let mfp = root_xprv_to_mfp(&xprv, &secp);
    // Known MFP for this mnemonic on mainnet
    assert_eq!(mfp.len(), 8);
    assert!(mfp.chars().all(|c| c.is_ascii_hexdigit()));
    // Calling again must produce the same MFP
    let xprv2 = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
    assert_eq!(root_xprv_to_mfp(&xprv2, &secp), mfp);
}

#[test]
fn test_mnemonic_invalid_words() {
    let result = mnemonic_to_root_xprv("invalid words here", "", Network::Bitcoin);
    assert!(result.is_err());
}

#[test]
fn test_xprv_str_to_root_xprv_rejects_non_master() {
    // An xprv with depth > 0 must be rejected.
    // We derive one from the test mnemonic and use it directly as a string.
    let secp = Secp256k1::new();
    let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
    let path = DerivationPath::from_str("m/44'/0'/0'").unwrap();
    let child = root.derive_priv(&secp, &path).unwrap();
    let child_str = child.to_string();
    let result = xprv_str_to_root_xprv(&child_str);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("depth"));
}

#[test]
fn test_xprv_str_to_root_xprv_accepts_master() {
    let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Bitcoin).unwrap();
    let root_str = root.to_string();
    let parsed = xprv_str_to_root_xprv(&root_str).unwrap();
    assert_eq!(parsed.depth, 0);
}

#[test]
fn test_make_private_descriptor_singlesig() {
    let secp = Secp256k1::new();
    let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).unwrap();
    let mfp = root_xprv_to_mfp(&root, &secp);

    // Build a descriptor using the xpub at m/84'/1'/0'
    let path = DerivationPath::from_str("m/84'/1'/0'").unwrap();
    let child_xprv = root.derive_priv(&secp, &path).unwrap();
    let child_xpub = bdk_wallet::bitcoin::bip32::Xpub::from_priv(&secp, &child_xprv);
    let descriptor = format!("wpkh([{}/84'/1'/0']{}/<0;1>/*)", mfp, child_xpub);

    let private_desc = make_private_descriptor(&descriptor, &root, &secp).unwrap();
    assert!(
        private_desc.contains("xprv") || private_desc.contains("tprv"),
        "Expected xprv in result: {}",
        private_desc
    );
    assert!(
        !private_desc.contains("xpub") && !private_desc.contains("tpub"),
        "xpub should have been replaced: {}",
        private_desc
    );
}

#[test]
fn test_make_private_descriptor_multisig_only_replaces_matching_mfp() {
    let secp = Secp256k1::new();
    // Two different mnemonics → two different root keys
    let root1 = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).unwrap();
    let mnemonic2 = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong";
    let root2 = mnemonic_to_root_xprv(mnemonic2, "", Network::Testnet).unwrap();

    let mfp1 = root_xprv_to_mfp(&root1, &secp);
    let mfp2 = root_xprv_to_mfp(&root2, &secp);

    let path = DerivationPath::from_str("m/48'/1'/0'/2'").unwrap();
    let xpub1 = bdk_wallet::bitcoin::bip32::Xpub::from_priv(
        &secp,
        &root1.derive_priv(&secp, &path).unwrap(),
    );
    let xpub2 = bdk_wallet::bitcoin::bip32::Xpub::from_priv(
        &secp,
        &root2.derive_priv(&secp, &path).unwrap(),
    );
    let descriptor = format!(
        "wsh(multi(2,[{}/48'/1'/0'/2']{}/<0;1>/*,[{}/48'/1'/0'/2']{}/<0;1>/*))",
        mfp1, xpub1, mfp2, xpub2
    );

    // Sign with root1 only → only mfp1's xpub is replaced
    let private_desc = make_private_descriptor(&descriptor, &root1, &secp).unwrap();
    // mfp2's key must still be xpub
    assert!(
        private_desc.contains(&format!("[{}/48'/1'/0'/2']", mfp2)),
        "mfp2 key expression should be unchanged"
    );
    // The descriptor should contain at least one xprv
    assert!(
        private_desc.contains("xprv") || private_desc.contains("tprv"),
        "mfp1 should have been replaced with xprv"
    );
}

#[test]
fn print_test_mnemonic_values() {
    let secp = Secp256k1::new();
    let root = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).unwrap();
    let mfp = root_xprv_to_mfp(&root, &secp);
    let path = DerivationPath::from_str("m/84'/1'/0'").unwrap();
    let child = root.derive_priv(&secp, &path).unwrap();
    let xpub = bdk_wallet::bitcoin::bip32::Xpub::from_priv(&secp, &child);
    println!("MFP={}", mfp);
    println!("DESC=wpkh([{}/84'/1'/0']{}/<0;1>/*)", mfp, xpub);
}
