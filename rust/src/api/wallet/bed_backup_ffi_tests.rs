// ---------------------------------------------------------------------------
// BED (Bitcoin Encrypted Descriptor) backup — FFI-layer tests
// ---------------------------------------------------------------------------
// Exercises `export_bed_backup` / `import_bed_backup` / `encode_bed_armor` /
// `sniff_bed_format` end-to-end against a real wallet, as opposed to
// `bed_backup_tests.rs` (crate-level) and `bed_interop_tests.rs` (fixture
// files), which test `bitcoin_encrypted_backup` directly.
// ---------------------------------------------------------------------------

use std::str::FromStr;

use tempfile::tempdir;

use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::Descriptor;

use crate::api::wallet::bed_backup::{
    encode_bed_armor, export_bed_backup, import_bed_backup, sniff_bed_format,
};
use crate::test_support::{APINetwork, KEY_HEX, MAINNET_DESC};

const XPUB_A: &str = "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn";
const XPUB_B: &str = "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj";

/// Round-tripping a descriptor through the crate's own parser normalizes
/// notation (`h` → `'`) and checksum, so byte-for-byte string comparison
/// isn't meaningful here — compare the parsed structures instead.
fn assert_descriptors_equivalent(a: &str, b: &str) {
    let parsed_a = Descriptor::<DescriptorPublicKey>::from_str(a).expect("descriptor a parses");
    let parsed_b = Descriptor::<DescriptorPublicKey>::from_str(b).expect("descriptor b parses");
    assert_eq!(
        parsed_a, parsed_b,
        "descriptors are not equivalent:\n  a: {a}\n  b: {b}"
    );
}

fn create_test_wallet(dir: &tempfile::TempDir, descriptor: &str) -> String {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = crate::api::wallet::create_wallet(
        wallets_dir,
        "Test".to_string(),
        descriptor.to_string(),
        APINetwork::Bitcoin,
        KEY_HEX.to_string(),
        crate::api::model::APIProtectionType::DeviceKey,
        None,
        crate::api::model::APISecurityLevel::Standard,
    )
    .expect("create_wallet failed");
    info.wallet_path
}

#[tokio::test]
async fn test_export_import_roundtrip_each_xpub() {
    let dir = tempdir().unwrap();
    let wallet_path = create_test_wallet(&dir, MAINNET_DESC);

    let export =
        export_bed_backup(wallet_path, KEY_HEX.to_string(), None).expect("export should succeed");
    assert!(!export.backup_bytes.is_empty());
    assert_eq!(&export.backup_bytes[0..3], b"BEB");

    for xpub in [XPUB_A, XPUB_B] {
        let import_dir = tempdir().unwrap();
        let result = import_bed_backup(
            export.backup_bytes.clone(),
            xpub.to_string(),
            KEY_HEX.to_string(),
            import_dir.path().to_string_lossy().to_string(),
            "bitcoin".to_string(),
        )
        .await
        .unwrap_or_else(|e| panic!("import with {xpub} should succeed: {e}"));

        assert_descriptors_equivalent(&result.wallet.descriptor, &export.descriptor);
    }
}

#[tokio::test]
async fn test_export_import_roundtrip_with_origin_brackets() {
    let dir = tempdir().unwrap();
    let wallet_path = create_test_wallet(&dir, MAINNET_DESC);
    let export = export_bed_backup(wallet_path, KEY_HEX.to_string(), None).unwrap();

    let import_dir = tempdir().unwrap();
    let credential = format!("[c449c5c5/48h/0h/0h/2h]{}", XPUB_A);
    let result = import_bed_backup(
        export.backup_bytes.clone(),
        credential,
        KEY_HEX.to_string(),
        import_dir.path().to_string_lossy().to_string(),
        "bitcoin".to_string(),
    )
    .await
    .expect("import with bracketed xpub credential should succeed");

    assert_descriptors_equivalent(&result.wallet.descriptor, &export.descriptor);
}

#[tokio::test]
async fn test_export_import_roundtrip_armored() {
    let dir = tempdir().unwrap();
    let wallet_path = create_test_wallet(&dir, MAINNET_DESC);
    let export = export_bed_backup(wallet_path, KEY_HEX.to_string(), None).unwrap();

    let armored = encode_bed_armor(export.backup_bytes.clone());
    assert!(armored.starts_with("-----BEGIN BITCOIN ENCRYPTED BACKUP-----"));

    let import_dir = tempdir().unwrap();
    let result = import_bed_backup(
        armored.into_bytes(),
        XPUB_A.to_string(),
        KEY_HEX.to_string(),
        import_dir.path().to_string_lossy().to_string(),
        "bitcoin".to_string(),
    )
    .await
    .expect("import from armored text should succeed");

    assert_descriptors_equivalent(&result.wallet.descriptor, &export.descriptor);
}

// Note: there is no test for the single-path rejection guard in
// `export_bed_backup` here. `create_wallet`/BDK already refuses to create a
// wallet from a single-path descriptor (it requires exactly the `<0;1>/*`
// receive/change pair), so a single-path descriptor can never reach
// `export_bed_backup` through any real code path in this app. The guard
// stays as defense-in-depth against a stored descriptor that predates that
// invariant, but it cannot be exercised without hand-crafting a DB row.

#[tokio::test]
async fn test_import_wrong_xpub_fails() {
    let dir = tempdir().unwrap();
    let wallet_path = create_test_wallet(&dir, MAINNET_DESC);
    let export = export_bed_backup(wallet_path, KEY_HEX.to_string(), None).unwrap();

    // A valid xpub, but not one of the descriptor's keys.
    let wrong_xpub = "xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz";

    let import_dir = tempdir().unwrap();
    let result = import_bed_backup(
        export.backup_bytes,
        wrong_xpub.to_string(),
        KEY_HEX.to_string(),
        import_dir.path().to_string_lossy().to_string(),
        "bitcoin".to_string(),
    )
    .await;

    assert!(result.is_err(), "wrong xpub must fail to decrypt");
}

#[tokio::test]
async fn test_import_unrecognized_bytes_fails() {
    let import_dir = tempdir().unwrap();
    let result = import_bed_backup(
        b"not a bed file at all".to_vec(),
        XPUB_A.to_string(),
        KEY_HEX.to_string(),
        import_dir.path().to_string_lossy().to_string(),
        "bitcoin".to_string(),
    )
    .await;

    assert!(result.is_err(), "unrecognized bytes must be rejected");
}

#[test]
fn test_sniff_bed_format_variants() {
    let dir = tempdir().unwrap();
    let wallet_path = create_test_wallet(&dir, MAINNET_DESC);
    let export = export_bed_backup(wallet_path, KEY_HEX.to_string(), None).unwrap();

    assert_eq!(sniff_bed_format(export.backup_bytes.clone()), "binary");

    let armored = encode_bed_armor(export.backup_bytes);
    assert_eq!(sniff_bed_format(armored.into_bytes()), "armored");

    assert_eq!(sniff_bed_format(b"not a bed file".to_vec()), "unknown");
}
