use super::*;

use crate::api::model::APIDescriptorSig;
use crate::core::bip322::{
    build_bip322_descriptor_psbt, descriptor_sig_message, sign_bip322_descriptor_with_xprv,
    verify_bip322_descriptor_sig, verify_bitcoin_message_sig,
};
use crate::core::descriptor::DescriptorAnalyzer;
use crate::core::seed::seed_entry_to_root_xprv;
use crate::core::wallet_persistence::{
    delete_descriptor_sig as db_delete_sig, insert_descriptor_sig as db_insert_sig,
    list_descriptor_sigs, read_wallet_info,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build `xpub_entry` string (`[mfp/path]xpub`) for a given MFP from descriptor.
fn xpub_entry_for_mfp(descriptor: &str, mfp: &str) -> Result<String> {
    use std::sync::OnceLock;
    static RE: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE.get_or_init(|| {
        regex::Regex::new(r"(\[[0-9a-fA-F]{8}[^\]]*\][A-Za-z]{1,4}pub[A-Za-z0-9]+)")
            .expect("xpub_entry regex is valid")
    });
    for cap in re.captures_iter(descriptor) {
        let entry = cap[1].to_string();
        // Extract MFP from the bracket prefix
        let inner = entry.trim_start_matches('[');
        let entry_mfp = inner
            .split(&['/', ']'][..])
            .next()
            .unwrap_or("")
            .to_lowercase();
        if entry_mfp == mfp.to_lowercase() {
            return Ok(entry);
        }
    }
    Err(anyhow::anyhow!("MFP {} not found in descriptor", mfp))
}

/// Build the signing message from the wallet's canonical descriptor.
fn signing_message_for_wallet(conn: &rusqlite::Connection) -> Result<String> {
    let info = read_wallet_info(conn)?;
    let analyzer = DescriptorAnalyzer::analyze(&info.descriptor)?;
    let canonical = analyzer.canonical_descriptor_str();
    Ok(descriptor_sig_message(&canonical))
}

// ---------------------------------------------------------------------------
// Verify helper: verify one stored sig, returns is_valid
// ---------------------------------------------------------------------------

pub(crate) fn verify_one_sig(
    message: &str,
    xpub_entry: &str,
    sig_method: &str,
    sig_hex: &str,
) -> bool {
    match sig_method {
        "bip322" => {
            let Ok(sig_der) = hex::decode(sig_hex) else {
                return false;
            };
            verify_bip322_descriptor_sig(xpub_entry, message, &sig_der).is_ok()
        }
        "message" => verify_bitcoin_message_sig(xpub_entry, message, sig_hex).is_ok(),
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Public API (methods on APIWallet)
// ---------------------------------------------------------------------------

impl APIWallet {
    /// Return all stored descriptor signatures, each with current validity status.
    #[frb(sync)]
    pub fn list_descriptor_sigs(&self) -> Result<Vec<APIDescriptorSig>> {
        let core = self.lock_wallet()?;
        let message = signing_message_for_wallet(&core.conn)?;
        let rows = list_descriptor_sigs(&core.conn)?;
        let sigs = rows
            .into_iter()
            .map(|r| {
                let is_valid = verify_one_sig(&message, &r.xpub_entry, &r.sig_method, &r.sig_hex);
                APIDescriptorSig {
                    mfp: r.mfp,
                    xpub_entry: r.xpub_entry,
                    sig_method: r.sig_method,
                    signed_at: r.signed_at,
                    is_valid,
                }
            })
            .collect();
        Ok(sigs)
    }

    /// Sign the descriptor with a stored HotKey (mnemonic or xprv).
    ///
    /// Derives the root xprv from the seed entry for `mfp`, signs the
    /// canonical descriptor message via the BB02-BIP322 adapted protocol,
    /// and persists the signature.
    #[frb(sync)]
    pub fn sign_descriptor_with_hotkey(&self, mfp: String) -> Result<APIDescriptorSig> {
        let core = self.lock_wallet()?;
        let info = read_wallet_info(&core.conn)?;
        let network: bdk_wallet::bitcoin::Network =
            APINetwork::try_from(info.network.as_str())?.into();

        let message = signing_message_for_wallet(&core.conn)?;
        let xpub_entry = xpub_entry_for_mfp(&info.descriptor, &mfp)?;

        // Load seed entry for this MFP
        let seeds = list_seed_entries(&core.conn)?;
        let seed = seeds
            .iter()
            .find(|s| s.mfp == mfp)
            .ok_or_else(|| anyhow::anyhow!("No HotKey with MFP {} found", mfp))?;

        let root_xprv = seed_entry_to_root_xprv(
            &seed.seed_type,
            seed.mnemonic.as_deref(),
            &seed.passphrase,
            seed.xprv.as_deref(),
            network,
        )?;

        let sig_der = sign_bip322_descriptor_with_xprv(&xpub_entry, &message, &root_xprv)?;
        let sig_hex = hex::encode(&sig_der);

        // Verify before storing
        verify_bip322_descriptor_sig(&xpub_entry, &message, &sig_der)?;

        let signed_at = db_insert_sig(&core.conn, &mfp, &xpub_entry, "bip322", &sig_hex)?;
        Ok(APIDescriptorSig {
            mfp,
            xpub_entry,
            sig_method: "bip322".to_string(),
            signed_at,
            is_valid: true,
        })
    }

    /// Build the BB02-BIP322 PSBT to send to the hardware wallet for signing.
    ///
    /// After calling this, pass the returned PSBT base64 to `hw_sign_psbt`
    /// with descriptor `wsh(pk({xpub_entry}/<0;1>/*))`  and then call
    /// `complete_descriptor_sig_from_psbt` with the signed result.
    ///
    /// Also returns the temporary descriptor string required for BB02 registration.
    #[frb(sync)]
    pub fn prepare_descriptor_sig_psbt(&self, mfp: String) -> Result<APIPrepareDescriptorSigPsbt> {
        let core = self.lock_wallet()?;
        let info = read_wallet_info(&core.conn)?;
        let message = signing_message_for_wallet(&core.conn)?;
        let xpub_entry = xpub_entry_for_mfp(&info.descriptor, &mfp)?;
        let psbt_b64 = build_bip322_descriptor_psbt(&xpub_entry, &message)?;
        let sign_descriptor = format!("wsh(pk({}/<0;1>/*))", xpub_entry);
        Ok(APIPrepareDescriptorSigPsbt {
            psbt_b64,
            sign_descriptor,
            xpub_entry,
            message,
        })
    }

    /// Complete a descriptor signature from a signed BIP322 PSBT (BB02 or QR Variant B).
    ///
    /// Extracts the ECDSA signature from the PSBT's `partial_sigs`, verifies it,
    /// and persists it as `"bip322"`.
    #[frb(sync)]
    pub fn complete_descriptor_sig_from_psbt(
        &self,
        mfp: String,
        xpub_entry: String,
        signed_psbt_b64: String,
    ) -> Result<APIDescriptorSig> {
        use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
        use bdk_wallet::bitcoin::psbt::Psbt;

        let core = self.lock_wallet()?;
        let message = signing_message_for_wallet(&core.conn)?;

        let psbt = Psbt::deserialize(&B64.decode(&signed_psbt_b64)?)?;
        let (_pk, ecdsa_sig) = psbt.inputs[0]
            .partial_sigs
            .iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("No partial_sigs in signed PSBT"))?;
        let sig_der = ecdsa_sig.signature.serialize_der().to_vec();
        let sig_hex = hex::encode(&sig_der);

        verify_bip322_descriptor_sig(&xpub_entry, &message, &sig_der)?;

        let signed_at = db_insert_sig(&core.conn, &mfp, &xpub_entry, "bip322", &sig_hex)?;
        Ok(APIDescriptorSig {
            mfp,
            xpub_entry,
            sig_method: "bip322".to_string(),
            signed_at,
            is_valid: true,
        })
    }

    /// Store a compact Bitcoin message signature (QR Variant A — standard HW message signing).
    ///
    /// `sig_b64` must be a base64-encoded 65-byte compact signature as produced
    /// by most hardware wallets' native "sign message" feature.
    #[frb(sync)]
    pub fn add_descriptor_sig_from_message(
        &self,
        mfp: String,
        xpub_entry: String,
        sig_b64: String,
    ) -> Result<APIDescriptorSig> {
        let core = self.lock_wallet()?;
        let message = signing_message_for_wallet(&core.conn)?;

        verify_bitcoin_message_sig(&xpub_entry, &message, &sig_b64)?;

        let signed_at = db_insert_sig(&core.conn, &mfp, &xpub_entry, "message", &sig_b64)?;
        Ok(APIDescriptorSig {
            mfp,
            xpub_entry,
            sig_method: "message".to_string(),
            signed_at,
            is_valid: true,
        })
    }

    /// Delete a stored descriptor signature.
    #[frb(sync)]
    pub fn delete_descriptor_sig(&self, mfp: String) -> Result<()> {
        let core = self.lock_wallet()?;
        db_delete_sig(&core.conn, &mfp)
    }

    /// Re-verify all stored descriptor signatures and return updated statuses.
    ///
    /// Intentionally identical to [`list_descriptor_sigs`]: verification is
    /// always performed eagerly on every read (see [`verify_one_sig`]).  The
    /// distinction exists at the Flutter/cubit layer, where calling this method
    /// sets `hasVerified = true` in the UI state so that "verified" / "invalid"
    /// labels are shown instead of the neutral "signed" label.
    #[frb(sync)]
    pub fn verify_descriptor_sigs(&self) -> Result<Vec<APIDescriptorSig>> {
        self.list_descriptor_sigs()
    }
}

// ---------------------------------------------------------------------------
// Return type for prepare_descriptor_sig_psbt
// ---------------------------------------------------------------------------

/// Output of `prepare_descriptor_sig_psbt`.
pub struct APIPrepareDescriptorSigPsbt {
    /// PSBT base64 to pass to `hw_sign_psbt`.
    pub psbt_b64: String,
    /// Temporary descriptor (`wsh(pk(…/<0;1>/*))`) to register on the device.
    pub sign_descriptor: String,
    /// The full xpub_entry for the MFP (needed for `complete_descriptor_sig_from_psbt`).
    pub xpub_entry: String,
    /// The message that was signed (for display / QR show).
    pub message: String,
}
