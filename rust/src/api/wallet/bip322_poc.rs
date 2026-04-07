//! BIP-322-like message signing for BitBox02 — PoC and findings
//!
//! # Goal
//!
//! Prove ownership of an xpub by producing a verifiable signature over a
//! message, using a BitBox02 as the signing device.  The standard approach
//! (BIP-322) cannot be applied verbatim because the BB02 firmware imposes
//! constraints that deviate from the spec.  This module documents those
//! constraints, defines the adapted protocol, and provides a standalone
//! verifier.
//!
//! # BB02 firmware constraints (empirically verified)
//!
//! The following table summarises what the BB02 accepts and rejects in a PSBT,
//! with the BIP-322 spec requirement shown for comparison.
//!
//! | Parameter              | BIP-322 spec | BB02 result       | Notes                              |
//! |------------------------|--------------|-------------------|------------------------------------|
//! | `version`              | 0            | **REJECTED**      | Only v=2 accepted                  |
//! | `sequence`             | 0            | accepted          | No restriction                     |
//! | `output value = 0`     | 0 sat        | REJECTED (change) | Zero-value outputs need OP_RETURN  |
//! | `naked OP_RETURN`      | required     | REJECTED in lib   | `bitbox-api` rejects at Rust level |
//! | `OP_RETURN <data> v=0` | —            | accepted          | With value=0; shows on screen      |
//! | `OP_RETURN <data> v≠0` | —            | REJECTED          | OP_RETURN must have value=0        |
//! | `non_witness_utxo`     | optional     | **MANDATORY**     | Missing → "previous tx required"   |
//!
//! # Why two transactions are required
//!
//! BB02 mandates `non_witness_utxo` (the full previous transaction) even for
//! native SegWit inputs, as a defence against the "segwit fee bug".  This makes
//! it impossible to reference an arbitrary txid (e.g. SHA256(message)) as the
//! direct input — the device would reject the PSBT for missing the previous tx.
//!
//! A "fictional" previous transaction (`funding_tx`) must therefore be provided.
//! Since this tx is constructed deterministically from the message, it does not
//! need to exist on-chain and does not require separate storage.
//!
//! # Protocol (BB02-BIP322)
//!
//! ```text
//! ── Signing ──────────────────────────────────────────────────────────────
//!
//! Temporary descriptor:  wsh(pk([MFP/account_path]xpub/<0;1>/*))
//! Register on BB02 under an ephemeral name (e.g. "BIP322 PoC").
//!
//! funding_tx  (never signed; provided as non_witness_utxo in PSBT):
//!   version:  2
//!   input[0]: outpoint = (SHA256(message), 0),  sequence = MAX
//!   output[0]: 1 sat → P2WSH(wsh(pk(xpub/0/0)))   ← signing address
//!
//! to_sign_tx  (signed by BB02):
//!   version:  2
//!   input[0]: outpoint = (txid(funding_tx), 0),  sequence = MAX
//!   output[0]: 1 sat → P2WSH(wsh(pk(xpub/1/0)))  ← change address, fee = 0
//!
//! PSBT fields (input):
//!   witness_utxo     = { 1 sat, P2WSH(xpub/0/0) }
//!   non_witness_utxo = funding_tx
//!   witness_script   = <pubkey/0/0> OP_CHECKSIG
//!   bip32_derivation = { pubkey/0/0 → (MFP, m/account_path/0/0) }
//!
//! PSBT fields (output):
//!   witness_script   = <pubkey/1/0> OP_CHECKSIG
//!   bip32_derivation = { pubkey/1/0 → (MFP, m/account_path/1/0) }
//!   (Marks output as change; BB02 shows no "external address" warning.)
//!
//! BB02 shows: "send to self, fee: 0"  →  user confirms  →  ECDSA sig extracted.
//!
//! ── Proof ────────────────────────────────────────────────────────────────
//!
//! { xpub_entry, message, sig_der }
//!
//! ── Verification ─────────────────────────────────────────────────────────
//!
//! Given only (xpub_entry, message, sig_der):
//!
//!   1. xpub/0/0 → pubkey → witness_script → P2WSH_spk   (input address)
//!   2. xpub/1/0 → change_pubkey → change_witness_script → change_P2WSH_spk
//!   3. SHA256(message) → fake_input_txid
//!   4. funding_tx  = { in: (fake_input_txid,0), out: 1sat→P2WSH_spk }
//!   5. to_sign_tx  = { in: (funding_txid,0),    out: 1sat→change_P2WSH_spk }
//!   6. sighash     = BIP143(to_sign_tx, witness_script, 1 sat)
//!   7. verify ECDSA(sig_der, sighash, pubkey)  →  VALID / INVALID
//! ```
//!
//! # Design decisions
//!
//! - **`wsh(pk(xpub))`** instead of a native single-key type: BB02 natively
//!   handles P2WPKH/P2PKH/P2SH-P2WPKH without registration.  `wsh(pk(...))`
//!   is a policy descriptor that must be registered, which is required for
//!   BB02 to sign PSBTs for it.
//!
//! - **Change output at xpub/1/0** (internal chain): BB02 classifies outputs
//!   whose derivation path is in the PSBT output's `bip32_derivation` as
//!   "change".  Using the internal chain (index 1) avoids the "sending to
//!   external address" warning on the device screen.
//!
//! - **fee = 0** (1 sat in, 1 sat out): makes `to_sign_tx` fully deterministic
//!   from the inputs alone.  No PSBT needs to be persisted.
//!
//! - **`OP_RETURN` output rejected** in favour of the change output: although
//!   `OP_RETURN <data>` with value=0 is accepted by BB02, it triggers an
//!   additional confirmation screen on the device.  The change-output approach
//!   is cleaner from a UX perspective.

