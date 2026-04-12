use super::{sign_bip322_descriptor_with_xprv, verify_bip322_descriptor_sig};
use crate::core::seed::mnemonic_to_root_xprv;
use anyhow::Result;
use bdk_wallet::bitcoin::{
    bip32::{DerivationPath, Xpub},
    secp256k1::Secp256k1,
    Network,
};
use std::str::FromStr;

// BIP39 test vector mnemonic (24 words, no passphrase) — not used for real funds.
const TEST_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon \
     abandon abandon abandon abandon abandon abandon abandon abandon \
     abandon abandon abandon abandon abandon abandon abandon art";

fn root_xprv() -> bdk_wallet::bitcoin::bip32::Xpriv {
    mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).expect("valid test mnemonic")
}

fn xpub_entry_for_path(path_str: &str) -> String {
    let root = root_xprv();
    let secp = Secp256k1::new();
    let path = DerivationPath::from_str(path_str).unwrap();
    let account_xprv = root.derive_priv(&secp, &path).unwrap();
    let account_xpub = Xpub::from_priv(&secp, &account_xprv);
    let mfp = root.fingerprint(&secp);
    let path_part = path_str.trim_start_matches("m/");
    format!("[{mfp}/{path_part}]{account_xpub}")
}

#[test]
fn sign_and_verify_roundtrip_m48() -> Result<()> {
    let xpub_entry = xpub_entry_for_path("m/48'/1'/0'/2'");
    let message = "Ownership proof — m/48'";
    let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, message, &root_xprv())?;
    let pubkey = verify_bip322_descriptor_sig(&xpub_entry, message, &sig)?;
    assert!(!pubkey.is_empty());
    Ok(())
}

#[test]
fn sign_and_verify_roundtrip_m84() -> Result<()> {
    let xpub_entry = xpub_entry_for_path("m/84'/1'/0'");
    let message = "Ownership proof — m/84'";
    let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, message, &root_xprv())?;
    let pubkey = verify_bip322_descriptor_sig(&xpub_entry, message, &sig)?;
    assert!(!pubkey.is_empty());
    Ok(())
}

#[test]
fn wrong_message_fails_verification() -> Result<()> {
    let xpub_entry = xpub_entry_for_path("m/84'/1'/0'");
    let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, "correct message", &root_xprv())?;
    assert!(verify_bip322_descriptor_sig(&xpub_entry, "wrong message", &sig).is_err());
    Ok(())
}

#[test]
fn wrong_xpub_fails_verification() -> Result<()> {
    let xpub_entry = xpub_entry_for_path("m/84'/1'/0'");
    let other_xpub_entry = xpub_entry_for_path("m/49'/1'/0'");
    let message = "test message";
    let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, message, &root_xprv())?;
    assert!(verify_bip322_descriptor_sig(&other_xpub_entry, message, &sig).is_err());
    Ok(())
}
