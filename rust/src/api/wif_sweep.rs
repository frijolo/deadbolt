use anyhow::Result;
use bdk_wallet::bitcoin::locktime::absolute::LockTime;
use bdk_wallet::bitcoin::secp256k1::{Message, Secp256k1};
use bdk_wallet::bitcoin::sighash::{EcdsaSighashType, SighashCache};
use bdk_wallet::bitcoin::transaction::Version;
use bdk_wallet::bitcoin::{
    Address, Amount, CompressedPublicKey, Network, OutPoint, PrivateKey, PublicKey, ScriptBuf,
    Sequence, Transaction, TxIn, TxOut, Txid, Witness,
};
use std::str::FromStr;

use crate::api::model::APINetwork;
use crate::api::wallet::create_raw_electrum_client;

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

/// A single address derived from a WIF key.
pub struct APIWifAddress {
    /// One of: `"p2wpkh"`, `"p2pkh"`, `"p2sh_wpkh"`.
    pub address_type: String,
    pub address: String,
}

/// A UTXO controlled by a WIF key.
pub struct APIWifUtxo {
    pub txid: String,
    pub vout: u32,
    pub value_sat: u64,
    pub address: String,
    /// Same type string as in [`APIWifAddress::address_type`].
    pub address_type: String,
}

// ---------------------------------------------------------------------------
// Step 1 — resolve addresses from WIF (sync)
// ---------------------------------------------------------------------------

/// Derive the P2WPKH, P2PKH, and P2SH-P2WPKH addresses controlled by `wif`.
///
/// Returns them in that order so callers can display them for the user to
/// identify which address type holds funds.
pub fn resolve_wif(wif: String, network: APINetwork) -> Result<Vec<APIWifAddress>> {
    let secp = Secp256k1::new();
    let priv_key = PrivateKey::from_wif(&wif).map_err(|e| anyhow::anyhow!("Invalid WIF: {}", e))?;
    let compressed_pub = CompressedPublicKey::from_private_key(&secp, &priv_key)
        .map_err(|_| anyhow::anyhow!("Only compressed WIF keys are supported"))?;
    // Also keep a PublicKey for P2PKH (accepts either compressed or uncompressed).
    let pub_key = PublicKey::from_private_key(&secp, &priv_key);

    let net: Network = network.into();

    Ok(vec![
        APIWifAddress {
            address_type: "p2wpkh".to_string(),
            address: Address::p2wpkh(&compressed_pub, net).to_string(),
        },
        APIWifAddress {
            address_type: "p2pkh".to_string(),
            address: Address::p2pkh(pub_key, net).to_string(),
        },
        APIWifAddress {
            address_type: "p2sh_wpkh".to_string(),
            address: Address::p2shwpkh(&compressed_pub, net).to_string(),
        },
    ])
}

// ---------------------------------------------------------------------------
// Step 2 — query UTXOs (async, requires Electrum)
// ---------------------------------------------------------------------------

/// Query Electrum for all UTXOs controlled by `wif` across all supported
/// address types (P2WPKH, P2PKH, P2SH-P2WPKH).
pub async fn query_wif_utxos(
    wif: String,
    network: APINetwork,
    electrum_url: String,
) -> Result<Vec<APIWifUtxo>> {
    use bdk_electrum::electrum_client::ElectrumApi;

    let addresses = resolve_wif(wif, network)?;
    let net: Network = network.into();
    let client = create_raw_electrum_client(&electrum_url)?;

    let mut result = Vec::new();
    for addr_entry in &addresses {
        let addr = Address::from_str(&addr_entry.address)
            .map_err(|e| anyhow::anyhow!("Address parse error: {}", e))?
            .require_network(net)
            .map_err(|_| anyhow::anyhow!("Network mismatch for address"))?;
        let spk = addr.script_pubkey();

        // Silently skip address types with no UTXOs or query errors.
        if let Ok(utxos) = client.script_list_unspent(&spk) {
            for utxo in utxos {
                result.push(APIWifUtxo {
                    txid: utxo.tx_hash.to_string(),
                    vout: utxo.tx_pos as u32,
                    value_sat: utxo.value,
                    address: addr_entry.address.clone(),
                    address_type: addr_entry.address_type.clone(),
                });
            }
        }
    }
    Ok(result)
}

// ---------------------------------------------------------------------------
// Step 3 — sweep (build, sign, broadcast)
// ---------------------------------------------------------------------------

