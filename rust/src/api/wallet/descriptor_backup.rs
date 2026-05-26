use std::io::Write as _;
use std::str::FromStr;

use anyhow::Result;
use base64::{engine::general_purpose, Engine as _};
use bdk_electrum::electrum_client::{Client, ElectrumApi};
use bdk_wallet::bitcoin::bip32::Xpub;
use bdk_wallet::bitcoin::hashes::Hash;
use bdk_wallet::bitcoin::key::TapTweak;
pub use bdk_wallet::bitcoin::key::XOnlyPublicKey;
use bdk_wallet::bitcoin::locktime::absolute::LockTime;
pub use bdk_wallet::bitcoin::secp256k1::SecretKey;
use bdk_wallet::bitcoin::secp256k1::{All, Keypair, Message, Secp256k1};
use bdk_wallet::bitcoin::sighash::{Prevouts, SighashCache, TapSighashType};
use bdk_wallet::bitcoin::taproot::{LeafVersion, TaprootBuilder, TaprootSpendInfo};
use bdk_wallet::bitcoin::{
    Address, Amount, Network, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Txid,
    Witness,
};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use zstd::stream::write::Encoder;

use crate::api::model::APINetwork;
use crate::core::descriptor_parser::{extract_xpub_derivation_map, extract_xpub_mfp_map};
use crate::core::key_protection::{
    decrypt_bytes, generate_data_key, parse_xpub_credential, unwrap_xpub_slots, wrap_with_xpub,
    XpubSlot,
};

// ---------------------------------------------------------------------------
// Protocol constants (v1)
// ---------------------------------------------------------------------------

pub(crate) const ANCHOR_DOMAIN_TAG: &[u8] = b"deadbolt-anchor-v1";
const NUMS_XONLY_HEX: &str = "50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0";
const M_COST: u32 = 65_536;
const T_COST: u32 = 3;
pub(crate) const ANCHOR_SATS: u64 = 330;

const SEGWIT_OVERHEAD_WU: u64 = 2;
const INPUT_NW_BYTES: u64 = 41;
const KEYPATH_WITNESS_WU: u64 = 1 + 1 + 64;
/// Full per-input weight delta (non-witness bytes * 4 + witness WU) for a
/// taproot key-path spend. Used as a baseline when the actual spend path
/// weight isn't known yet — callers that *do* know it (e.g. `prepare_backup_psbt`)
/// must pass `SpendPath::wu_in` instead so the fee matches the real witness.
pub(crate) const KEYPATH_INPUT_WU: u64 = INPUT_NW_BYTES * 4 + KEYPATH_WITNESS_WU;

// TX_COMMIT is kept below standard relay minimum so it cannot be mined alone.
// TX_REVEAL carries the bulk of the fees, forming a CPFP package with TX_COMMIT.

// ---------------------------------------------------------------------------
// FRB-exposed return types
// ---------------------------------------------------------------------------

/// Pre-computed backup parameters returned to Flutter immediately (no network).
///
/// Flutter uses `commit_vbytes` + `reveal_vbytes` to compute live fee breakdowns.
/// For N selected UTXOs: total_commit_vbytes = commit_vbytes + (N-1) * ceil(path.wuIn / 4).
pub struct BackupParams {
    /// Commit TX weight in vbytes assuming one input (baseline).
    pub commit_vbytes: u64,
    pub reveal_vbytes: u64,
    pub participant_count: u32,
    pub vault_address: String,
    pub vault_tapscript_hex: String,
    pub anchor_addresses: Vec<String>,
    /// Minimum UTXO value in sats at the base fee rate (0.1 sat/vB).
    /// Flutter should scale this dynamically: min = base_min + commit_vbytes * (fee_rate - 0.1).
    pub min_utxo_sats_base: u64,
}

/// Unsigned TX_COMMIT PSBT with fee breakdown. Returned by `prepare_onchain_backup_psbt`.
///
/// Pass `commit_psbt_base64` to the signer and both fields verbatim to
/// `finalize_onchain_backup` once signing is complete.
pub struct OnchainBackupPsbt {
    pub commit_psbt_base64: String,
    pub vault_tapscript_hex: String,
    pub commit_fee_sat: u64,
    pub reveal_fee_sat: u64,
    pub vault_sats: u64,
    pub anchor_cost_sat: u64,
    pub anchor_count: u32,
    pub change_sat: u64,
    pub reveal_change_sat: u64,
    pub package_vbytes: u64,
}

