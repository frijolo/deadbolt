// ---------------------------------------------------------------------------
// BED (Bitcoin Encrypted Descriptor) backup — fixture generators
// Generates real .bed files from the official bitcoin-encrypted-backup crate.
// Run: cargo test bed_fixture::tests::generate_all_fixtures
// ---------------------------------------------------------------------------

use bitcoin_encrypted_backup::descriptor::dpk_to_pk;
use bitcoin_encrypted_backup::miniscript::bitcoin::secp256k1::PublicKey;
use bitcoin_encrypted_backup::miniscript::{
    bitcoin::hashes::Hash, Descriptor, DescriptorPublicKey,
};
use bitcoin_encrypted_backup::EncryptedBackup;
use std::fs;
use std::path::Path;
use std::str::FromStr;
use std::sync::LazyLock;

const FIXTPUB: &str =
    "tpubDEPBvXvhta3pjVaKokqC3eeMQnszj9ehFaA2zD5nSdkaccwGAizu8jVB2NeSpvmP2P52MBoZvNCixqXRJnTyXx51FQzARR63tjxQSyP3Btw";

/// Simple singlesig descriptor (single key)
fn singlesig_desc() -> Descriptor<DescriptorPublicKey> {
    let s = format!("wpkh([58b7f8dc/48'/1'/0'/2']{}/<0;1>/*)", FIXTPUB);
    Descriptor::from_str(&s).expect("valid singlesig descriptor")
}

/// Multisig 2-of-3 descriptor
fn multisig_desc() -> Descriptor<DescriptorPublicKey> {
    let s = format!(
        "wsh(sortedmulti(2,[58b7f8dc/48'/1'/0'/2']{}/<0;1>/*,[58b7f8dc/48'/1'/0'/2']{}/<0;1>/*,[58b7f8dc/48'/1'/0'/2']{}/<0;1>/*))",
        FIXTPUB, FIXTPUB, FIXTPUB
    );
    Descriptor::from_str(&s).expect("valid multisig descriptor")
}

/// Taproot descriptor
fn taproot_desc() -> Descriptor<DescriptorPublicKey> {
    let s = format!("tr([58b7f8dc/48'/1'/0'/2']{}/<0;1>/*)", FIXTPUB);
    Descriptor::from_str(&s).expect("valid taproot descriptor")
}

fn make_nonce(seed: &[u8]) -> [u8; 12] {
    let hash = bitcoin_encrypted_backup::miniscript::bitcoin::hashes::sha256::Hash::hash(seed);
    let bytes = hash.to_byte_array();
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&bytes[..12]);
    nonce
}

fn encrypt_descriptor(desc: &Descriptor<DescriptorPublicKey>, nonce: [u8; 12]) -> Vec<u8> {
    let backup = EncryptedBackup::new()
        .set_payload(desc)
        .expect("set_payload ok");
    backup.encrypt(nonce).expect("encrypt ok")
}

/// Pre-generated fixture data (computed once via OnceLock to avoid race conditions
/// when tests run in parallel).
static FIXTURES: LazyLock<Vec<(String, Vec<u8>)>> = LazyLock::new(|| {
    let pairs = [
        ("singlesig", singlesig_desc()),
        ("multisig_2of3", multisig_desc()),
        ("taproot_tr", taproot_desc()),
    ];
    pairs
        .iter()
        .map(|(name, desc)| {
            let nonce = make_nonce(name.as_bytes());
            let encrypted = encrypt_descriptor(desc, nonce);
            (name.to_string(), encrypted)
        })
        .collect()
});

fn dpk_to_pk_str(xpub_str: &str) -> PublicKey {
    let dpk = DescriptorPublicKey::from_str(xpub_str).expect("valid dpk");
    dpk_to_pk(&dpk)
}

/// Write all fixtures to disk (call once from test generation).
pub fn write_all_bed_fixtures() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/bed");
    let path = Path::new(dir);
    fs::create_dir_all(path).expect("create fixture dir");

    for (name, data) in FIXTURES.iter() {
        let file = path.join(format!("{}.bed", name));
        fs::write(&file, data).unwrap_or_else(|e| {
            panic!("write fixture {}: {}", file.display(), e);
        });
    }
}

/// Return pre-generated fixture data by name.
fn get_fixture(name: &str) -> Vec<u8> {
    FIXTURES
        .iter()
        .find(|(n, _)| n == name)
        .map(|(_, data)| data.clone())
        .unwrap_or_else(|| panic!("fixture {} not found", name))
}

#[cfg(test)]
#[path = "bed_fixture_tests.rs"]
mod tests;
