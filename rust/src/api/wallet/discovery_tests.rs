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
