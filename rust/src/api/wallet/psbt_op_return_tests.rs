//! Tests for OP_RETURN support in create_psbt / preview_psbt and helpers.
//!
//! Reuses the helpers defined in `psbt_tests.rs` indirectly by re-creating a
//! minimal wallet harness here; we deliberately do not import that module to
//! keep this test file self-contained per `feedback_rust_test_files.md`.

use super::*;
use crate::api::model::{APICoinControl, APIPolicyPath, APIRecipient};
use crate::core::descriptor::DescriptorAnalyzer;
use crate::test_support::{KEY_HEX, SIGNET_INHERITANCE_DESC};
use bdk_wallet::bitcoin::{absolute, transaction, Amount, OutPoint, Sequence, Transaction, TxIn};
use bdk_wallet::KeychainKind;
use tempfile::tempdir;

fn make_wallet(dir: &tempfile::TempDir) -> APIWallet {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    let info = create_wallet(
        wallets_dir,
        "Test".to_string(),
        SIGNET_INHERITANCE_DESC.to_string(),
        APINetwork::Signet,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )
    .expect("create_wallet failed");
    open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None).expect("open_wallet failed")
}

fn inject_utxo(wallet: &APIWallet) -> bdk_wallet::bitcoin::Txid {
    let spk = {
        let core = wallet.lock_wallet().unwrap();
        core.wallet
            .peek_address(KeychainKind::External, 0)
            .address
            .script_pubkey()
    };
    let fake_prev = OutPoint {
        txid: bdk_wallet::bitcoin::Txid::from_raw_hash(
            *bdk_wallet::bitcoin::hashes::sha256d::Hash::from_bytes_ref(&[7u8; 32]),
        ),
        vout: 0,
    };
    let funding_tx = Transaction {
        version: transaction::Version::TWO,
        lock_time: absolute::LockTime::ZERO,
        input: vec![TxIn {
            previous_output: fake_prev,
            sequence: Sequence::MAX,
            ..Default::default()
        }],
        output: vec![bdk_wallet::bitcoin::TxOut {
            value: Amount::from_sat(1_000_000),
            script_pubkey: spk,
        }],
    };
    let txid = funding_tx.compute_txid();
    wallet
        .inject_unconfirmed_tx(funding_tx)
        .expect("inject_unconfirmed_tx failed");
    txid
}

fn owner_path() -> crate::core::spend_path::SpendPath {
    DescriptorAnalyzer::analyze(SIGNET_INHERITANCE_DESC)
        .unwrap()
        .spend_paths()
        .unwrap()
        .into_iter()
        .find(|sp| sp.rel_timelock == 0 && sp.abs_timelock == 0)
        .expect("owner spend path not found")
}

fn recv_addr(wallet: &APIWallet) -> String {
    let core = wallet.lock_wallet().unwrap();
    core.wallet
        .peek_address(KeychainKind::External, 1)
        .address
        .to_string()
}