/// Txids produced by a successful commit-reveal backup.
pub struct OnchainBackupResult {
    pub commit_txid: String,
    pub reveal_txid: String,
}

/// Whether a previous on-chain backup exists for an xpub.
pub struct ExistingBackupInfo {
    pub found: bool,
    pub commit_txid: Option<String>,
    pub reveal_txid: Option<String>,
}

/// Health status of an existing on-chain backup for this wallet.
pub struct WalletBackupStatus {
    pub found: bool,
    pub commit_txid: Option<String>,
    pub reveal_txid: Option<String>,
    /// How many anchor addresses have the commit TX in their Electrum history.
    pub anchors_reachable: u32,
    pub anchors_total: u32,
    /// True when TX_REVEAL was found and its decrypted descriptor matches this wallet.
    pub descriptor_verified: bool,
}

// ---------------------------------------------------------------------------
// Weight calculation (same as PoC)
// ---------------------------------------------------------------------------

/// Weight of TX_COMMIT in WU.
///
/// `per_input_wu` is the full per-input weight delta (non-witness bytes * 4
/// plus witness WU). For a taproot key-path spend this is `KEYPATH_INPUT_WU`;
/// for multisig or script-path spends it must be the `SpendPath::wu_in` value
/// measured against the actual descriptor, otherwise the fee will be set from
/// an underestimated weight and broadcast may be rejected with a "min relay
/// fee not met" error.
pub(crate) fn commit_weight(n_inputs: usize, n_anchors: usize, per_input_wu: u64) -> u64 {
    let ni = n_inputs as u64;
    let n_outputs = (2 + n_anchors) as u64;
    // Non-witness bytes excluding inputs (version + n_in varint + n_out varint
    // + outputs + lock_time). Inputs contribute via `per_input_wu`.
    let nw_no_inputs: u64 = 4 + 1 + 1 + 43 * n_outputs + 4;
    nw_no_inputs * 4 + SEGWIT_OVERHEAD_WU + per_input_wu * ni
}

pub(crate) fn reveal_weight(tapscript_len: usize, n_anchors: usize) -> u64 {
    let n_inputs = (1 + n_anchors) as u64;
    let nw: u64 = 4 + 1 + INPUT_NW_BYTES * n_inputs + 1 + 43 + 4;
    let ts_len = tapscript_len as u64;
    let ts_len_varint: u64 = if tapscript_len <= 252 { 1 } else { 3 };
    let vault_witness_wu: u64 = 1 + ts_len_varint + ts_len + 1 + 33;
    let w: u64 = SEGWIT_OVERHEAD_WU + vault_witness_wu + KEYPATH_WITNESS_WU * n_anchors as u64;
    nw * 4 + w
}

#[cfg(test)]
fn fee_from_weight(weight_wu: u64, fee_rate: f64) -> u64 {
    let vbytes = weight_wu.div_ceil(4);
    (vbytes as f64 * fee_rate).ceil() as u64
}

/// Split fees into (commit_fee, reveal_fee) following the CPFP package strategy.
///
/// TX_COMMIT pays only `min_commit_fee_rate` so it cannot be relayed or mined
/// alone.  TX_REVEAL carries the balance so that the combined package reaches
/// `user_fee_rate`.
///
/// `min_commit_fee_rate` is also used as the safeguard minimum for TX_REVEAL —
/// its fee is guaranteed to be at least `reveal_vbytes * min_commit_fee_rate`
/// so the transaction independently meets the network minimum relay fee.
pub(crate) fn split_package_fees(
    commit_wu: u64,
    reveal_wu: u64,
    user_fee_rate: f64,
    min_fee_rate: f64,
) -> (u64, u64) {
    let commit_vbytes = commit_wu.div_ceil(4);
    let reveal_vbytes = reveal_wu.div_ceil(4);
    let total_fee = ((commit_vbytes + reveal_vbytes) as f64 * user_fee_rate).ceil() as u64;
    // +1 sat ensures the commit TX clears minimum relay fee on all nodes.
    let commit_fee = (commit_vbytes as f64 * min_fee_rate).ceil() as u64 + 1;
    // Ensure TX_REVEAL independently meets the minimum relay fee requirement.
    // When user_fee_rate is very low (e.g. 0.1 sat/vB), the raw split can leave
    // reveal_fee below the relay threshold, causing broadcast rejection.
    let min_reveal_fee = (reveal_vbytes as f64 * min_fee_rate).ceil() as u64;
    let reveal_fee = total_fee.saturating_sub(commit_fee).max(min_reveal_fee);

    (commit_fee, reveal_fee)
}

