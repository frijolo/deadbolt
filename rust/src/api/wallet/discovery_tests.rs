use super::*;

/// Regression: derive_xpubs_for_nostr must include the BIP48 P2WSH xpub
/// at m/48'/1'/0'/2' (signet) for the known test seed.
///
/// Seed:    piece blue stadium control fiction kick group mimic hollow dog mask interest
/// Network: Signet  (coin = 1)
/// Path:    m/48'/1'/0'/2'
/// Expected xpub: tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K
///
/// Note: derive_xpubs_for_nostr also covers script_types 1 (P2SH-P2WSH),
/// 3 (P2TR), 4 (P2WSH-P2SH nested), and 9 (Miniscript/Liana).
#[test]
fn derive_xpubs_for_nostr_includes_bip48_p2wsh_signet() {
    let mnemonic =
        "piece blue stadium control fiction kick group mimic hollow dog mask interest".to_string();
    let xpubs =
        derive_xpubs_for_nostr(mnemonic, None, crate::api::model::APINetwork::Signet, 1).unwrap();

    let expected = "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K";
    assert!(
        xpubs.contains(&expected.to_string()),
        "BIP48 P2WSH xpub not found.\nExpected: {expected}\nGot: {xpubs:#?}"
    );
}

/// Regression: first_address_from_descriptor must derive the index-0 external
/// address for a complex taproot miniscript descriptor whose keys use different
/// multipath index pairs (<0;1>, <2;3>, <4;5>, ...). This is the
/// `descriptor_verified` check in check_backup_health; if BDK failed to derive
/// the address the on-chain backup would never be detected.
#[test]
fn first_address_complex_multipath_tr() {
    let descriptor = "tr(tpubD6NzVbkrYhZ4XrnSGVhdFaTQhftAEKC7tEXQCsV73DBCwBzLQFXSFH6DHjJicwtJPMRyA8wu5XAo9qvUE1JeTGwYFeuVtrQ5Rp3Fk2hhPtP/<0;1>/*,{{and_v(v:pk([6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<0;1>/*),pk([dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<0;1>/*)),{and_v(v:multi_a(2,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<2;3>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<2;3>/*,[e4d0e6ca/48'/1'/0'/2']tpubDEk2ocixY8gJr4Xxo838JABCuNVg4Ybq82e1zAUikd2GQkNujboMcCVae9LFJeUHfGupQHRkJxDzi5XtpDwB1oDAdrEhHjhywMnq19kgjkR/<0;1>/*),older(6)),and_v(v:multi_a(2,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<4;5>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<4;5>/*,[e8b5d6bc/48'/1'/0'/2']tpubDF1uPjUDidqLh15zq1t2GYBGpfsbaiw52v4cNmBnPrUQUpRXKjWAczn5HTbnGD339UUFYKYkgHDkaUi2VrfF8W7dsYmBQMawkVTnHcFSjcz/<0;1>/*),older(6))}},{and_v(v:multi_a(2,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<6;7>/*,[c98cc679/48'/1'/0'/2']tpubDFDZZTwBjF5LTjAo6M5UmxugwHCZKcWYZ4t3Djf5rE3fXuY2mg5WUf4yvktnbP88nHf8BZvQBq9igncbQhdU7HxEeWRv9T3YbmU2NfbmUPL/<0;1>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<6;7>/*),older(6)),{and_v(v:multi_a(1,[6127dfd4/48'/1'/0'/2']tpubDFeh3tp6XM2T4yEpADjkjjojHrL5p9grqbK6Jsd61PTTrdTFnXtCXfgQRYhRm6H5mfA1iW2iFi9Q75QP3pjfLNUigcN2FbJpD1kqeJ6jKx8/<8;9>/*,[dec4f854/48'/1'/0'/2']tpubDFJNw2VNTEjdoBDNzPMjUKyVG4Z6eeKSeQAgyxfyCfk55xqwHqbGXVXnmVbrzYVWQpPwGVuHqkTDwrc2hCnX7bjXcdwQ4P3Vr62iShcjQ52/<8;9>/*),older(12)),and_v(v:multi_a(1,[c98cc679/48'/1'/0'/2']tpubDFDZZTwBjF5LTjAo6M5UmxugwHCZKcWYZ4t3Djf5rE3fXuY2mg5WUf4yvktnbP88nHf8BZvQBq9igncbQhdU7HxEeWRv9T3YbmU2NfbmUPL/<2;3>/*,[e4d0e6ca/48'/1'/0'/2']tpubDEk2ocixY8gJr4Xxo838JABCuNVg4Ybq82e1zAUikd2GQkNujboMcCVae9LFJeUHfGupQHRkJxDzi5XtpDwB1oDAdrEhHjhywMnq19kgjkR/<2;3>/*,[e8b5d6bc/48'/1'/0'/2']tpubDF1uPjUDidqLh15zq1t2GYBGpfsbaiw52v4cNmBnPrUQUpRXKjWAczn5HTbnGD339UUFYKYkgHDkaUi2VrfF8W7dsYmBQMawkVTnHcFSjcz/<2;3>/*),older(18))}}})#qc5f98nd";
    let res = first_address_from_descriptor(
        descriptor.to_string(),
        crate::api::model::APINetwork::Signet,
    );
    let expected = "tb1pz5trpkjg7jeh28f44ryjf4d3zj5z87pysekqampyysck9wrjx4zq37xfzn";
    assert_eq!(res.expect("first_address_from_descriptor failed"), expected);
}