use anyhow::Result;

/// Verifies a BB02-BIP322 descriptor ownership signature.
///
/// Reconstructs the deterministic transaction chain from `xpub_entry` and
/// `message`, computes the BIP-143 sighash, and checks `sig_der` against it.
/// No network access or stored state is required.
///
/// # Arguments
/// * `xpub_entry`   — full descriptor key, e.g. `[aabbccdd/48'/1'/0'/2']tpub…`
/// * `message`      — the message that was signed (raw UTF-8 string)
/// * `sig_der`      — ECDSA signature in DER encoding
/// * `signing_path` — (chain, index) for the signing key; defaults to `(0, 0)`
/// * `change_path`  — (chain, index) for the change output; defaults to `(1, 0)`
///
/// # Returns
/// `Ok(pubkey_hex)` — compressed public key that produced the signature.
/// `Err(_)`         — signature invalid or inputs malformed.
pub(crate) fn verify_bip322_descriptor_sig(
    xpub_entry: &str,
    message: &str,
    sig_der: &[u8],
    signing_path: Option<(u32, u32)>,
    change_path: Option<(u32, u32)>,
) -> Result<String> {
    use bdk_wallet::bitcoin::{
        absolute::LockTime,
        bip32::{ChildNumber, Xpub},
        opcodes::all::OP_CHECKSIG,
        script::Builder,
        secp256k1::{ecdsa::Signature, Message as SecpMsg, Secp256k1},
        sighash::{EcdsaSighashType, SighashCache},
        transaction::Version,
        Amount, OutPoint, PublicKey, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Txid, Witness,
    };
    use sha2::{Digest, Sha256};
    use std::str::FromStr;

    let (s_chain, s_idx) = signing_path.unwrap_or((0, 0));
    let (c_chain, c_idx) = change_path.unwrap_or((1, 0));

    // Parse bare xpub from "[mfp/path]xpub..." format
    let bare_xpub = xpub_entry
        .find(']')
        .map(|i| &xpub_entry[i + 1..])
        .ok_or_else(|| anyhow::anyhow!("xpub_entry must be in [mfp/path]xpub format"))?;

    let xpub_obj = Xpub::from_str(bare_xpub).map_err(|e| anyhow::anyhow!("Invalid xpub: {e}"))?;
    let secp = Secp256k1::new();

    // Derive signing pubkey (external chain) and change pubkey (internal chain)
    let pubkey = PublicKey::new(
        xpub_obj
            .derive_pub(
                &secp,
                &[
                    ChildNumber::Normal { index: s_chain },
                    ChildNumber::Normal { index: s_idx },
                ],
            )
            .map_err(|e| anyhow::anyhow!("Signing key derivation: {e}"))?
            .public_key,
    );
    let change_pubkey = PublicKey::new(
        xpub_obj
            .derive_pub(
                &secp,
                &[
                    ChildNumber::Normal { index: c_chain },
                    ChildNumber::Normal { index: c_idx },
                ],
            )
            .map_err(|e| anyhow::anyhow!("Change key derivation: {e}"))?
            .public_key,
    );

    // Build P2WSH scripts
    let witness_script = Builder::new()
        .push_key(&pubkey)
        .push_opcode(OP_CHECKSIG)
        .into_script();
    let p2wsh_spk = ScriptBuf::new_p2wsh(&witness_script.wscript_hash());

    let change_witness_script = Builder::new()
        .push_key(&change_pubkey)
        .push_opcode(OP_CHECKSIG)
        .into_script();
    let change_p2wsh_spk = ScriptBuf::new_p2wsh(&change_witness_script.wscript_hash());

    // SHA256(message) → deterministic fake input txid
    let hash_bytes: [u8; 32] = Sha256::digest(message.as_bytes()).into();
    let fake_input_txid = Txid::from_str(&hex::encode(hash_bytes))
        .map_err(|e| anyhow::anyhow!("SHA256 as Txid: {e}"))?;

    // Reconstruct funding_tx
    let funding_tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: vec![TxIn {
            previous_output: OutPoint::new(fake_input_txid, 0),
            script_sig: ScriptBuf::new(),
            sequence: Sequence::MAX,
            witness: Witness::new(),
        }],
        output: vec![TxOut {
            value: Amount::from_sat(1),
            script_pubkey: p2wsh_spk,
        }],
    };

    // Reconstruct to_sign_tx
    let to_sign_tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: vec![TxIn {
            previous_output: OutPoint::new(funding_tx.compute_txid(), 0),
            script_sig: ScriptBuf::new(),
            sequence: Sequence::MAX,
            witness: Witness::new(),
        }],
        output: vec![TxOut {
            value: Amount::from_sat(1),
            script_pubkey: change_p2wsh_spk,
        }],
    };

    // BIP-143 sighash
    let sighash = SighashCache::new(&to_sign_tx)
        .p2wsh_signature_hash(
            0,
            &witness_script,
            Amount::from_sat(1),
            EcdsaSighashType::All,
        )
        .map_err(|e| anyhow::anyhow!("sighash: {e}"))?;

    // Parse DER signature and verify
    let sig =
        Signature::from_der(sig_der).map_err(|e| anyhow::anyhow!("Invalid DER signature: {e}"))?;
    let msg = SecpMsg::from_digest_slice(sighash.as_ref())
        .map_err(|e| anyhow::anyhow!("sighash → message: {e}"))?;
    Secp256k1::verification_only()
        .verify_ecdsa(&msg, &sig, &pubkey.inner)
        .map_err(|e| anyhow::anyhow!("Signature invalid: {e}"))?;

    Ok(pubkey.to_string())
}

