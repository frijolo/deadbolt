use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use bdk_wallet::rusqlite::Connection;
use bdk_wallet::{KeychainKind, PersistedWallet, Wallet};
use std::sync::Arc;

use crate::core::seed::{
    make_private_descriptor, root_xprv_to_mfp, seed_entry_to_root_xprv, split_multipath_descriptor,
    strip_descriptor_checksum,
};
use crate::core::wallet_persistence::{list_seed_entries, load_or_create_wallet};

#[derive(Debug, Clone, PartialEq)]
pub enum WalletType {
    P2PKH,
    P2WPKH,
    P2SH,
    P2WSH,
    P2TR,
    #[allow(non_camel_case_types)]
    P2SH_WPKH,
    #[allow(non_camel_case_types)]
    P2SH_WSH,
    Unknown,
}

/// Live wallet handle: open once, reuse across multiple operations.
pub struct CoreWallet {
    pub wallet: PersistedWallet<Connection>,
    pub conn: Connection,
}

impl CoreWallet {
    /// Open (or create) the encrypted BDK wallet at `path`.
    pub fn open(path: &str, descriptor: &str, network: Network, key_hex: &str) -> Result<Self> {
        let (wallet, conn) = load_or_create_wallet(path, descriptor, network, key_hex)?;
        Ok(Self { wallet, conn })
    }

    /// Persist any pending wallet state to the SQLite file.
    pub fn persist(&mut self) -> Result<bool> {
        Ok(self.wallet.persist(&mut self.conn)?)
    }

