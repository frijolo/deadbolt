//! BIP-322-like message signing for BitBox02
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
//! Register on BB02 under an ephemeral name (e.g. "BIP322 m48'").
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

// ---------------------------------------------------------------------------
// xpub_entry parsing
// ---------------------------------------------------------------------------

/// Parse `"[mfp/account_path]xpub…"` into its three components.
///
/// Returns `(mfp_str, account_path, bare_xpub)`.
fn parse_xpub_entry(xpub_entry: &str) -> Result<(&str, &str, &str)> {
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
    Ok((mfp_str, account_path, bare_xpub))
}

// ---------------------------------------------------------------------------
// Message derivation
// ---------------------------------------------------------------------------

/// Returns the canonical message used for descriptor signing.
///
/// Always ~85 chars regardless of descriptor length, so it stays within
/// hardware-wallet message-signing limits (e.g. Coldcard ≤ 240 chars).
///
/// Format: `"deadbolt-descriptor-v1:\n" + sha256_hex(canonical_descriptor)`
pub(crate) fn descriptor_sig_message(canonical_descriptor: &str) -> String {
    use sha2::{Digest, Sha256};
    let hash: [u8; 32] = Sha256::digest(canonical_descriptor.as_bytes()).into();
    format!("deadbolt-descriptor-v1:\n{}", hex::encode(hash))
}

// ---------------------------------------------------------------------------
// PSBT construction (shared by BB02 and QR Variant B flows)
// ---------------------------------------------------------------------------

/// Build the deterministic BB02-BIP322 PSBT for `xpub_entry` / `message`.
///
/// Returns the PSBT serialized as base64. The caller is responsible for
/// registering `wsh(pk({xpub_entry}/<0;1>/*))` on the device before signing.
pub(crate) fn build_bip322_descriptor_psbt(xpub_entry: &str, message: &str) -> Result<String> {
    use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
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

    let (mfp_str, account_path, bare_xpub) = parse_xpub_entry(xpub_entry)?;

    let xpub_obj = Xpub::from_str(bare_xpub)?;
    let secp = Secp256k1::new();

    let pubkey = PublicKey::new(
        xpub_obj
            .derive_pub(
                &secp,
                &[
                    ChildNumber::Normal { index: 0 },
                    ChildNumber::Normal { index: 0 },
                ],
            )?
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
            )?
            .public_key,
    );

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

    let hash_bytes: [u8; 32] = Sha256::digest(message.as_bytes()).into();
    let fake_input_txid = Txid::from_str(&hex::encode(hash_bytes))?;

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

    let mut psbt = Psbt::from_unsigned_tx(to_sign_tx)?;
    let fp = mfp_str.parse::<Fingerprint>()?;
    {
        let pi = &mut psbt.inputs[0];
        pi.witness_utxo = Some(TxOut {
            value: Amount::from_sat(1),
            script_pubkey: p2wsh_spk,
        });
        pi.non_witness_utxo = Some(funding_tx);
        pi.witness_script = Some(witness_script);
        let path = DerivationPath::from_str(&format!("m/{account_path}/0/0"))?;
        pi.bip32_derivation.insert(pubkey.inner, (fp, path));
    }
    {
        let po = &mut psbt.outputs[0];
        po.witness_script = Some(change_witness_script);
        let path = DerivationPath::from_str(&format!("m/{account_path}/1/0"))?;
        po.bip32_derivation.insert(change_pubkey.inner, (fp, path));
    }

    Ok(B64.encode(psbt.serialize()))
}

// ---------------------------------------------------------------------------
// HotKey signing (programmatic, no hardware)
// ---------------------------------------------------------------------------