// ---------------------------------------------------------------------------
// Anchor key derivation (shared with descriptor_recovery.rs)
// ---------------------------------------------------------------------------

pub(crate) struct AnchorKey {
    pub xonly: XOnlyPublicKey,
    pub privkey: SecretKey,
}

pub(crate) fn derive_anchor_key(secp: &Secp256k1<All>, xpub: &Xpub) -> AnchorKey {
    let xpub_str = xpub.to_string();
    for counter in 0u8..=255 {
        let mut mac =
            Hmac::<Sha256>::new_from_slice(ANCHOR_DOMAIN_TAG).expect("HMAC accepts any key length");
        mac.update(&[counter]);
        mac.update(xpub_str.as_bytes());
        if let Ok(sk) = SecretKey::from_slice(&mac.finalize().into_bytes()) {
            let (xonly, _) = Keypair::from_secret_key(secp, &sk).x_only_public_key();
            return AnchorKey { xonly, privkey: sk };
        }
    }
    unreachable!("all 256 HMAC-SHA256 outputs invalid")
}

pub(crate) fn anchor_p2tr_address(
    secp: &Secp256k1<All>,
    key: &AnchorKey,
    network: Network,
) -> Address {
    Address::p2tr(secp, key.xonly, None, network)
}

// ---------------------------------------------------------------------------
// Encrypted payload construction (same as PoC)
// ---------------------------------------------------------------------------

pub(crate) fn zstd_compress(data: &[u8]) -> Vec<u8> {
    let mut enc = Encoder::new(Vec::new(), 22).expect("zstd encoder");
    enc.write_all(data).expect("zstd write");
    enc.finish().expect("zstd finish")
}

/// `participants`: slice of (mfp, bare_xpub, derivation_path)
pub(crate) fn build_encrypted_payload(
    descriptor: &str,
    participants: &[(&str, &str, &str)],
    wallet_name: &str,
) -> Result<Vec<u8>> {
    let export_key = generate_data_key()?;
    let inner = serde_json::json!({
        "descriptor": descriptor,
        "wallet_name": wallet_name,
    });
    let compressed = zstd_compress(&serde_json::to_vec(&inner)?);
    let encrypted_desc = crate::core::key_protection::encrypt_bytes(&export_key, &compressed)?;
    let data_b64 = general_purpose::STANDARD.encode(&encrypted_desc);

    let mut slots: Vec<serde_json::Value> = Vec::new();
    for &(mfp, xpub, path) in participants {
        let slot = wrap_with_xpub(mfp, xpub, &export_key, M_COST, T_COST, path)?;
        slots.push(serde_json::to_value(&slot)?);
    }

    let payload = serde_json::json!({
        "version": 3,
        "slots": slots,
        "data": data_b64,
    });
    Ok(serde_json::to_vec(&payload)?)
}

// ---------------------------------------------------------------------------
// Vault tapscript / taproot (same as PoC)
// ---------------------------------------------------------------------------

pub(crate) fn vault_tapscript(payload: &[u8]) -> ScriptBuf {
    let mut raw: Vec<u8> = Vec::with_capacity(payload.len() + 16);
    raw.push(0x51); // OP_1
    raw.push(0x00); // OP_FALSE
    raw.push(0x63); // OP_IF
    for chunk in payload.chunks(520) {
        let n = chunk.len();
        match n {
            0..=75 => raw.push(n as u8),
            76..=255 => {
                raw.push(0x4c);
                raw.push(n as u8);
            }
            _ => {
                raw.push(0x4d);
                raw.extend_from_slice(&(n as u16).to_le_bytes());
            }
        }
        raw.extend_from_slice(chunk);
    }
    raw.push(0x68); // OP_ENDIF
    ScriptBuf::from_bytes(raw)
}