/// Sweep all funds controlled by `wif` to `destination_address`.
///
/// Queries Electrum for UTXOs, builds a transaction spending all of them to
/// `destination_address` (minus fee), signs each input, and broadcasts.
///
/// Returns the transaction ID of the broadcast transaction.
pub async fn sweep_wif(
    wif: String,
    destination_address: String,
    fee_rate_sat_per_vb: f64,
    electrum_url: String,
    network: APINetwork,
) -> Result<String> {
    use bdk_electrum::electrum_client::ElectrumApi;

    let secp = Secp256k1::new();
    let net: Network = network.into();

    let priv_key = PrivateKey::from_wif(&wif).map_err(|e| anyhow::anyhow!("Invalid WIF: {}", e))?;
    let compressed_pub = CompressedPublicKey::from_private_key(&secp, &priv_key)
        .map_err(|_| anyhow::anyhow!("Only compressed WIF keys are supported"))?;
    let pub_key = PublicKey::from_private_key(&secp, &priv_key);

    // Collect all UTXOs for this key.
    let utxos = query_wif_utxos(wif, network, electrum_url.clone()).await?;
    if utxos.is_empty() {
        return Err(anyhow::anyhow!("No unspent outputs found for this WIF key"));
    }

    let total_input_sat: u64 = utxos.iter().map(|u| u.value_sat).sum();

    // Parse destination address.
    let dest_addr = Address::from_str(&destination_address)
        .map_err(|e| {
            anyhow::anyhow!(
                "Invalid destination address '{}': {}",
                destination_address,
                e
            )
        })?
        .require_network(net)
        .map_err(|_| anyhow::anyhow!("Destination address does not match wallet network"))?;
    let dest_spk = dest_addr.script_pubkey();

    // Estimate fee.
    let fee_sat = estimate_sweep_fee(&utxos, &dest_spk, fee_rate_sat_per_vb);
    if fee_sat >= total_input_sat {
        return Err(anyhow::anyhow!(
            "Insufficient funds: total {} sat, estimated fee {} sat",
            total_input_sat,
            fee_sat
        ));
    }
    let output_sat = total_input_sat - fee_sat;

    // Build unsigned transaction.
    let inputs: Vec<TxIn> = utxos
        .iter()
        .map(|u| -> anyhow::Result<TxIn> {
            let txid = Txid::from_str(&u.txid)
                .map_err(|e| anyhow::anyhow!("invalid txid from Electrum '{}': {e}", u.txid))?;
            Ok(TxIn {
                previous_output: OutPoint::new(txid, u.vout),
                script_sig: ScriptBuf::new(),
                sequence: Sequence::ENABLE_RBF_NO_LOCKTIME,
                witness: Witness::new(),
            })
        })
        .collect::<anyhow::Result<Vec<_>>>()?;

    let outputs = vec![TxOut {
        value: Amount::from_sat(output_sat),
        script_pubkey: dest_spk,
    }];

    let mut tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: inputs,
        output: outputs,
    };

    // Sign each input.
    for (i, utxo) in utxos.iter().enumerate() {
        let utxo_addr = Address::from_str(&utxo.address)
            .map_err(|e| anyhow::anyhow!("invalid address '{}': {e}", utxo.address))?
            .require_network(net)
            .map_err(|e| anyhow::anyhow!("address network mismatch for '{}': {e}", utxo.address))?;
        let utxo_spk = utxo_addr.script_pubkey();
        let value = Amount::from_sat(utxo.value_sat);

        match utxo.address_type.as_str() {
            "p2wpkh" => {
                sign_p2wpkh_input(&secp, &priv_key, &pub_key, &mut tx, i, &utxo_spk, value)?;
            }
            "p2pkh" => {
                sign_p2pkh_input(&secp, &priv_key, &pub_key, &mut tx, i, &utxo_spk)?;
            }
            "p2sh_wpkh" => {
                sign_p2sh_wpkh_input(
                    &secp,
                    &priv_key,
                    &pub_key,
                    &compressed_pub,
                    &mut tx,
                    i,
                    value,
                )?;
            }
            other => {
                return Err(anyhow::anyhow!("Unsupported input type: {}", other));
            }
        }
    }

    // Broadcast.
    let client = create_raw_electrum_client(&electrum_url)?;
    let txid = client
        .transaction_broadcast(&tx)
        .map_err(|e| anyhow::anyhow!("Broadcast failed: {}", e))?;

    Ok(txid.to_string())
}

// ---------------------------------------------------------------------------
// Signing helpers
// ---------------------------------------------------------------------------

fn make_ecdsa_sig(
    secp: &Secp256k1<bdk_wallet::bitcoin::secp256k1::All>,
    priv_key: &PrivateKey,
    sighash_bytes: &[u8],
) -> Result<bdk_wallet::bitcoin::ecdsa::Signature> {
    let msg = Message::from_digest_slice(sighash_bytes)
        .map_err(|e| anyhow::anyhow!("Invalid sighash length: {}", e))?;
    let sig = secp.sign_ecdsa(&msg, &priv_key.inner);
    Ok(bdk_wallet::bitcoin::ecdsa::Signature {
        signature: sig,
        sighash_type: EcdsaSighashType::All,
    })
}

