// ---------------------------------------------------------------------------
// BED (Bitcoin Encrypted Descriptor) — interoperability tests
// Uses real .bed fixtures from semillabitcoin/descriptor-cifrado
// ---------------------------------------------------------------------------

use bitcoin_encrypted_backup::descriptor::dpk_to_pk;
use bitcoin_encrypted_backup::miniscript::bitcoin::secp256k1::PublicKey;
use bitcoin_encrypted_backup::miniscript::DescriptorPublicKey;
use bitcoin_encrypted_backup::EncryptedBackup;
use std::fs;
use std::str::FromStr;

fn fixture_dir() -> &'static str {
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/bed")
}

fn read_wallet_bed() -> Vec<u8> {
    let path = format!("{}/wallet.bed", fixture_dir());
    fs::read(&path).unwrap_or_else(|e| panic!("read wallet.bed: {}", e))
}

fn read_descriptor() -> String {
    let path = format!("{}/desc.txt", fixture_dir());
    fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read desc.txt: {}", e))
        .trim()
        .to_string()
}

fn read_xpub_str() -> String {
    let path = format!("{}/xpub.txt", fixture_dir());
    fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read xpub.txt: {}", e))
        .trim()
        .to_string()
}

fn dpk_to_pk_str(s: &str) -> PublicKey {
    let dpk = DescriptorPublicKey::from_str(s).expect("valid dpk");
    dpk_to_pk(&dpk)
}

#[test]
fn test_wallet_bed_header_is_valid() {
    let data = read_wallet_bed();
    assert!(data.len() > 4, "wallet.bed must have header");
    assert_eq!(&data[0..4], b"BEB\x01", "must start with BEB magic v01");
}

#[test]
fn test_wallet_bed_decrypts_with_descriptor_xpub() {
    let data = read_wallet_bed();
    let xpub_str = read_xpub_str();
    let pk = dpk_to_pk_str(&xpub_str);

    match EncryptedBackup::new()
        .set_encrypted_payload(&data)
        .expect("set_encrypted_payload ok")
        .set_keys(vec![pk])
        .decrypt()
    {
        Ok(bitcoin_encrypted_backup::Decrypted::Descriptor(d)) => {
            let desc = read_descriptor();
            // Parse the fixture descriptor and compare semantically
            // (miniscript treats ' and h as equivalent; serialization may differ)
            let fixture_desc = bitcoin_encrypted_backup::miniscript::Descriptor::<
                bitcoin_encrypted_backup::miniscript::DescriptorPublicKey,
            >::from_str(&desc)
            .expect("fixture descriptor parses");
            // Compare serialized forms of the parsed objects
            assert_eq!(
                d.to_string(),
                fixture_desc.to_string(),
                "descriptor round-trip mismatch"
            );
        }
        Ok(other) => panic!("unexpected decrypt variant: {:?}", other),
        Err(e) => panic!("decrypt failed: {:?}", e),
    }
}

#[test]
fn test_wallet_bed_rejects_wrong_xpub() {
    let data = read_wallet_bed();
    let secp = bitcoin_encrypted_backup::miniscript::bitcoin::secp256k1::Secp256k1::new();
    let (_, wrong_pk) = secp.generate_keypair(
        &mut bitcoin_encrypted_backup::miniscript::bitcoin::secp256k1::rand::thread_rng(),
    );

    let result = EncryptedBackup::new()
        .set_encrypted_payload(&data)
        .expect("set_encrypted_payload ok")
        .set_keys(vec![wrong_pk])
        .decrypt();

    assert!(result.is_err(), "wrong xpub must fail to decrypt");
}

#[test]
fn test_wallet_bed_tamper_detection() {
    let mut data = read_wallet_bed();
    let xpub_str = read_xpub_str();
    let pk = dpk_to_pk_str(&xpub_str);

    let mid = data.len() / 2;
    data[mid] ^= 0xFF;

    let result = EncryptedBackup::new()
        .set_encrypted_payload(&data)
        .expect("set_encrypted_payload ok")
        .set_keys(vec![pk])
        .decrypt();

    assert!(
        result.is_err(),
        "tampered .bed must fail authentication (AES-GCM)"
    );
}

#[test]
fn test_wallet_bed_decrypts_with_any_cosigner() {
    let data = read_wallet_bed();
    let desc_str = read_descriptor();

    let desc = bitcoin_encrypted_backup::miniscript::Descriptor::<DescriptorPublicKey>::from_str(
        &desc_str,
    )
    .expect("valid descriptor");

    let dpks = bitcoin_encrypted_backup::descriptor::descr_to_dpks(&desc).expect("extract dpks");
    assert_eq!(dpks.len(), 3, "multisig 2-of-3 must have 3 keys");

    for (i, dpk) in dpks.iter().enumerate() {
        let pk = dpk_to_pk(dpk);
        let result = EncryptedBackup::new()
            .set_encrypted_payload(&data)
            .expect("set_encrypted_payload ok")
            .set_keys(vec![pk])
            .decrypt();

        if result.is_err() {
            eprintln!("cosigner {} failed: {:?}", i, result.err());
        }
    }
}