#[cfg(test)]
mod tests {
    use super::verify_bip322_descriptor_sig;
    use crate::api::{
        hw_wallet::{
            connect_hw_device, get_hw_session_info, hw_disconnect, hw_register_descriptor,
            hw_sign_psbt, list_hw_devices, wait_hw_pairing,
        },
        model::APINetwork,
    };
    use anyhow::Result;
    use base64::engine::general_purpose::STANDARD as B64;
    use base64::Engine as _;
    use bdk_wallet::bitcoin::{
        absolute::LockTime,
        bip32::{ChildNumber, DerivationPath, Fingerprint, Xpub},
        opcodes::all::OP_CHECKSIG,
        psbt::Psbt,
        script::Builder,
        secp256k1::Secp256k1,
        transaction::Version,
        Amount, OutPoint, PublicKey, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Txid, Witness,
    };
    use sha2::{Digest, Sha256};
    use std::str::FromStr;
    use tempfile::tempdir;

    // ── Shared output type ────────────────────────────────────────────────────

    /// Output of a successful BB02-BIP322 signing round.
    struct Bip322SignOutput {
        /// ECDSA signature in DER encoding, as returned by BB02.
        sig_der: Vec<u8>,
        /// Compressed signing pubkey (xpub/0/0), hex-encoded.
        pubkey_hex: String,
        /// SHA256(message) hex — the deterministic fake input txid.
        message_hash_hex: String,
    }

