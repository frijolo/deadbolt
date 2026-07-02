// ---------------------------------------------------------------------------
// BED (Bitcoin Encrypted Descriptor) backup — FFI layer
// ---------------------------------------------------------------------------
//
// Wraps the `bitcoin-encrypted-backup` crate (pinned at commit `cd7ee38`, the
// same revision used by `descriptor-cifrado` and Liana 13+) to produce and
// consume `.bed` files.
//
// Key fact (verified against the pinned crate source, not assumed from the
// BIP draft): decryption only needs a `secp256k1::PublicKey`, which is
// derived straight from an xpub string. No private key, seed, or hardware
// device is ever involved on either side of the exchange.
//
// v1 scope: descriptor-only payloads (`Content::Bip380`), binary + ASCII
// armor containers. The pinned crate returns `Error::NotImplemented` when
// decrypting `Bip329`/`Bip388` content, so labels/policy payloads are not
// supported yet.
// ---------------------------------------------------------------------------

use std::str::FromStr;

use anyhow::{Context, Result};
use bitcoin_encrypted_backup::miniscript::{Descriptor, DescriptorPublicKey};
use bitcoin_encrypted_backup::{Decrypted, EncryptedBackup};
use flutter_rust_bridge::frb;

use crate::api::model::{APINetwork, BEDExportResult, BEDImportResult};
use crate::core::bed_container::{decode_armored, encode_armored, sniff_bed, BedFormat};
use crate::core::descriptor_parser::is_single_path;
use crate::core::error::WalletError;
use crate::core::key_protection::parse_xpub_credential;
use crate::core::wallet_info::{create_wallet_db, WalletProtectionRequest};

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

/// Export the wallet's descriptor to a BED file.
///
/// Returns the raw binary payload. Use [`encode_bed_armor`] to obtain the
/// ASCII-armored text variant of the same bytes.
#[frb(sync)]
pub fn export_bed_backup(
    wallet_path: String,
    device_key_hex: String,
    password: Option<String>,
) -> Result<BEDExportResult> {
    let (_data_key, _conn, row) = crate::core::wallet_info::open_snapshot(
        &wallet_path,
        &device_key_hex,
        password.as_deref(),
    )?;

    let descriptor = row.descriptor.clone();
    let wallet_name = row.name;
    let network = row.network;
    let created_at = row.created_at;

    // BED's privacy model only holds up for multipath descriptors — a
    // single-path descriptor leaks the xpub on-chain as soon as any address
    // is used, defeating the point of an xpub-keyed backup.
    if is_single_path(&descriptor) {
        return Err(WalletError::SinglePathDescriptor.into());
    }

    let parsed: Descriptor<DescriptorPublicKey> = Descriptor::from_str(&descriptor)
        .map_err(|_| WalletError::InvalidDescriptorSyntax)
        .context("parsing descriptor for BED export")?;

    let backup = EncryptedBackup::new()
        .set_payload(&parsed)
        .map_err(|e| anyhow::anyhow!("BED encode error: {e:?}"))?;

    let nonce: [u8; 12] = rand::random();
    let encrypted = backup
        .encrypt(nonce)
        .map_err(|e| anyhow::anyhow!("BED encryption error: {e:?}"))?;

    Ok(BEDExportResult {
        backup_bytes: encrypted,
        descriptor,
        wallet_name,
        network,
        created_at,
    })
}

/// Encode raw BED bytes as PEM-style ASCII armor (pure post-processing, no
/// crypto). Mirrors [`decode_armored`] on the way back in.
#[frb(sync)]
pub fn encode_bed_armor(backup_bytes: Vec<u8>) -> String {
    encode_armored(&backup_bytes)
}

// ---------------------------------------------------------------------------
// Import
// ---------------------------------------------------------------------------

/// Import a wallet from a BED file.
///
/// `backup_bytes` may be the raw binary payload or ASCII-armored text
/// (auto-detected). `xpub_credential` is any one of the descriptor's xpubs,
/// with or without the `[fingerprint/path]` origin prefix — only the xpub's
/// own public key is used, so no private key material is required.
///
/// Signature intentionally mirrors `import_onchain_backup` /
/// `import_nostr_backup` so it can be used as a drop-in `rustImport`
/// callback on the Dart side.
pub async fn import_bed_backup(
    backup_bytes: Vec<u8>,
    xpub_credential: String,
    device_key_hex: String,
    wallets_dir: String,
    network_hint: String,
) -> Result<BEDImportResult> {
    let raw_bytes = match sniff_bed(&backup_bytes) {
        Ok(BedFormat::Binary) => backup_bytes,
        Ok(BedFormat::Armored) => {
            let text =
                String::from_utf8(backup_bytes).map_err(|_| WalletError::BedFormatUnknown)?;
            decode_armored(&text).map_err(|_| WalletError::BedFormatUnknown)?
        }
        Err(_) => return Err(WalletError::BedFormatUnknown.into()),
    };

    let (_mfp, bare_xpub) = parse_xpub_credential(&xpub_credential);
    let dpk =
        DescriptorPublicKey::from_str(bare_xpub).map_err(|_| WalletError::BedDecryptionFailed)?;
    let pk = bitcoin_encrypted_backup::descriptor::dpk_to_pk(&dpk);

    let decrypted = EncryptedBackup::new()
        .set_encrypted_payload(&raw_bytes)
        .map_err(|_| WalletError::BedFormatUnknown)?
        .set_keys(vec![pk])
        .decrypt()
        .map_err(|_| WalletError::BedDecryptionFailed)?;

    let descriptor = match decrypted {
        Decrypted::Descriptor(d) => d.to_string(),
        _ => return Err(WalletError::BedUnsupportedContent.into()),
    };

    let network_str = APINetwork::try_from(network_hint.as_str())
        .map(|n| n.as_str().to_string())
        .unwrap_or(network_hint);

    let (path, row) = create_wallet_db(
        &wallets_dir,
        "Imported BED",
        &descriptor,
        &network_str,
        &device_key_hex,
        WalletProtectionRequest::DeviceKey,
    )?;

    let wallet = super::row_to_api_info(path, row)?;
    Ok(BEDImportResult { wallet })
}

// ---------------------------------------------------------------------------
// Sniff
// ---------------------------------------------------------------------------

/// Detect the format of raw bytes — `"binary"`, `"armored"`, or `"unknown"`.
#[frb(sync)]
pub fn sniff_bed_format(backup_bytes: Vec<u8>) -> String {
    match sniff_bed(&backup_bytes) {
        Ok(BedFormat::Binary) => "binary".to_string(),
        Ok(BedFormat::Armored) => "armored".to_string(),
        Err(_) => "unknown".to_string(),
    }
}
