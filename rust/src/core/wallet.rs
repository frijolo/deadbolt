use std::ops::Deref;

use crate::core::descriptor_parser::DescriptorParser;
use crate::core::error::WalletError;
use crate::core::pubkey::PubKey;
use crate::core::spend_path::SpendPath;

use anyhow::Result;
use bdk_wallet::bitcoin::Network;
use bdk_wallet::miniscript::descriptor::ShInner;
use bdk_wallet::miniscript::Descriptor;
use bdk_wallet::rusqlite::Connection;
use bdk_wallet::{KeychainKind, PersistedWallet, Wallet};

#[derive(Debug)]
pub struct CoreWallet {
    pub descriptor: String,
    pub bdk_wallet: BDKWallet,
    pub spend_paths: Option<Vec<SpendPath>>,
    pub keys: Option<Vec<PubKey>>,
}

#[derive(Debug)]
pub enum BDKWallet {
    Temporal(Wallet),
    Rusqlite(PersistedWallet<Connection>),
}

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

impl CoreWallet {
    pub fn new_temporal(network: Network, descriptor: &String) -> Result<CoreWallet> {
        let wallet = Wallet::create_from_two_path_descriptor(descriptor.clone())
            .network(network)
            .create_wallet_no_persist()?;

        Ok(CoreWallet {
            descriptor: descriptor.clone(),
            bdk_wallet: BDKWallet::Temporal(wallet),
            spend_paths: None,
            keys: None
        })
    }

    pub fn new_persisted(network: Network, descriptor: &String) -> Result<CoreWallet> {
        let mut mem = Connection::open("")?;

        let wallet = Wallet::create_from_two_path_descriptor(descriptor.clone())
            .network(network)
            .create_wallet(&mut mem)?;

        Ok(CoreWallet {
            descriptor: descriptor.clone(),
            bdk_wallet: BDKWallet::Rusqlite(wallet),
            spend_paths: None,
            keys:None
        })
    }

    pub fn network_from_descriptor(descriptor: &String) -> Result<Network> {
        // NEW: Use DescriptorParser for network detection
        // This eliminates up to 5 wallet creations (one per network variant)
        // For mainnet descriptors: 0 wallets created (uses xpub prefix)
        // For testnet descriptors: 1-4 wallets created (still better than 5)
        let parser = DescriptorParser::parse(descriptor)?;
        parser.detect_network()
    }

    pub fn wallet(&self) -> &Wallet {
        match &self.bdk_wallet {
            BDKWallet::Temporal(w) => w,
            BDKWallet::Rusqlite(w) => w.deref(),
        }
    }

    pub fn network(&self) -> Network {
        self.wallet().network()
    }

    pub fn wallet_type(&self) -> WalletType {
        let descriptor = self.wallet().public_descriptor(KeychainKind::External);
        match descriptor {
            Descriptor::Pkh(_) => WalletType::P2PKH,
            Descriptor::Sh(sh) => match sh.as_inner() {
                ShInner::Wsh(_) => WalletType::P2SH_WSH,
                ShInner::Wpkh(_) => WalletType::P2SH_WPKH,
                _ => WalletType::P2SH,
            },
            Descriptor::Wpkh(_) => WalletType::P2WPKH,
            Descriptor::Wsh(_) => WalletType::P2WSH,
            Descriptor::Tr(_) => WalletType::P2TR,
            _ => WalletType::Unknown,
        }
    }

    pub fn spend_paths(&mut self) -> Result<&Vec<SpendPath>> {
        if self.spend_paths.is_none() {
            self.spend_paths = Some(SpendPath::extract_spend_paths(&self.wallet())?);
        }
        Ok(self
            .spend_paths
            .as_ref()
            .ok_or(WalletError::MissingPolicy)?)
    }

    pub fn keys(&mut self) -> Result<&Vec<PubKey>> {
        if self.keys.is_none() {
            self.keys = Some(PubKey::extract_pub_keys(&self.wallet())?);
        }
        Ok(self
            .keys
            .as_ref()
            .ok_or(WalletError::MissingFingerprint)?)
    }
}