fn sign_p2wpkh_input(
    secp: &Secp256k1<bdk_wallet::bitcoin::secp256k1::All>,
    priv_key: &PrivateKey,
    pub_key: &PublicKey,
    tx: &mut Transaction,
    input_index: usize,
    script_pubkey: &ScriptBuf,
    value: Amount,
) -> Result<()> {
    let sighash = SighashCache::new(&*tx)
        .p2wpkh_signature_hash(
            input_index,
            script_pubkey.as_script(),
            value,
            EcdsaSighashType::All,
        )
        .map_err(|e| anyhow::anyhow!("P2WPKH sighash error: {}", e))?;

    let sig = make_ecdsa_sig(secp, priv_key, sighash.as_ref())?;
    tx.input[input_index].witness = Witness::from_slice(&[
        sig.serialize().to_vec().as_slice(),
        pub_key.inner.serialize().as_slice(),
    ]);
    Ok(())
}

fn sign_p2pkh_input(
    secp: &Secp256k1<bdk_wallet::bitcoin::secp256k1::All>,
    priv_key: &PrivateKey,
    pub_key: &PublicKey,
    tx: &mut Transaction,
    input_index: usize,
    script_pubkey: &ScriptBuf,
) -> Result<()> {
    let sighash = SighashCache::new(&*tx)
        .legacy_signature_hash(
            input_index,
            script_pubkey.as_script(),
            EcdsaSighashType::All.to_u32(),
        )
        .map_err(|e| anyhow::anyhow!("P2PKH sighash error: {}", e))?;

    let sig = make_ecdsa_sig(secp, priv_key, sighash.as_ref())?;

    // script_sig: <DER-sig> <compressed-pubkey>
    let script_sig = ScriptBuf::builder()
        .push_slice(sig.serialize())
        .push_key(pub_key)
        .into_script();
    tx.input[input_index].script_sig = script_sig;
    Ok(())
}

fn sign_p2sh_wpkh_input(
    secp: &Secp256k1<bdk_wallet::bitcoin::secp256k1::All>,
    priv_key: &PrivateKey,
    pub_key: &PublicKey,
    compressed_pub: &CompressedPublicKey,
    tx: &mut Transaction,
    input_index: usize,
    value: Amount,
) -> Result<()> {
    // Redeem script = P2WPKH scriptPubKey (OP_0 <hash160(compressed_pub)>).
    let redeem_script = ScriptBuf::new_p2wpkh(&compressed_pub.wpubkey_hash());

    // script_sig: <push(redeemScript)>
    let redeem_bytes =
        bdk_wallet::bitcoin::script::PushBytesBuf::try_from(redeem_script.as_bytes().to_vec())
            .map_err(|e| anyhow::anyhow!("Redeem script encoding error: {}", e))?;
    tx.input[input_index].script_sig = ScriptBuf::builder().push_slice(&redeem_bytes).into_script();

    // Witness signing uses the redeem_script as the scriptCode (it IS a P2WPKH script).
    sign_p2wpkh_input(
        secp,
        priv_key,
        pub_key,
        tx,
        input_index,
        &redeem_script,
        value,
    )
}

// ---------------------------------------------------------------------------
// Fee estimation
// ---------------------------------------------------------------------------

/// Estimate transaction size in vbytes for a sweep (all UTXOs → 1 output).
fn estimate_sweep_fee(utxos: &[APIWifUtxo], dest_spk: &ScriptBuf, fee_rate: f64) -> u64 {
    // Base tx overhead: version(4) + locktime(4) + vin_count(1) + vout_count(1) = 10 bytes.
    // Segwit adds 0.5 vbyte overhead (marker + flag divided by 4).
    let has_segwit = utxos
        .iter()
        .any(|u| u.address_type == "p2wpkh" || u.address_type == "p2sh_wpkh");
    let overhead_vb: f64 = if has_segwit { 10.5 } else { 10.0 };

    // Per-input vbyte estimates (witness bytes divided by 4 for discount):
    //   P2WPKH:     41 base + 108 witness → (41×4 + 108) / 4 ≈ 68 vbytes
    //   P2PKH:      148 vbytes (no witness)
    //   P2SH-P2WPKH: 64 base + 108 witness → (64×4 + 108) / 4 ≈ 91 vbytes
    let input_vb: f64 = utxos
        .iter()
        .map(|u| match u.address_type.as_str() {
            "p2wpkh" => 68.0_f64,
            "p2pkh" => 148.0_f64,
            "p2sh_wpkh" => 91.0_f64,
            _ => 148.0_f64,
        })
        .sum();

    // Output: 8 bytes (value) + scriptPubKey length + 1 byte (length prefix).
    let output_vb: f64 = 9.0 + dest_spk.len() as f64;

    let total_vb = overhead_vb + input_vb + output_vb;
    (total_vb * fee_rate).ceil() as u64
}