pub(crate) fn vault_taproot(secp: &Secp256k1<All>, script: &ScriptBuf) -> Result<TaprootSpendInfo> {
    let nums = XOnlyPublicKey::from_slice(&hex::decode(NUMS_XONLY_HEX)?)?;
    TaprootBuilder::new()
        .add_leaf(0, script.clone())?
        .finalize(secp, nums)
        .map_err(|_| anyhow::anyhow!("TaprootBuilder::finalize failed"))
}

// ---------------------------------------------------------------------------
// TX_REVEAL helpers
// ---------------------------------------------------------------------------

pub(crate) fn build_reveal(
    commit_txid: Txid,
    vault_vout: u32,
    vault_txout: &TxOut,
    anchor_vouts: &[u32],
    anchor_txouts: &[TxOut],
    fee_sats: u64,
    change_addr: &Address,
) -> Result<Transaction> {
    let total_in: u64 =
        vault_txout.value.to_sat() + anchor_txouts.iter().map(|o| o.value.to_sat()).sum::<u64>();
    let change_sats = total_in.checked_sub(fee_sats).ok_or_else(|| {
        anyhow::anyhow!("Reveal inputs ({total_in} sats) < fee ({fee_sats} sats)")
    })?;
    anyhow::ensure!(
        change_sats >= 330,
        "reveal change {change_sats} below P2TR dust"
    );

    let mut inputs = vec![TxIn {
        previous_output: OutPoint {
            txid: commit_txid,
            vout: vault_vout,
        },
        script_sig: ScriptBuf::default(),
        sequence: Sequence::ENABLE_RBF_NO_LOCKTIME,
        witness: Witness::default(),
    }];
    for &vout in anchor_vouts {
        inputs.push(TxIn {
            previous_output: OutPoint {
                txid: commit_txid,
                vout,
            },
            script_sig: ScriptBuf::default(),
            sequence: Sequence::ENABLE_RBF_NO_LOCKTIME,
            witness: Witness::default(),
        });
    }
    Ok(Transaction {
        version: bdk_wallet::bitcoin::transaction::Version(2),
        lock_time: LockTime::ZERO,
        input: inputs,
        output: vec![TxOut {
            value: Amount::from_sat(change_sats),
            script_pubkey: change_addr.script_pubkey(),
        }],
    })
}

pub(crate) fn sign_reveal(
    secp: &Secp256k1<All>,
    tx: &mut Transaction,
    vault_txout: &TxOut,
    anchor_txouts: &[TxOut],
    vault_info: &TaprootSpendInfo,
    tapscript: &ScriptBuf,
    anchor_keys: &[AnchorKey],
) -> Result<()> {
    let mut prevouts: Vec<TxOut> = vec![vault_txout.clone()];
    prevouts.extend_from_slice(anchor_txouts);

    let anchor_sighashes: Vec<_> = {
        let mut cache = SighashCache::new(&*tx);
        (1..=anchor_txouts.len())
            .map(|i| {
                cache
                    .taproot_key_spend_signature_hash(
                        i,
                        &Prevouts::All(&prevouts),
                        TapSighashType::Default,
                    )
                    .expect("sighash always valid")
            })
            .collect()
    };

    for (i, (sh, key)) in anchor_sighashes.iter().zip(anchor_keys.iter()).enumerate() {
        let keypair = Keypair::from_secret_key(secp, &key.privkey);
        let tweaked = keypair.tap_tweak(secp, None);
        let sig = secp.sign_schnorr(
            &Message::from_digest(*sh.as_byte_array()),
            &tweaked.to_keypair(),
        );
        let tap_sig = bdk_wallet::bitcoin::taproot::Signature {
            signature: sig,
            sighash_type: TapSighashType::Default,
        };
        tx.input[i + 1].witness = Witness::from_slice(&[tap_sig.serialize()]);
    }

    let cb = vault_info
        .control_block(&(tapscript.clone(), LeafVersion::TapScript))
        .ok_or_else(|| anyhow::anyhow!("control block not found for vault tapscript"))?;
    tx.input[0].witness = Witness::from_slice(&[tapscript.as_bytes(), &cb.serialize()]);
    Ok(())
}

