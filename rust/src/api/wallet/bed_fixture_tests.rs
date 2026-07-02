use super::*;

#[test]
fn generate_all_fixtures() {
    write_all_bed_fixtures();

    for name in ["singlesig", "multisig_2of3", "taproot_tr"] {
        let data = get_fixture(name);
        assert!(!data.is_empty(), "{} must not be empty", name);
        assert_eq!(
            &data[0..4],
            b"BEB\x01",
            "{} must start with BEB magic",
            name
        );
    }
}

#[test]
fn fixture_singlesig_roundtrip() {
    let bytes = get_fixture("singlesig");
    let pk = dpk_to_pk_str(FIXTPUB);

    let decrypted = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("set_encrypted_payload ok")
        .set_keys(vec![pk])
        .decrypt()
        .expect("decrypt with correct key");

    match decrypted {
        bitcoin_encrypted_backup::Decrypted::Descriptor(d) => {
            assert_eq!(d.to_string(), singlesig_desc().to_string());
        }
        other => panic!("expected Descriptor, got {:?}", other),
    }
}

#[test]
fn fixture_multisig_roundtrip() {
    let bytes = get_fixture("multisig_2of3");
    let pk = dpk_to_pk_str(FIXTPUB);

    let decrypted = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("set_encrypted_payload ok")
        .set_keys(vec![pk])
        .decrypt()
        .expect("decrypt with correct key");

    match decrypted {
        bitcoin_encrypted_backup::Decrypted::Descriptor(d) => {
            assert_eq!(d.to_string(), multisig_desc().to_string());
        }
        other => panic!("expected Descriptor, got {:?}", other),
    }
}

#[test]
fn fixture_taproot_roundtrip() {
    let bytes = get_fixture("taproot_tr");
    let pk = dpk_to_pk_str(FIXTPUB);

    let decrypted = EncryptedBackup::new()
        .set_encrypted_payload(&bytes)
        .expect("set_encrypted_payload ok")
        .set_keys(vec![pk])
        .decrypt()
        .expect("decrypt with correct key");

    match decrypted {
        bitcoin_encrypted_backup::Decrypted::Descriptor(d) => {
            assert_eq!(d.to_string(), taproot_desc().to_string());
        }
        other => panic!("expected Descriptor, got {:?}", other),
    }
}

#[test]
fn fixture_wrong_key_fails() {
    let secp = bitcoin_encrypted_backup::miniscript::bitcoin::secp256k1::Secp256k1::new();
    let (_, wrong_pk) = secp.generate_keypair(
        &mut bitcoin_encrypted_backup::miniscript::bitcoin::secp256k1::rand::thread_rng(),
    );

    for name in ["singlesig", "multisig_2of3", "taproot_tr"] {
        let bytes = get_fixture(name);
        let result = EncryptedBackup::new()
            .set_encrypted_payload(&bytes)
            .expect("set_encrypted_payload ok")
            .set_keys(vec![wrong_pk])
            .decrypt();

        assert!(result.is_err(), "{} should fail with wrong key", name);
    }
}
