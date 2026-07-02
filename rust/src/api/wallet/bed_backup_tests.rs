// ---------------------------------------------------------------------------
// BED (Bitcoin Encrypted Descriptor) backup — unit tests
// ---------------------------------------------------------------------------

use bitcoin_encrypted_backup::{
    miniscript::{
        bitcoin::{hashes::Hash, secp256k1},
        Descriptor, DescriptorPublicKey,
    },
    Decrypted, EncryptedBackup,
};
use core::str::FromStr;

// Real testnet xpub from the bitcoin-encrypted-backup crate tests
// Used in the descriptor below for byte-level interop with the crate's own tests
#[allow(dead_code)]
const TESTXPUB: &str =
    "tpubDEPBvXvhta3pjVaKokqC3eeMQnszj9ehFaA2zD5nSdkaccwGAizu8jVB2NeSpvmP2P52MBoZvNCixqXRJnTyXx51FQzARR63tjxQSyP3Btw";

// Wrong key for failure tests — a different valid pubkey (NUMS point from BIP341)
fn wrong_pk() -> secp256k1::PublicKey {
    secp256k1::PublicKey::from_str(
        "0250929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0",
    )
    .expect("valid NUMS pubkey")
}

fn make_nonce(seed: &[u8]) -> [u8; 12] {
    let hash = bitcoin_encrypted_backup::miniscript::bitcoin::hashes::sha256::Hash::hash(seed);
    let bytes = hash.to_byte_array();
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&bytes[..12]);
    nonce
}

fn multipath_single_key() -> Descriptor<DescriptorPublicKey> {
    // EXACT same descriptor as the crate's descr_1() test
    let desc_str = "wsh(or_d(pk([58b7f8dc/48'/1'/0'/2']tpubDEPBvXvhta3pjVaKokqC3eeMQnszj9ehFaA2zD5nSdkaccwGAizu8jVB2NeSpvmP2P52MBoZvNCixqXRJnTyXx51FQzARR63tjxQSyP3Btw/<0;1>/*),and_v(v:pkh([58b7f8dc/48'/1'/0'/2']tpubDEPBvXvhta3pjVaKokqC3eeMQnszj9ehFaA2zD5nSdkaccwGAizu8jVB2NeSpvmP2P52MBoZvNCixqXRJnTyXx51FQzARR63tjxQSyP3Btw/<2;3>/*),older(52596))))#pggrcdd0";
    Descriptor::from_str(desc_str).expect("valid test descriptor from crate")
}

fn dummy_pubkey() -> secp256k1::PublicKey {
    // Real pubkey that matches the xpub's internal key
    secp256k1::PublicKey::from_slice(&[
        0x03, 0xEB, 0xD2, 0x52, 0xCA, 0x08, 0x77, 0xAA, 0xE0, 0x9B, 0x9D, 0x05, 0x82, 0x19, 0x68,
        0x27, 0x75, 0xAA, 0x3C, 0xBC, 0xD0, 0x49, 0xC1, 0x2F, 0x07, 0x83, 0x2F, 0x2C, 0xF6, 0xA3,
        0xB5, 0x17, 0x08,
    ])
    .expect("valid pubkey bytes")
}

#[test]
fn test_roundtrip_single_key() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let keys = backup.get_keys();
    assert!(!keys.is_empty(), "should have at least one public key");

    let nonce = make_nonce(b"nonce1");
    let bytes = backup.encrypt(nonce).expect("encryption should succeed");
    assert!(!bytes.is_empty());
    assert_eq!(&bytes[..3], b"BEB", "magic must be BEB");

    let restored = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("set_encrypted_payload should succeed")
        .set_keys(keys.clone())
        .decrypt()
        .expect("decrypt should succeed");

    match restored {
        Decrypted::Descriptor(d) => assert_eq!(d, descriptor),
        other => panic!("expected Decrypted::Descriptor, got {:?}", other),
    }
}

#[test]
fn test_roundtrip_decrypt_with_each_key() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let keys = backup.get_keys();

    let nonce = make_nonce(b"nonce2");
    let bytes = backup.encrypt(nonce).expect("encryption should succeed");

    for (i, key) in keys.iter().enumerate() {
        let restored = EncryptedBackup::new()
            .set_encrypted_payload(&bytes)
            .expect("set_encrypted_payload should succeed")
            .set_keys(vec![*key])
            .decrypt()
            .unwrap_or_else(|e| panic!("decrypt with key {} should succeed: {:?}", i, e));

        match restored {
            Decrypted::Descriptor(d) => assert_eq!(d, descriptor),
            other => panic!("key {}: expected Descriptor, got {:?}", i, other),
        }
    }
}

#[test]
fn test_wrong_key_fails() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let keys = backup.get_keys();
    assert!(!keys.is_empty());

    let nonce = make_nonce(b"nonce3");
    let bytes = backup.encrypt(nonce).expect("encryption should succeed");

    let wrong_pk = wrong_pk();

    let result = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("parse should succeed")
        .set_keys(vec![wrong_pk])
        .decrypt();

    assert!(result.is_err(), "decrypt with wrong key should fail");
    assert_eq!(
        result.unwrap_err(),
        bitcoin_encrypted_backup::Error::WrongKey
    );
}

#[test]
fn test_no_key_fails() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let _keys = backup.get_keys();
    let nonce = make_nonce(b"nonce4");
    let bytes = backup.encrypt(nonce).expect("encryption should succeed");

    let result = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("parse should succeed")
        .decrypt();

    assert!(result.is_err(), "decrypt without keys should fail");
    assert_eq!(result.unwrap_err(), bitcoin_encrypted_backup::Error::NoKey);
}