// ---------------------------------------------------------------------------
// Participant xpubs from descriptor
// ---------------------------------------------------------------------------

/// Returns `(mfp, bare_xpub, derivation_path)` for every key in the descriptor,
/// sorted by mfp so that callers (anchor addresses, slot ordering, fee
/// previews) get a deterministic result across invocations.
pub(crate) fn participant_triples(descriptor: &str) -> Vec<(String, String, String)> {
    let mfp_to_xpub = extract_xpub_mfp_map(descriptor);
    let mfp_to_path = extract_xpub_derivation_map(descriptor);
    let mut out: Vec<(String, String, String)> = mfp_to_xpub
        .into_iter()
        .map(|(mfp, xpub)| {
            let path = mfp_to_path.get(&mfp).cloned().unwrap_or_default();
            (mfp, xpub, path)
        })
        .collect();
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

// ---------------------------------------------------------------------------
// Reveal TX / inscription envelope helpers (used by descriptor_recovery.rs too)
// ---------------------------------------------------------------------------

pub(crate) fn find_reveal_tx(
    client: &Client,
    vault_spk: &ScriptBuf,
    commit_txid: Txid,
    vault_vout: u32,
) -> Option<(Txid, Transaction, usize)> {
    let vault_outpoint = OutPoint {
        txid: commit_txid,
        vout: vault_vout,
    };
    for item in client.script_get_history(vault_spk.as_script()).ok()? {
        if item.tx_hash == commit_txid {
            continue;
        }
        if let Ok(tx) = client.transaction_get(&item.tx_hash) {
            if tx.input.iter().any(|i| i.previous_output == vault_outpoint) {
                return Some((item.tx_hash, tx, item.height.max(0) as usize));
            }
        }
    }
    None
}

/// Find TX_REVEAL for a commit TX without assuming a fixed vault output position.
///
/// Iterates every output that is not one of the known anchor scriptPubKeys and
/// calls `find_reveal_tx` for each candidate. The first output whose Electrum
/// history contains a transaction spending that outpoint is returned.
///
/// This is robust to BDK reordering TX_COMMIT outputs at build time.
pub(crate) fn find_reveal_tx_for_commit(
    client: &Client,
    commit_tx: &Transaction,
    commit_txid: Txid,
    anchor_spks: &[ScriptBuf],
) -> Option<(Txid, Transaction, usize)> {
    for (vout, output) in commit_tx.output.iter().enumerate() {
        if anchor_spks.contains(&output.script_pubkey) {
            continue;
        }
        if let Some(result) =
            find_reveal_tx(client, &output.script_pubkey, commit_txid, vout as u32)
        {
            return Some(result);
        }
    }
    None
}

pub(crate) fn extract_raw_from_tapscript(tapscript: &[u8]) -> Result<Vec<u8>> {
    let mut pos = 0;

    macro_rules! expect {
        ($byte:expr, $name:expr) => {
            match tapscript.get(pos) {
                Some(&b) if b == $byte => pos += 1,
                other => anyhow::bail!(
                    "expected {} (0x{:02x}) at offset {pos}, got {other:?}",
                    $name,
                    $byte
                ),
            }
        };
    }

    expect!(0x51, "OP_1");
    expect!(0x00, "OP_FALSE");
    expect!(0x63, "OP_IF");

    let mut compressed: Vec<u8> = Vec::new();
    loop {
        let op = *tapscript
            .get(pos)
            .ok_or_else(|| anyhow::anyhow!("unexpected end at offset {pos}"))?;
        match op {
            0x68 => break,
            1..=75 => {
                let len = op as usize;
                pos += 1;
                let end = pos + len;
                anyhow::ensure!(end <= tapscript.len(), "direct push overrun");
                compressed.extend_from_slice(&tapscript[pos..end]);
                pos = end;
            }
            0x4c => {
                pos += 1;
                let len = *tapscript
                    .get(pos)
                    .ok_or_else(|| anyhow::anyhow!("PUSHDATA1 length missing"))?
                    as usize;
                pos += 1;
                let end = pos + len;
                anyhow::ensure!(end <= tapscript.len(), "PUSHDATA1 overrun");
                compressed.extend_from_slice(&tapscript[pos..end]);
                pos = end;
            }
            0x4d => {
                pos += 1;
                anyhow::ensure!(pos + 2 <= tapscript.len(), "PUSHDATA2 length missing");
                let len = u16::from_le_bytes([tapscript[pos], tapscript[pos + 1]]) as usize;
                pos += 2;
                let end = pos + len;
                anyhow::ensure!(end <= tapscript.len(), "PUSHDATA2 overrun");
                compressed.extend_from_slice(&tapscript[pos..end]);
                pos = end;
            }
            _ => anyhow::bail!("unexpected opcode 0x{op:02x} at offset {pos}"),
        }
    }

    zstd::decode_all(&compressed[..]).map_err(|e| anyhow::anyhow!("zstd decompress: {e}"))
}

/// Decrypt the on-chain backup envelope and return the raw inner bytes and the descriptor string.
pub(crate) fn decrypt_onchain_backup(
    raw_bytes: &[u8],
    xpub_credential: &str,
) -> Result<(Vec<u8>, String)> {
    let payload: serde_json::Value =
        serde_json::from_slice(raw_bytes).map_err(|e| anyhow::anyhow!("JSON parse: {e}"))?;

    let version = payload["version"].as_u64().unwrap_or(0);
    if version != 3 {
        anyhow::bail!("unsupported payload version {version} (expected 3)");
    }

    let slots: Vec<XpubSlot> = payload["slots"]
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("missing 'slots' array"))?
        .iter()
        .map(|v| serde_json::from_value::<XpubSlot>(v.clone()))
        .collect::<std::result::Result<_, _>>()
        .map_err(|e| anyhow::anyhow!("slot deserialization: {e}"))?;

    let (mfp_hint, bare_xpub) = parse_xpub_credential(xpub_credential);
    let (export_key, _) = unwrap_xpub_slots(bare_xpub, mfp_hint, &slots)
        .map_err(|_| anyhow::anyhow!("xpub does not match any slot in this backup"))?;

    let data_b64 = payload["data"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing 'data' field"))?;
    let encrypted = general_purpose::STANDARD
        .decode(data_b64)
        .map_err(|e| anyhow::anyhow!("base64 decode: {e}"))?;
    let compressed = decrypt_bytes(&export_key, &encrypted)
        .map_err(|e| anyhow::anyhow!("AES-256-GCM decrypt: {e}"))?;

    let inner_bytes =
        zstd::decode_all(&compressed[..]).map_err(|e| anyhow::anyhow!("zstd decompress: {e}"))?;

    let descriptor = serde_json::from_slice::<serde_json::Value>(&inner_bytes)
        .map_err(|e| anyhow::anyhow!("inner JSON parse: {e}"))?["descriptor"]
        .as_str()
        .map(String::from)
        .ok_or_else(|| anyhow::anyhow!("missing descriptor in inner JSON"))?;

    Ok((inner_bytes, descriptor))
}

pub(crate) fn extract_descriptor_from_reveal(
    reveal_tx: &Transaction,
    xpub_credential: &str,
) -> Result<(String, Vec<u8>, serde_json::Value)> {
    let mut last_error = String::from("no script-path spend found in any input");
    for (idx, input) in reveal_tx.input.iter().enumerate() {
        let witness = &input.witness;
        let n = witness.len();
        if n < 2 {
            continue;
        }
        let control_block = witness.iter().last().unwrap();
        if control_block.first().map(|&b| b & 0xfe) != Some(0xc0) {
            continue;
        }
        let tapscript: &[u8] = witness.iter().nth(n - 2).unwrap();
        match extract_raw_from_tapscript(tapscript) {
            Err(e) => last_error = format!("input {idx}: envelope parse failed: {e}"),
            Ok(raw) => match decrypt_onchain_backup(&raw, xpub_credential) {
                Ok((inner_bytes, descriptor)) => {
                    match serde_json::from_slice::<serde_json::Value>(&inner_bytes) {
                        Ok(inner) => return Ok((descriptor, raw, inner)),
                        Err(e) => last_error = format!("input {idx}: inner JSON parse: {e}"),
                    }
                }
                Err(e) => last_error = format!("input {idx}: decrypt failed: {e}"),
            },
        }
    }
    Err(anyhow::anyhow!("{last_error}"))
}

// ---------------------------------------------------------------------------
// Public FRB functions
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Unified PSBT backup flow (all wallet types)
// ---------------------------------------------------------------------------

/// Minimum total UTXO sats required to perform the backup at the given fee rate.
///
/// Uses the same weight model as `prepare_backup_psbt` (keypath witness per input).
/// `commit_weight` already includes the change output in its size estimate, so the
/// fee covers that weight regardless of whether a change output is actually created.
/// Any surplus above this minimum goes to a change output when ≥ 330 sats (P2TR dust),
/// or is absorbed into the commit fee when below dust.
///
/// Flutter should call this instead of estimating weights locally.
#[flutter_rust_bridge::frb(sync)]
pub fn compute_min_utxo_sats(
    commit_vbytes: u64,
    reveal_vbytes: u64,
    n_anchors: u32,
    fee_rate_sat_per_vb: f64,
    min_fee_rate: f64,
) -> u64 {
    let (commit_fee, reveal_fee) = split_package_fees(
        commit_vbytes * 4,
        reveal_vbytes * 4,
        fee_rate_sat_per_vb,
        min_fee_rate,
    );
    let anchor_cost = ANCHOR_SATS * n_anchors as u64;
    let vault_sats = ANCHOR_SATS.max(reveal_fee.saturating_sub(anchor_cost));
    vault_sats + anchor_cost + commit_fee
}

/// Check if an on-chain backup exists for the given xpub credential.
pub async fn check_existing_backup(
    xpub_credential: String,
    electrum_url: String,
    network_hint: String,
) -> Result<ExistingBackupInfo> {
    use crate::core::key_protection::parse_xpub_credential;

    let network: Network = APINetwork::try_from(network_hint.as_str())?.into();
    let (_, bare_xpub) = parse_xpub_credential(&xpub_credential);

    let client = super::create_raw_electrum_client(&electrum_url)?;

    let secp = Secp256k1::new();
    let xpub = Xpub::from_str(bare_xpub)?;
    let anchor = derive_anchor_key(&secp, &xpub);
    let addr = anchor_p2tr_address(&secp, &anchor, network);
    let anchor_spk = addr.script_pubkey();

    let history = client
        .script_get_history(anchor_spk.as_script())
        .map_err(|e| anyhow::anyhow!("Electrum error: {e}"))?;
    if history.is_empty() {
        return Ok(ExistingBackupInfo {
            found: false,
            commit_txid: None,
            reveal_txid: None,
        });
    }

    let mut commit_txid: Option<Txid> = None;
    for item in &history {
        let tx = client
            .transaction_get(&item.tx_hash)
            .map_err(|e| anyhow::anyhow!("Electrum fetch: {e}"))?;
        if tx.output.iter().any(|o| o.script_pubkey == anchor_spk) {
            commit_txid = Some(item.tx_hash);
            break;
        }
    }

    let Some(ctxid) = commit_txid else {
        return Ok(ExistingBackupInfo {
            found: false,
            commit_txid: None,
            reveal_txid: None,
        });
    };

    // Look for TX_REVEAL. The vault output position is not fixed — locate it by
    // excluding the known anchor output and trying each remaining output.
    let commit_tx = client
        .transaction_get(&ctxid)
        .map_err(|e| anyhow::anyhow!("Electrum fetch commit tx: {e}"))?;

    let reveal_txid = find_reveal_tx_for_commit(&client, &commit_tx, ctxid, &[anchor_spk])
        .map(|(txid, _, _)| txid.to_string());

    Ok(ExistingBackupInfo {
        found: true,
        commit_txid: Some(ctxid.to_string()),
        reveal_txid,
    })
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
#[path = "descriptor_backup_tests.rs"]
mod tests;