    // ── Common signing helper ─────────────────────────────────────────────────

    /// Full BB02-BIP322 signing flow for any `xpub_entry` / `message` pair.
    ///
    /// Builds the deterministic two-tx chain, constructs the PSBT, connects to
    /// a BitBox02 (registering the temporary `wsh(pk(...))` descriptor), has
    /// the user confirm on the device, and extracts the ECDSA signature.
    ///
    /// Returns `None` when no BitBox02 is detected (test is silently skipped).
    ///
    /// # Arguments
    /// * `xpub_entry`  — descriptor key: `[MFP/account_path]xpub…` or
    ///                   `[MFP/account_path]tpub…`
    /// * `message`     — raw UTF-8 message to sign
    /// * `network`     — `APINetwork::Mainnet` | `APINetwork::Testnet`
    /// * `wallet_name` — name shown during BB02 descriptor registration
    fn sign_bip322_like(
        xpub_entry: &str,
        message: &str,
        network: APINetwork,
        wallet_name: &str,
    ) -> Result<Option<Bip322SignOutput>> {
        // ── Parse xpub_entry ─────────────────────────────────────────────────
        let inner = xpub_entry.trim_start_matches('[');
        let mfp_str = inner
            .split('/')
            .next()
            .ok_or_else(|| anyhow::anyhow!("Cannot parse MFP from xpub_entry"))?;
        let account_path = inner
            .find('/')
            .and_then(|i| {
                let rest = &inner[i + 1..];
                rest.find(']').map(|j| &rest[..j])
            })
            .ok_or_else(|| anyhow::anyhow!("Cannot extract account path from xpub_entry"))?;
        let bare_xpub = xpub_entry
            .find(']')
            .map(|i| &xpub_entry[i + 1..])
            .ok_or_else(|| anyhow::anyhow!("Cannot extract bare xpub from xpub_entry"))?;

        println!("Signing MFP:  {mfp_str}");
        println!("Account path: m/{account_path}");

        // ── Derive keys ───────────────────────────────────────────────────────
        let xpub_obj =
            Xpub::from_str(bare_xpub).map_err(|e| anyhow::anyhow!("Invalid xpub: {e}"))?;
        let secp = Secp256k1::new();

        let pubkey = PublicKey::new(
            xpub_obj
                .derive_pub(
                    &secp,
                    &[
                        ChildNumber::Normal { index: 0 },
                        ChildNumber::Normal { index: 0 },
                    ],
                )
                .map_err(|e| anyhow::anyhow!("BIP-32 signing key derivation: {e}"))?
                .public_key,
        );
        let change_pubkey = PublicKey::new(
            xpub_obj
                .derive_pub(
                    &secp,
                    &[
                        ChildNumber::Normal { index: 1 },
                        ChildNumber::Normal { index: 0 },
                    ],
                )
                .map_err(|e| anyhow::anyhow!("BIP-32 change key derivation: {e}"))?
                .public_key,
        );
        println!("Pubkey/0/0:   {pubkey}");
        println!("Pubkey/1/0:   {change_pubkey}");

        // ── P2WSH scripts ─────────────────────────────────────────────────────
        let witness_script = Builder::new()
            .push_key(&pubkey)
            .push_opcode(OP_CHECKSIG)
            .into_script();
        let p2wsh_spk = ScriptBuf::new_p2wsh(&witness_script.wscript_hash());

        let change_witness_script = Builder::new()
            .push_key(&change_pubkey)
            .push_opcode(OP_CHECKSIG)
            .into_script();
        let change_p2wsh_spk = ScriptBuf::new_p2wsh(&change_witness_script.wscript_hash());

        // ── SHA256(message) → fake input txid ────────────────────────────────
        let hash_bytes: [u8; 32] = Sha256::digest(message.as_bytes()).into();
        let message_hash_hex = hex::encode(hash_bytes);
        let fake_input_txid = Txid::from_str(&message_hash_hex)
            .map_err(|e| anyhow::anyhow!("SHA256 as Txid: {e}"))?;
        println!("SHA256(msg):  {message_hash_hex}");

        // ── funding_tx (deterministic; never signed; mandatory for BB02) ──────
        let funding_tx = Transaction {
            version: Version::TWO,
            lock_time: LockTime::ZERO,
            input: vec![TxIn {
                previous_output: OutPoint::new(fake_input_txid, 0),
                script_sig: ScriptBuf::new(),
                sequence: Sequence::MAX,
                witness: Witness::new(),
            }],
            output: vec![TxOut {
                value: Amount::from_sat(1),
                script_pubkey: p2wsh_spk.clone(),
            }],
        };
        let funding_txid = funding_tx.compute_txid();
        println!("Funding TXID: {funding_txid}");

        // ── to_sign_tx (fee = 0; fully deterministic) ─────────────────────────
        // Output → xpub/1/0 (internal chain) so BB02 shows it as change,
        // avoiding the "external address" confirmation screen.
        let to_sign_tx = Transaction {
            version: Version::TWO,
            lock_time: LockTime::ZERO,
            input: vec![TxIn {
                previous_output: OutPoint::new(funding_txid, 0),
                script_sig: ScriptBuf::new(),
                sequence: Sequence::MAX,
                witness: Witness::new(),
            }],
            output: vec![TxOut {
                value: Amount::from_sat(1),
                script_pubkey: change_p2wsh_spk.clone(),
            }],
        };

        // ── Build PSBT ────────────────────────────────────────────────────────
        let mut psbt =
            Psbt::from_unsigned_tx(to_sign_tx).map_err(|e| anyhow::anyhow!("PSBT from tx: {e}"))?;
        let fp = mfp_str
            .parse::<Fingerprint>()
            .map_err(|e| anyhow::anyhow!("Fingerprint: {e}"))?;
        {
            let pi = &mut psbt.inputs[0];
            pi.witness_utxo = Some(TxOut {
                value: Amount::from_sat(1),
                script_pubkey: p2wsh_spk,
            });
            pi.non_witness_utxo = Some(funding_tx); // mandatory for BB02
            pi.witness_script = Some(witness_script.clone());
            let path = DerivationPath::from_str(&format!("m/{account_path}/0/0"))
                .map_err(|e| anyhow::anyhow!("Signing DerivationPath: {e}"))?;
            pi.bip32_derivation.insert(pubkey.inner, (fp, path));
        }
        {
            let po = &mut psbt.outputs[0];
            po.witness_script = Some(change_witness_script);
            let path = DerivationPath::from_str(&format!("m/{account_path}/1/0"))
                .map_err(|e| anyhow::anyhow!("Change DerivationPath: {e}"))?;
            po.bip32_derivation.insert(change_pubkey.inner, (fp, path));
        }
        let psbt_b64 = B64.encode(psbt.serialize());

        // ── Hardware signing ──────────────────────────────────────────────────
        let sign_descriptor = format!("wsh(pk({}/<0;1>/*))", xpub_entry);
        let devices = list_hw_devices();
        if devices.is_empty() {
            println!("\nNo BitBox02 detected — signing skipped.");
            return Ok(None);
        }

        let tmp = tempdir()?;
        let noise_dir = tmp.path().join("hw_pairing").to_string_lossy().to_string();
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?;

        println!("\n=== HARDWARE SIGNING ===");
        println!(
            "Device: {} [{}]",
            devices[0].product_string, devices[0].device_path
        );

        let connect = rt.block_on(connect_hw_device(devices[0].device_path.clone(), noise_dir))?;
        let session_id = connect.session_id.clone();

        if let Some(code) = &connect.pairing_code {
            println!("Pairing code: {code} — confirm on device");
            rt.block_on(wait_hw_pairing(session_id.clone()))?;
            println!("Paired.");
        } else {
            println!("Already paired.");
        }

        let info = get_hw_session_info(session_id.clone())?;
        if info.root_fingerprint != mfp_str {
            println!("WARNING: device MFP {} ≠ {mfp_str}", info.root_fingerprint);
        } else {
            println!("MFP match: {mfp_str} ✓");
        }

        let newly_registered = rt.block_on(hw_register_descriptor(
            session_id.clone(),
            wallet_name.to_string(),
            sign_descriptor.clone(),
            network,
        ))?;
        println!("Descriptor registered (new={newly_registered}).");

        println!("Confirm on device (shows: send to self, fee = 0)...");
        let signed_psbt_b64 = rt.block_on(hw_sign_psbt(
            session_id.clone(),
            psbt_b64,
            network,
            Some(sign_descriptor),
        ))?;

        // ── Extract ECDSA signature ───────────────────────────────────────────
        let signed_psbt = Psbt::deserialize(&B64.decode(&signed_psbt_b64)?)?;
        let (_pk, ecdsa_sig) = signed_psbt.inputs[0]
            .partial_sigs
            .iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("No partial_sigs in signed PSBT"))?;
        let sig_der = ecdsa_sig.signature.serialize_der().to_vec();
        println!("Signature (DER): {}", hex::encode(&sig_der));

