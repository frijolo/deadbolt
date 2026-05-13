use super::*;
use tempfile::tempdir;

const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

fn make_wallet(dir: &tempfile::TempDir) -> Result<APIWalletInfo> {
    let wallets_dir = dir.path().to_string_lossy().to_string();
    create_wallet(
        wallets_dir,
        "Test Wallet".to_string(),
        MAINNET_DESC.to_string(),
        APINetwork::Bitcoin,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )
}

#[test]
fn test_create_wallet_returns_info() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;

    assert_eq!(info.name, "Test Wallet");
    assert_eq!(info.network, APINetwork::Bitcoin);
    assert!(info.wallet_path.ends_with(".db"));
    assert!(std::path::Path::new(&info.wallet_path).exists());
    Ok(())
}

#[test]
fn test_open_wallet_get_balance() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;

    let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None)?;
    let balance = handle.get_balance()?;

    assert_eq!(balance.confirmed, 0);
    assert_eq!(balance.trusted_pending, 0);
    assert_eq!(balance.untrusted_pending, 0);
    assert_eq!(balance.immature, 0);
    Ok(())
}

#[test]
fn test_open_wallet_get_transactions_empty() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;

    let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None)?;
    let page = handle.get_transactions(0, 20)?;

    assert_eq!(page.total_count, 0);
    assert!(page.transactions.is_empty());
    assert!(!page.has_more);
    Ok(())
}

#[test]
fn test_open_wallet_get_transactions_page_beyond_total() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;

    let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None)?;
    let page = handle.get_transactions(10, 20)?;

    assert_eq!(page.total_count, 0);
    assert!(page.transactions.is_empty());
    assert!(!page.has_more);
    Ok(())
}

#[test]
fn test_open_wallet_balance_consistent_across_calls() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;

    let handle = open_wallet(info.wallet_path, KEY_HEX.to_string(), None, None)?;
    let b1 = handle.get_balance()?;
    let b2 = handle.get_balance()?;

    assert_eq!(b1.confirmed, b2.confirmed);
    Ok(())
}

#[test]
fn test_open_wallet_get_info() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;

    let handle = open_wallet(info.wallet_path.clone(), KEY_HEX.to_string(), None, None)?;
    let fetched = handle.get_info()?;

    assert_eq!(fetched.name, "Test Wallet");
    assert_eq!(fetched.network, APINetwork::Bitcoin);
    assert_eq!(fetched.wallet_path, info.wallet_path);
    Ok(())
}

#[test]
fn test_list_wallets() -> Result<()> {
    let dir = tempdir()?;
    let wallets_dir = dir.path().to_string_lossy().to_string();

    create_wallet(
        wallets_dir.clone(),
        "W1".to_string(),
        MAINNET_DESC.to_string(),
        APINetwork::Bitcoin,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )?;
    create_wallet(
        wallets_dir.clone(),
        "W2".to_string(),
        MAINNET_DESC.to_string(),
        APINetwork::Bitcoin,
        KEY_HEX.to_string(),
        APIProtectionType::DeviceKey,
        None,
        APISecurityLevel::Standard,
    )?;

    let list = list_wallets(wallets_dir, KEY_HEX.to_string())?;
    assert_eq!(list.len(), 2);
    Ok(())
}

#[test]
fn test_rename_wallet() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;

    rename_wallet(
        info.wallet_path.clone(),
        "Renamed".to_string(),
        KEY_HEX.to_string(),
        None,
    )?;

    let updated = get_wallet_info(info.wallet_path, KEY_HEX.to_string(), None)?;
    assert_eq!(updated.name, "Renamed");
    Ok(())
}

#[test]
fn test_delete_wallet_removes_file() -> Result<()> {
    let dir = tempdir()?;
    let info = make_wallet(&dir)?;
    let path = info.wallet_path.clone();

    assert!(std::path::Path::new(&path).exists());

    delete_wallet(path.clone())?;

    assert!(!std::path::Path::new(&path).exists());
    Ok(())
}

impl APIWallet {
    /// Inject a transaction into the wallet graph as **unconfirmed** (seen_at=1).
    /// Used by unit tests to set up wallet state without a real Electrum sync.
    pub(crate) fn inject_unconfirmed_tx(&self, tx: bdk_wallet::bitcoin::Transaction) -> Result<()> {
        use bdk_wallet::chain::TxUpdate;
        use bdk_wallet::Update;
        use std::sync::Arc;
        let txid = tx.compute_txid();
        let mut core = self.lock_wallet()?;
        let mut tx_update = TxUpdate::default();
        tx_update.txs = vec![Arc::new(tx)];
        tx_update.seen_ats = [(txid, 1_000_000_u64)].into();
        core.wallet.apply_update(Update {
            tx_update,
            ..Default::default()
        })?;
        Ok(())
    }

    /// Inject a transaction into the wallet graph with **no chain position**
    /// (not confirmed, not seen as unconfirmed). The tx is only present in the
    /// graph for txout lookups — it does NOT appear in `wallet.transactions()`.
    pub(crate) fn inject_graph_tx(&self, tx: bdk_wallet::bitcoin::Transaction) -> Result<()> {
        use bdk_wallet::chain::TxUpdate;
        use bdk_wallet::Update;
        use std::sync::Arc;
        let mut core = self.lock_wallet()?;
        let mut tx_update = TxUpdate::default();
        tx_update.txs = vec![Arc::new(tx)];
        core.wallet.apply_update(Update {
            tx_update,
            ..Default::default()
        })?;
        Ok(())
    }
}

mod generate_mnemonic_tests {
    use super::super::generate_mnemonic;
    use bdk_wallet::keys::bip39::{Language, Mnemonic};

    #[test]
    fn rejects_invalid_word_count() {
        for n in [0u8, 1, 11, 13, 15, 18, 21, 23, 25, 255] {
            assert!(
                generate_mnemonic(n).is_err(),
                "word_count {n} should be rejected"
            );
        }
    }

    #[test]
    fn produces_12_words_with_valid_checksum() {
        let phrase = generate_mnemonic(12).expect("generate 12");
        assert_eq!(phrase.split_whitespace().count(), 12);
        let parsed = Mnemonic::parse(&phrase).expect("valid BIP39 mnemonic with checksum");
        assert_eq!(parsed.to_string(), phrase);
    }

    #[test]
    fn produces_24_words_with_valid_checksum() {
        let phrase = generate_mnemonic(24).expect("generate 24");
        assert_eq!(phrase.split_whitespace().count(), 24);
        let parsed = Mnemonic::parse(&phrase).expect("valid BIP39 mnemonic with checksum");
        assert_eq!(parsed.to_string(), phrase);
    }

    #[test]
    fn all_words_are_in_bip39_english_wordlist() {
        let wordlist = Language::English.word_list();
        for count in [12u8, 24] {
            let phrase = generate_mnemonic(count).expect("generate");
            for word in phrase.split_whitespace() {
                assert!(
                    wordlist.contains(&word),
                    "word `{word}` not in BIP39 English wordlist"
                );
            }
        }
    }

    #[test]
    fn successive_calls_produce_distinct_mnemonics() {
        // Smoke test that the RNG is actually random. With 128+ bits of entropy
        // the collision probability is negligible; a repeat would indicate a
        // broken pipeline.
        let a = generate_mnemonic(12).expect("a");
        let b = generate_mnemonic(12).expect("b");
        let c = generate_mnemonic(24).expect("c");
        let d = generate_mnemonic(24).expect("d");
        assert_ne!(a, b);
        assert_ne!(c, d);
    }
}