#[test]
fn test_create_psbt_with_op_return_payload() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_path();
    let recv = recv_addr(&wallet);

    let payload = b"deadbolt-test".to_vec();
    let info = wallet.create_psbt(
        vec![
            APIRecipient {
                address: recv,
                amount_sat: 100_000,
                op_return_data: None,
            },
            APIRecipient {
                address: String::new(),
                amount_sat: 0,
                op_return_data: Some(payload.clone()),
            },
        ],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
        None,
    )?;

    // Decode the PSBT and verify there is exactly one OP_RETURN output with our payload.
    use bdk_wallet::bitcoin::psbt::Psbt;
    use std::str::FromStr;
    let psbt = Psbt::from_str(&info.psbt_base64)?;
    let op_return_outputs: Vec<_> = psbt
        .unsigned_tx
        .output
        .iter()
        .filter(|o| o.script_pubkey.is_op_return())
        .collect();
    assert_eq!(op_return_outputs.len(), 1, "exactly one OP_RETURN output");
    assert_eq!(op_return_outputs[0].value, Amount::ZERO);

    // Extract the pushed bytes and check they match.
    use bdk_wallet::bitcoin::script::Instruction;
    let mut pushed = Vec::new();
    for instr in op_return_outputs[0].script_pubkey.instructions().flatten() {
        if let Instruction::PushBytes(pb) = instr {
            pushed.extend_from_slice(pb.as_bytes());
        }
    }
    assert_eq!(pushed, payload);

    // The returned APIPsbtInfo's recipients list must surface the OP_RETURN entry too.
    assert_eq!(info.recipients.len(), 2);
    let or = info
        .recipients
        .iter()
        .find(|r| r.op_return_data.is_some())
        .expect("OP_RETURN recipient missing in APIPsbtInfo");
    assert_eq!(or.op_return_data.as_deref(), Some(payload.as_slice()));
    assert_eq!(or.amount_sat, 0);
    assert!(or.address.is_empty());
    Ok(())
}

#[test]
fn test_create_psbt_rejects_two_op_returns() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_path();
    let recv = recv_addr(&wallet);

    let result = wallet.create_psbt(
        vec![
            APIRecipient {
                address: recv,
                amount_sat: 100_000,
                op_return_data: None,
            },
            APIRecipient {
                address: String::new(),
                amount_sat: 0,
                op_return_data: Some(b"first".to_vec()),
            },
            APIRecipient {
                address: String::new(),
                amount_sat: 0,
                op_return_data: Some(b"second".to_vec()),
            },
        ],
        None,
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
        None,
    );

    let err = match result {
        Ok(_) => panic!("two OP_RETURN outputs must be rejected"),
        Err(e) => e,
    };
    let msg = err.to_string().to_lowercase();
    assert!(
        msg.contains("op_return") || msg.contains("only one"),
        "{msg}"
    );
    Ok(())
}

#[test]
fn test_create_psbt_rejects_op_return_as_max_recipient() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_path();

    let result = wallet.create_psbt(
        vec![APIRecipient {
            address: String::new(),
            amount_sat: 0,
            op_return_data: Some(b"hello".to_vec()),
        }],
        Some(0),
        1_000,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        sp.threshold as u32,
        sp.mfps.clone(),
        None,
    );

    let err = match result {
        Ok(_) => panic!("OP_RETURN cannot drain wallet"),
        Err(e) => e,
    };
    let msg = err.to_string().to_lowercase();
    assert!(
        msg.contains("op_return") && msg.contains("remaining"),
        "{msg}"
    );
    Ok(())
}

#[test]
fn test_preview_psbt_with_op_return_returns_payload() -> anyhow::Result<()> {
    let dir = tempdir()?;
    let wallet = make_wallet(&dir);
    let funding_txid = inject_utxo(&wallet);
    let sp = owner_path();
    let recv = recv_addr(&wallet);

    let payload = vec![0xf0, 0x00, 0xba, 0xad, 0xde, 0xad];
    let preview = wallet.preview_psbt(
        vec![
            APIRecipient {
                address: recv,
                amount_sat: 200_000,
                op_return_data: None,
            },
            APIRecipient {
                address: String::new(),
                amount_sat: 0,
                op_return_data: Some(payload.clone()),
            },
        ],
        None,
        Some(2.0),
        None,
        vec![APICoinControl {
            txid: funding_txid.to_string(),
            vout: 0,
        }],
        APIPolicyPath::from_spendpath(&sp)?,
        sp.id,
        vec![],
    )?;

    assert!(!preview.insufficient_funds);
    let or = preview
        .recipients
        .iter()
        .find(|r| r.op_return_data.is_some())
        .expect("OP_RETURN recipient missing in preview");
    assert_eq!(or.op_return_data.as_deref(), Some(payload.as_slice()));
    assert_eq!(or.amount_sat, 0);
    Ok(())
}