        let _ = hw_disconnect(session_id);
        println!("Device disconnected.");

        Ok(Some(Bip322SignOutput {
            sig_der,
            pubkey_hex: pubkey.to_string(),
            message_hash_hex,
        }))
    }

    // ── Shared verify-and-print helper ────────────────────────────────────────

    fn verify_and_print(xpub_entry: &str, message: &str, out: &Bip322SignOutput) -> Result<()> {
        println!("\n=== INDEPENDENT VERIFICATION ===");
        println!("Inputs: xpub_entry + message + sig_der");

        let verified_pubkey =
            verify_bip322_descriptor_sig(xpub_entry, message, &out.sig_der, None, None)?;

        println!("pubkey (xpub/0/0): {verified_pubkey}");
        println!("SHA256(message):   {}", out.message_hash_hex);
        println!("signature (DER):   {}", hex::encode(&out.sig_der));
        println!("\nResult: VALID ✓");
        Ok(())
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    /// BB02-BIP322 with the existing example xpub / descriptor (m/48'/1'/0'/2').
    ///
    /// Reads xpub and message from `xpub_ejemplo.txt` / `descriptor_ejemplo.txt`
    /// at the repo root. Skipped automatically when no BitBox02 is detected.
    #[test]
    fn test_bip322_m48() -> Result<()> {
        const XPUB_ENTRY: &str = "[4061aff0/48'/1'/0'/1']tpubDFAv39stw4ELNRJns8vuoZQrpvAcpRqk3LxV8gHfbegc3BH6AtD316QDu5eWof8EqA459jSchDXmCy3ogv75Qc1fttQxzqGD36E75DpjH3i";
        const MESSAGE: &str = "Ownership proof — m/48'";

        let Some(out) = sign_bip322_like(XPUB_ENTRY, MESSAGE, APINetwork::Signet, "BIP322 m48")?
        else {
            return Ok(());
        };

        verify_and_print(XPUB_ENTRY, MESSAGE, &out)
    }

    /// BB02-BIP322 with a P2WPKH (native SegWit) key at m/84'/0'/0'.
    ///
    /// Fill in `XPUB_ENTRY` with `[MFP/84'/0'/0']xpub…` (mainnet)
    /// or `[MFP/84'/1'/0']tpub…` (testnet) from the target device.
    #[test]
    fn test_bip322_m84() -> Result<()> {
        const XPUB_ENTRY: &str = "[4061aff0/84'/1'/0']tpubDDW89obYFKaCXrsrGHE9bZM3xt9AaFZdhDVEMVwbY1xNFmesRqTK6ou6C6smG1XdgkaeFd5ZFeeLn3AgEvKNq7s38DbEmRGSoeogsbM1QTs";
        const MESSAGE: &str = "Ownership proof — m/84'";

        let Some(out) = sign_bip322_like(XPUB_ENTRY, MESSAGE, APINetwork::Signet, "BIP322 m84")?
        else {
            return Ok(());
        };

        verify_and_print(XPUB_ENTRY, MESSAGE, &out)
    }

    /// BB02-BIP322 with a Taproot key at m/86'/0'/0'.
    ///
    /// Note: BB02 supports native P2TR outputs, but the `wsh(pk(...))` wrapper
    /// used here is a separate policy descriptor — the protocol is the same
    /// regardless of the xpub's intended address type.
    ///
    /// Fill in `XPUB_ENTRY` with `[MFP/86'/0'/0']xpub…` from the target device.
    #[test]
    fn test_bip322_m86() -> Result<()> {
        const XPUB_ENTRY: &str = "[4061aff0/86'/1'/0']tpubDC8K2g13MjUxLo9tK8FT3uanTfR2WVT4nH4EimwXmkw6RuWH17sRaFkPHsoeF2SDh7JJs4h5gZaFxMaSaWsBwpLfFcqBAuR76rJFzRHrV3f";
        const MESSAGE: &str = "Ownership proof — m/86'";

        let Some(out) = sign_bip322_like(XPUB_ENTRY, MESSAGE, APINetwork::Signet, "BIP322 m86")?
        else {
            return Ok(());
        };

        verify_and_print(XPUB_ENTRY, MESSAGE, &out)
    }

    /// BB02-BIP322 with a wrapped SegWit (P2SH-P2WPKH) key at m/49'/0'/0'.
    ///
    /// Fill in `XPUB_ENTRY` with `[MFP/49'/0'/0']xpub…` from the target device.
    #[test]
    fn test_bip322_m49() -> Result<()> {
        const XPUB_ENTRY: &str = "[4061aff0/49'/1'/0']tpubDD5sDNk7RDWG8qMnfHRNNRskzpUCY3tBbm9ARB8RNHr9Ci7687bwc9TU8iqFHT8xchDLuUusnzeKv1cqdbxX365XyrygBkSqXLyXeR8iXHn";
        const MESSAGE: &str = "Ownership proof — m/49'";

        let Some(out) = sign_bip322_like(XPUB_ENTRY, MESSAGE, APINetwork::Signet, "BIP322 m49")?
        else {
            return Ok(());
        };

        verify_and_print(XPUB_ENTRY, MESSAGE, &out)
    }

    /// BB02-BIP322 with a legacy (P2PKH) key at m/44'/0'/0'.
    ///
    /// Fill in `XPUB_ENTRY` with `[MFP/44'/0'/0']xpub…` from the target device.
    #[test]
    fn test_bip322_m44() -> Result<()> {
        const XPUB_ENTRY: &str = "[4061aff0/44'/1'/0']tpubDCrnozEoX8UCUfjJqUubu1cY5m74Z9R17Hm6cDTx3oi5zH77M2aioB3kv8eUGXgMdzPYGAssrmdTg9j5upf3kFpphouEYVwirEZd7n7JyAS";
        const MESSAGE: &str = "Ownership proof — m/44'";

        let Some(out) = sign_bip322_like(XPUB_ENTRY, MESSAGE, APINetwork::Signet, "BIP322 m44")?
        else {
            return Ok(());
        };

        verify_and_print(XPUB_ENTRY, MESSAGE, &out)
    }
}