#[test]
fn test_content_type_bip380() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    use bitcoin_encrypted_backup::Content;
    assert_eq!(backup.get_content(), Content::Bip380);
}

#[test]
fn test_raw_bytes_payload() {
    let payload = vec![0xDE, 0xAD, 0xBE, 0xEF];
    let mut backup = EncryptedBackup::new()
        .set_payload(&payload)
        .expect("set_payload should succeed");

    let key = dummy_pubkey();
    backup = backup.set_keys(vec![key]);

    let result = backup.clone().encrypt(make_nonce(b"nonce5"));
    assert!(result.is_err(), "encrypt without content type should fail");

    use bitcoin_encrypted_backup::Content;
    backup = backup.set_content_type(Content::None);
    let bytes = backup
        .encrypt(make_nonce(b"nonce6"))
        .expect("encrypt should succeed");

    let result = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("parse should succeed")
        .decrypt();
    assert!(result.is_err());

    let restored = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("parse should succeed")
        .set_keys(vec![key])
        .decrypt()
        .expect("decrypt should succeed");

    match restored {
        Decrypted::Raw(data) => assert_eq!(data, payload),
        other => panic!("expected Raw, got {:?}", other),
    }
}

#[test]
fn test_version_and_encryption() {
    use bitcoin_encrypted_backup::{Encryption, Version};

    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    assert_eq!(backup.get_version(), Version::V0);
    assert_eq!(backup.get_encryption(), Encryption::AesGcm256);

    let backup = backup.set_version(Version::V1);
    assert_eq!(backup.get_version(), Version::V1);
}

#[test]
fn test_magic_header() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let _keys = backup.get_keys();
    let nonce = make_nonce(b"nonce7");
    let bytes = backup.encrypt(nonce).expect("encrypt should succeed");

    assert_eq!(&bytes[..3], b"BEB", "magic header must be BEB");
    assert_eq!(bytes[3], 0x01, "version byte must be 0x01 (V1)");
}

#[test]
fn test_derivation_paths_extracted() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let paths = backup.get_derivation_paths();
    assert!(
        !paths.is_empty(),
        "should have at least one derivation path"
    );

    for path in &paths {
        let segments = path.to_u32_vec();
        assert!(!segments.is_empty(), "path segments should not be empty");
    }
}

#[test]
fn test_encrypt_empty_fails() {
    let mut backup = EncryptedBackup::new()
        .set_payload(&Vec::<u8>::new())
        .expect("set_payload should succeed");
    use bitcoin_encrypted_backup::Content;
    backup = backup.set_content_type(Content::None);

    let result = backup.encrypt(make_nonce(b"nonce8"));
    assert!(result.is_err(), "encrypt with empty data should fail");
}

#[test]
fn test_encrypt_no_keys_fails() {
    let mut backup = EncryptedBackup::new()
        .set_payload(&vec![0x42u8])
        .expect("set_payload should succeed");
    use bitcoin_encrypted_backup::Content;
    backup = backup.set_content_type(Content::None);

    let result = backup.encrypt(make_nonce(b"nonce9"));
    assert!(result.is_err(), "encrypt without keys should fail");
}

#[test]
fn test_multiple_encryption_rounds() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let keys = backup.get_keys();
    let mut first_bytes: Option<Vec<u8>> = None;

    for round in 0..3u8 {
        let nonce = make_nonce(&[round]);
        let bytes = backup
            .clone()
            .encrypt(nonce)
            .expect("encrypt should succeed");

        if let Some(ref first) = first_bytes {
            assert_ne!(
                bytes[..],
                first[..],
                "different nonces produce different blobs"
            );
        }
        first_bytes = Some(bytes.clone());

        let restored = EncryptedBackup::new()
            .set_encrypted_payload(&bytes)
            .expect("parse should succeed")
            .set_keys(keys.clone())
            .decrypt()
            .expect("decrypt should succeed");

        match restored {
            Decrypted::Descriptor(d) => assert_eq!(d, descriptor),
            other => panic!("expected Descriptor, got {:?}", other),
        }
    }
}

#[test]
fn test_tampered_ciphertext_fails() {
    let descriptor = multipath_single_key();
    let backup = EncryptedBackup::new()
        .set_payload(&descriptor)
        .expect("set_payload should succeed");

    let keys = backup.get_keys();
    let nonce = make_nonce(b"nonce10");
    let mut bytes = backup.encrypt(nonce).expect("encrypt should succeed");

    // Tamper with a byte in the middle
    let mid = bytes.len() / 2;
    bytes[mid] ^= 0xFF;

    let result = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("parse should succeed")
        .set_keys(keys)
        .decrypt();

    assert!(result.is_err(), "tampered ciphertext should fail");
}

#[test]
fn test_decode_magic() {
    use bitcoin_encrypted_backup::ll::parse_magic_byte;

    assert!(parse_magic_byte(b"BEB\x01").is_ok());
    assert!(parse_magic_byte(b"XYZ\x01").is_err());
    assert!(parse_magic_byte(b"BE").is_err());
}

#[test]
fn test_xor() {
    use bitcoin_encrypted_backup::ll::xor;

    let a = [1u8; 32];
    let b = [2u8; 32];
    let result = xor(&a, &b);

    for byte in result {
        assert_eq!(byte, 3u8, "1 XOR 2 = 3");
    }

    let zero = xor(&a, &a);
    assert!(zero.iter().all(|&b| b == 0));
}
