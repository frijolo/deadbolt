use super::*;
use crate::api::wallet::descriptor_backup::{extract_raw_from_tapscript, vault_tapscript};

#[tokio::test]
#[ignore]
async fn debug_fetch_onchain_backup_signet() {
    let xpub = "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K".to_string();
    let electrum = "ssl://mempool.space:60602".to_string();
    let result = fetch_onchain_backup(xpub, electrum, "signet".to_string()).await;
    println!("\n=== fetch_onchain_backup result ===");
    match &result {
        Ok(backups) => {
            println!("Found {} backup(s)", backups.len());
            for (i, b) in backups.iter().enumerate() {
                println!("  [{}] commit_txid:    {}", i, b.commit_txid);
                println!("  [{}] reveal_txid:    {:?}", i, b.reveal_txid);
                println!("  [{}] wallet_name:    {:?}", i, b.wallet_name);
                println!("  [{}] network:        {:?}", i, b.network);
                println!("  [{}] created_at:     {:?}", i, b.created_at);
                println!("  [{}] first_address:  {:?}", i, b.first_address);
                println!("  [{}] wallet_type:    {:?}", i, b.wallet_type);
                println!("  [{}] descriptor:     {:?}", i, b.descriptor);
                println!(
                    "  [{}] anchors:        {}/{}",
                    i, b.anchors_reachable, b.anchors_total
                );
                println!("  [{}] bytes len:      {}", i, b.bytes.len());
            }
        }
        Err(e) => println!("Error: {e}"),
    }
    println!("===================================\n");
    assert!(result.is_ok());
}

#[tokio::test]
#[ignore]
async fn debug_fetch_nostr_backup_signet() {
    use crate::api::wallet::nostr_backup::fetch_nostr_backup;
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();

    let xpub = "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K".to_string();
    let relays = vec![
        "wss://relay.damus.io".to_string(),
        "wss://nos.lol".to_string(),
    ];
    let result = fetch_nostr_backup(xpub, relays).await;
    println!("\n=== fetch_nostr_backup result ===");
    match &result {
        Ok(backups) => {
            println!("Found {} backup(s)", backups.len());
            for (i, b) in backups.iter().enumerate() {
                println!("  [{}] wallet_name:   {:?}", i, b.wallet_name);
                println!("  [{}] network:       {:?}", i, b.network);
                println!("  [{}] created_at:    {:?}", i, b.created_at);
                println!("  [{}] first_address: {:?}", i, b.first_address);
                println!("  [{}] wallet_type:   {:?}", i, b.wallet_type);
                println!(
                    "  [{}] descriptor:    {:?}",
                    i,
                    b.descriptor.as_deref().map(|d| &d[..d.len().min(60)])
                );
                println!("  [{}] bytes len:     {}", i, b.bytes.len());
            }
        }
        Err(e) => println!("Error: {e}"),
    }
    println!("=================================\n");
    assert!(result.is_ok());
}

#[tokio::test]
#[ignore]
async fn debug_discover_singlesig_signet() {
    use crate::api::model::{APINetwork, APIWalletType};
    use crate::api::wallet::discovery::{discover_accounts_from_keyspecs, APIWalletTypeKeyspecs};

    let xpub = "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K".to_string();
    let electrum = "ssl://mempool.space:60602".to_string();
    let keyspecs_by_type = vec![
        APIWalletTypeKeyspecs {
            wallet_type: APIWalletType::P2PKH,
            keyspecs: vec![xpub.clone()],
        },
        APIWalletTypeKeyspecs {
            wallet_type: APIWalletType::P2SH_WPKH,
            keyspecs: vec![xpub.clone()],
        },
        APIWalletTypeKeyspecs {
            wallet_type: APIWalletType::P2WPKH,
            keyspecs: vec![xpub.clone()],
        },
        APIWalletTypeKeyspecs {
            wallet_type: APIWalletType::P2TR,
            keyspecs: vec![xpub.clone()],
        },
    ];
    let result =
        discover_accounts_from_keyspecs(keyspecs_by_type, APINetwork::Signet, electrum, 20).await;
    println!("\n=== discover_accounts_from_keyspecs result ===");
    match &result {
        Ok(r) => {
            println!("scanned_count: {}", r.scanned_count);
            println!("accounts found: {}", r.accounts.len());
            for (i, a) in r.accounts.iter().enumerate() {
                println!(
                    "  [{}] type={:?}  path={}  first_address={}  tx={}  bal={}",
                    i, a.wallet_type, a.derivation_path, a.first_address, a.tx_count, a.balance_sat
                );
            }
        }
        Err(e) => println!("Error: {e}"),
    }
    println!("==============================================\n");
    assert!(result.is_ok());
}

#[test]
fn extract_raw_from_tapscript_small() {
    // Protocol always stores zstd-compressed data in the tapscript.
    let payload = b"hello";
    let mut enc = zstd::stream::write::Encoder::new(Vec::new(), 22).unwrap();
    std::io::Write::write_all(&mut enc, payload).unwrap();
    let compressed = enc.finish().unwrap();

    let ts = vault_tapscript(&compressed);
    let result = extract_raw_from_tapscript(ts.as_bytes()).unwrap();
    assert_eq!(result, payload);
}

#[test]
fn extract_raw_rejects_malformed_tapscript() {
    // Missing OP_1 header — should fail.
    let result = extract_raw_from_tapscript(&[0x00, 0x63, 0x68]);
    assert!(result.is_err());
}