/// Sign the BB02-BIP322 PSBT for `xpub_entry` / `message` using `root_xprv`.
///
/// Derives the private key at `m/{account_path}/0/0`, computes the BIP-143
/// sighash, signs with ECDSA, and returns the DER-encoded signature.
///
/// `account_path` is extracted automatically from `xpub_entry`'s bracket.
pub(crate) fn sign_bip322_descriptor_with_xprv(
    xpub_entry: &str,
    message: &str,
    root_xprv: &bdk_wallet::bitcoin::bip32::Xpriv,
) -> Result<Vec<u8>> {
    use bdk_wallet::bitcoin::{
        absolute::LockTime,
        bip32::{ChildNumber, DerivationPath, Xpub},
        opcodes::all::OP_CHECKSIG,
        script::Builder,
        secp256k1::{Message as SecpMsg, Secp256k1},
        sighash::{EcdsaSighashType, SighashCache},
        transaction::Version,
        Amount, OutPoint, PublicKey, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Txid, Witness,
    };
    use sha2::{Digest, Sha256};
    use std::str::FromStr;

    let (_, account_path, bare_xpub) = parse_xpub_entry(xpub_entry)?;

    let secp = Secp256k1::new();
    let xpub_obj = Xpub::from_str(bare_xpub)?;

    // Derive signing pubkey (0/0) and change pubkey (1/0)
    let pubkey = PublicKey::new(
        xpub_obj
            .derive_pub(
                &secp,
                &[
                    ChildNumber::Normal { index: 0 },
                    ChildNumber::Normal { index: 0 },
                ],
            )?
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
            )?
            .public_key,
    );

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

    let hash_bytes: [u8; 32] = Sha256::digest(message.as_bytes()).into();
    let fake_input_txid = Txid::from_str(&hex::encode(hash_bytes))?;

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
    let sighash = SighashCache::new(&to_sign_tx).p2wsh_signature_hash(
        0,
        &witness_script,
        Amount::from_sat(1),
        EcdsaSighashType::All,
    )?;

    // Derive private key at m/{account_path}/0/0
    let signing_path = DerivationPath::from_str(&format!("m/{account_path}/0/0"))?;
    let signing_xprv = root_xprv.derive_priv(&secp, &signing_path)?;

    let msg = SecpMsg::from_digest_slice(sighash.as_ref())?;
    let sig = secp.sign_ecdsa(&msg, &signing_xprv.private_key);
    Ok(sig.serialize_der().to_vec())
}

// ---------------------------------------------------------------------------
// QR Variant A: standard Bitcoin message signature verification
// ---------------------------------------------------------------------------

/// Verify a compact base64 Bitcoin message signature (65 bytes, as produced by
/// most hardware wallets via their native "sign message" feature).
///
/// The message hash follows the standard Bitcoin signed message format:
///   SHA256d( "\x18Bitcoin Signed Message:\n" + varint(len) + message )
///
/// `xpub_entry` — `[mfp/path]xpub…`; the signing key is derived at `0/0`.
pub(crate) fn verify_bitcoin_message_sig(
    xpub_entry: &str,
    message: &str,
    sig_b64: &str,
) -> Result<()> {
    use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
    use bitcoin::{
        bip32::{ChildNumber, Xpub},
        secp256k1::{
            ecdsa::{RecoverableSignature, RecoveryId, Signature as EcdsaSig},
            Message as SecpMsg, Secp256k1,
        },
    };
    use sha2::{Digest, Sha256};
    use std::str::FromStr;

    let (_, _, bare_xpub) = parse_xpub_entry(xpub_entry)?;
    let xpub_obj = Xpub::from_str(bare_xpub)?;
    let secp = Secp256k1::new();

    // xpub/0/0 — the child key our BIP322-PSBT protocol designates as the signing key.
    let pubkey_0_0 = xpub_obj
        .derive_pub(
            &secp,
            &[
                ChildNumber::Normal { index: 0 },
                ChildNumber::Normal { index: 0 },
            ],
        )?
        .public_key;

    let msg_bytes = message.as_bytes();

    let raw = B64.decode(sig_b64)?;

    if raw.len() == 65 {
        // BIP137 compact format: [recovery_flag, R(32), S(32)]
        // Signing key: xpub/0/0.
        // Hash: double-SHA256 over the magic prefix + varint + message.
        // Used by Coldcard, BitBox02, and Krux "sign with address" path.
        let varint = encode_varint(msg_bytes.len());
        let mut preimage = Vec::with_capacity(26 + varint.len() + msg_bytes.len());
        preimage.extend_from_slice(b"\x18Bitcoin Signed Message:\n");
        preimage.extend_from_slice(&varint);
        preimage.extend_from_slice(msg_bytes);
        let hash1: [u8; 32] = Sha256::digest(&preimage).into();
        let hash2: [u8; 32] = Sha256::digest(hash1).into();
        let msg = SecpMsg::from_digest_slice(&hash2)?;

        let flag = raw[0];
        let rec_id_val = if flag >= 31 { flag - 31 } else { flag - 27 } & 0x03;
        let rec_id = RecoveryId::from_i32(rec_id_val as i32)
            .map_err(|_| anyhow::anyhow!("Invalid recovery id {rec_id_val}"))?;
        let rec_sig = RecoverableSignature::from_compact(&raw[1..], rec_id)?;
        let recovered = secp.recover_ecdsa(&msg, &rec_sig)?;
        if recovered != pubkey_0_0 {
            return Err(anyhow::anyhow!("Message signature does not match xpub/0/0"));
        }
    } else {
        // DER format without recovery byte.
        // Krux (embit HDKey.sign path): signs with the account-level xpub key directly,
        // over a plain SHA256(message) — no Bitcoin magic prefix.
        let sig = EcdsaSig::from_der(&raw).map_err(|_| {
            anyhow::anyhow!(
                "Cannot parse signature: expected 65-byte compact (BIP137) or DER, got {} bytes",
                raw.len()
            )
        })?;
        let hash: [u8; 32] = Sha256::digest(msg_bytes).into();
        let msg = SecpMsg::from_digest_slice(&hash)?;
        secp.verify_ecdsa(&msg, &sig, &xpub_obj.public_key)
            .map_err(|_| anyhow::anyhow!("Message signature does not match xpub/0/0"))?;
    }

    Ok(())
}