    /// Load private-key signers from stored seed entries into the wallet's signer set.
    ///
    /// Clears any previously loaded signers first, then re-adds one signer per matching
    /// seed entry. Call this after opening the wallet and after any seed entry change.
    pub fn load_signers(&mut self, descriptor: &str, network: Network) -> Result<()> {
        use bdk_wallet::bitcoin::secp256k1::Secp256k1;
        #[allow(deprecated)]
        use bdk_wallet::signer::SignerOrdering;

        // Clear existing signers for both keychains so refresh works correctly.
        self.wallet
            .set_keymap(KeychainKind::External, Default::default());
        self.wallet
            .set_keymap(KeychainKind::Internal, Default::default());

        let seeds = list_seed_entries(&self.conn)?;
        let secp = Secp256k1::new();

        for seed in &seeds {
            let root_xprv = seed_entry_to_root_xprv(
                &seed.seed_type,
                seed.mnemonic.as_deref(),
                &seed.passphrase,
                seed.xprv.as_deref(),
                network,
            )?;

            let mfp = root_xprv_to_mfp(&root_xprv, &secp);
            if !descriptor.contains(&mfp) {
                continue;
            }

            let private_desc = match make_private_descriptor(descriptor, &root_xprv, &secp) {
                Ok(d) => d,
                Err(_) => continue,
            };
            // Strip checksum — xpub→xprv replacement invalidates it.
            let private_desc = strip_descriptor_checksum(&private_desc);

            // Build a temporary wallet just to extract properly-contextualized signers.
            // The temp wallet is never used for signing — its sole purpose is to let BDK
            // create SignerWrapper instances with the correct SignerContext (Segwitv0, Tap, etc.)
            // based on the private descriptor.
            //
            // BDK cannot create a wallet from a multi-path descriptor that contains an xprv
            // (any `<n;m>` suffix with a private key trips a miniscript limitation). We split
            // the two-path descriptor into a standard external+internal pair first.
            let (ext_desc, int_desc) = split_multipath_descriptor(&private_desc);
            let temp = match Wallet::create(ext_desc, int_desc)
                .network(network)
                .create_wallet_no_persist()
            {
                Ok(w) => w,
                Err(_) => continue,
            };

            // Copy signers into the main wallet (which has the synced address index).
            for keychain in [KeychainKind::External, KeychainKind::Internal] {
                #[allow(deprecated)]
                for signer in temp.get_signers(keychain).signers() {
                    #[allow(deprecated)]
                    self.wallet
                        .add_signer(keychain, SignerOrdering(200), Arc::clone(signer));
                }
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use bdk_wallet::bitcoin::{
        absolute::LockTime, transaction::Version, Amount, OutPoint, Sequence, Transaction, TxIn,
        TxOut,
    };
    use bdk_wallet::{KeychainKind, Update};
    use std::sync::Arc;
    use tempfile::tempdir;

    const KEY_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
    const TESTNET_DESC: &str = "wpkh([ff81be5d/84'/1'/0']tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf/<0;1>/*)";
    const TEST_MNEMONIC: &str =
        "piece blue stadium control fiction kick group mimic hollow dog mask interest";

    #[test]
    fn test_mnemonic_mfp_matches_descriptor() -> anyhow::Result<()> {
        use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
        let secp = Secp256k1::new();
        let xprv = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet)?;
        let mfp = root_xprv_to_mfp(&xprv, &secp);
        eprintln!("mfp={}", mfp);
        assert_eq!(mfp, "ff81be5d", "mnemonic MFP must match descriptor");
        Ok(())
    }

    #[test]
    fn test_load_signers_self_transfer() -> anyhow::Result<()> {
        use crate::core::wallet_persistence::{ensure_seed_entries_table, insert_seed_entry};
        use bdk_wallet::chain::TxUpdate;

        let dir = tempdir()?;
        let path = dir.path().join("wallet.db").to_string_lossy().to_string();
        let network = Network::Testnet;

        // 1. Open wallet with public descriptor
        let mut core = CoreWallet::open(&path, TESTNET_DESC, network, KEY_HEX)?;

        // 2. Store mnemonic as seed entry and load signers
        ensure_seed_entries_table(&core.conn)?;
        insert_seed_entry(
            &core.conn,
            "ff81be5d",
            "mnemonic",
            Some(TEST_MNEMONIC),
            "",
            None,
        )?;
        core.load_signers(TESTNET_DESC, network)?;

        // 3. Derive an address and insert a fake funding UTXO
        let addr = core.wallet.reveal_next_address(KeychainKind::External);
        eprintln!("receiving address: {}", addr.address);

        // Use a non-null previous_output so BDK doesn't treat this as a coinbase tx.
        let fake_prev = OutPoint {
            txid: bdk_wallet::bitcoin::Txid::from_raw_hash(
                *bdk_wallet::bitcoin::hashes::sha256d::Hash::from_bytes_ref(&[1u8; 32]),
            ),
            vout: 0,
        };
        let funding_tx = Transaction {
            version: Version::TWO,
            lock_time: LockTime::ZERO,
            input: vec![TxIn {
                previous_output: fake_prev,
                sequence: Sequence::MAX,
                ..Default::default()
            }],
            output: vec![TxOut {
                value: Amount::from_sat(100_000),
                script_pubkey: addr.address.script_pubkey(),
            }],
        };
        let txid = funding_tx.compute_txid();
        let seen_at = std::time::UNIX_EPOCH.elapsed().unwrap().as_secs();
        let mut tx_update = TxUpdate::default();
        tx_update.txs = vec![Arc::new(funding_tx)];
        tx_update.seen_ats = [(txid, seen_at)].into();
        core.wallet.apply_update(Update {
            tx_update,
            ..Default::default()
        })?;

        // 4. Build self-transfer PSBT
        let recv = core
            .wallet
            .reveal_next_address(KeychainKind::External)
            .address;
        let mut psbt = {
            let mut builder = core.wallet.build_tx();
            builder.add_recipient(recv.script_pubkey(), Amount::from_sat(50_000));
            builder.finish()?
        };
        eprintln!("PSBT inputs: {}", psbt.inputs.len());

        // 5. Sign using the main wallet's loaded signers
        #[allow(deprecated)]
        let finalized = core.wallet.sign(
            &mut psbt,
            bdk_wallet::SignOptions {
                trust_witness_utxo: true,
                ..Default::default()
            },
        )?;
        eprintln!("finalized={}", finalized);

        // Verify at least one signature was produced
        let has_sig = psbt.inputs[0].partial_sigs.len() > 0
            || psbt.inputs[0].final_script_witness.is_some()
            || psbt.inputs[0].final_script_sig.is_some();
        assert!(
            has_sig,
            "PSBT should have at least one signature after signing"
        );
        Ok(())
    }

    /// Verify that load_signers succeeds for a Taproot descriptor that contains
    /// multi-path derivation pairs beyond <0;1> (e.g. <2;3>, <4;5>).
    /// This exercises the regex-based multipath split introduced to fix the
    /// "Can't make an extended private key with multiple paths" error.
    #[test]
    fn test_load_signers_taproot_multi_derivation_index() -> anyhow::Result<()> {
        use crate::api::model::{APIAbsoluteTimelock, APIRelativeTimelock};
        use crate::core::descriptor_builder::{build_descriptor, SpendPathDef};
        use crate::core::pubkey::PubKey;
        use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
        use crate::core::wallet_persistence::{ensure_seed_entries_table, insert_seed_entry};

        let secp = Secp256k1::new();
        let root_xprv = mnemonic_to_root_xprv(TEST_MNEMONIC, "", Network::Testnet)?;
        let mfp = root_xprv_to_mfp(&root_xprv, &secp);

        // Derive account xpub at 86'/1'/0' (Taproot BIP-86 testnet)
        let path: bdk_wallet::bitcoin::bip32::DerivationPath = "m/86'/1'/0'".parse()?;
        let account_xprv = root_xprv.derive_priv(&secp, &path)?;
        let account_xpub = bdk_wallet::bitcoin::bip32::Xpub::from_priv(&secp, &account_xprv);

        // Build a PubKey via the canonical constructor
        let key = PubKey::new(&mfp, "86'/1'/0'", &account_xpub.to_string())?;

        // Two spend paths with the same key force derivation indices <0;1> and <2;3>.
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec![mfp.clone()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec![mfp.clone()],
                rel_timelock: APIRelativeTimelock::from_consensus(1008),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor =
            build_descriptor(crate::core::wallet::WalletType::P2TR, &[key], &spend_paths)?;
        eprintln!("Taproot descriptor: {}", descriptor);
        assert!(
            descriptor.contains("<2;3>"),
            "expected <2;3> in descriptor for second spend path: {}",
            descriptor
        );

        // Open wallet and verify load_signers succeeds (previously failed with:
        // "Can't make an extended private key with multiple paths into a public key")
        let dir = tempdir()?;
        let db = dir.path().join("wallet.db").to_string_lossy().to_string();
        let mut core = CoreWallet::open(&db, &descriptor, Network::Testnet, KEY_HEX)?;
        ensure_seed_entries_table(&core.conn)?;
        insert_seed_entry(&core.conn, &mfp, "mnemonic", Some(TEST_MNEMONIC), "", None)?;
        core.load_signers(&descriptor, Network::Testnet)?;

        Ok(())
    }
}