fn encode_varint(n: usize) -> Vec<u8> {
    if n < 0xfd {
        vec![n as u8]
    } else if n <= 0xffff {
        let mut v = vec![0xfd];
        v.extend_from_slice(&(n as u16).to_le_bytes());
        v
    } else {
        let mut v = vec![0xfe];
        v.extend_from_slice(&(n as u32).to_le_bytes());
        v
    }
}

// ---------------------------------------------------------------------------
// Verifier
// ---------------------------------------------------------------------------

/// Verifies a BB02-BIP322 descriptor ownership signature.
///
/// Reconstructs the deterministic transaction chain from `xpub_entry` and
/// `message`, computes the BIP-143 sighash, and checks `sig_der` against it.
/// No network access or stored state is required.
///
/// # Arguments
/// * `xpub_entry` — full descriptor key, e.g. `[aabbccdd/48'/1'/0'/2']tpub…`
/// * `message`    — the message that was signed (raw UTF-8 string)
/// * `sig_der`    — ECDSA signature in DER encoding
///
/// # Returns
/// `Ok(pubkey_hex)` — compressed public key that produced the signature.
/// `Err(_)`         — signature invalid or inputs malformed.
pub(crate) fn verify_bip322_descriptor_sig(
    xpub_entry: &str,
    message: &str,
    sig_der: &[u8],
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

    let (s_chain, s_idx) = (0u32, 0u32);
    let (c_chain, c_idx) = (1u32, 0u32);

    let (_, _, bare_xpub) = parse_xpub_entry(xpub_entry)?;

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
    use super::{sign_bip322_descriptor_with_xprv, verify_bip322_descriptor_sig};
    use crate::core::seed::mnemonic_to_root_xprv;
    use anyhow::Result;
    use bdk_wallet::bitcoin::{
        bip32::{DerivationPath, Xpub},
        secp256k1::Secp256k1,
        Network,
    };
    use std::str::FromStr;

    // BIP39 test vector mnemonic (24 words, no passphrase) — not used for real funds.
    const TEST_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon \
         abandon abandon abandon abandon abandon abandon abandon abandon \
         abandon abandon abandon abandon abandon abandon abandon art";

    fn root_xprv() -> bdk_wallet::bitcoin::bip32::Xpriv {
        mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet).expect("valid test mnemonic")
    }

    fn xpub_entry_for_path(path_str: &str) -> String {
        let root = root_xprv();
        let secp = Secp256k1::new();
        let path = DerivationPath::from_str(path_str).unwrap();
        let account_xprv = root.derive_priv(&secp, &path).unwrap();
        let account_xpub = Xpub::from_priv(&secp, &account_xprv);
        let mfp = root.fingerprint(&secp);
        let path_part = path_str.trim_start_matches("m/");
        format!("[{mfp}/{path_part}]{account_xpub}")
    }

    #[test]
    fn sign_and_verify_roundtrip_m48() -> Result<()> {
        let xpub_entry = xpub_entry_for_path("m/48'/1'/0'/2'");
        let message = "Ownership proof — m/48'";
        let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, message, &root_xprv())?;
        let pubkey = verify_bip322_descriptor_sig(&xpub_entry, message, &sig)?;
        assert!(!pubkey.is_empty());
        Ok(())
    }

    #[test]
    fn sign_and_verify_roundtrip_m84() -> Result<()> {
        let xpub_entry = xpub_entry_for_path("m/84'/1'/0'");
        let message = "Ownership proof — m/84'";
        let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, message, &root_xprv())?;
        let pubkey = verify_bip322_descriptor_sig(&xpub_entry, message, &sig)?;
        assert!(!pubkey.is_empty());
        Ok(())
    }

    #[test]
    fn wrong_message_fails_verification() -> Result<()> {
        let xpub_entry = xpub_entry_for_path("m/84'/1'/0'");
        let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, "correct message", &root_xprv())?;
        assert!(verify_bip322_descriptor_sig(&xpub_entry, "wrong message", &sig).is_err());
        Ok(())
    }

    #[test]
    fn wrong_xpub_fails_verification() -> Result<()> {
        let xpub_entry = xpub_entry_for_path("m/84'/1'/0'");
        let other_xpub_entry = xpub_entry_for_path("m/49'/1'/0'");
        let message = "test message";
        let sig = sign_bip322_descriptor_with_xprv(&xpub_entry, message, &root_xprv())?;
        assert!(verify_bip322_descriptor_sig(&other_xpub_entry, message, &sig).is_err());
        Ok(())
    }
}
