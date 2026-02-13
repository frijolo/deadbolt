use crate::core::spend_path::SpendPath;
use crate::core::wallet::WalletType;
use anyhow::Result;
use bdk_wallet::bitcoin::Network;

////////////////
// APINetwork //
////////////////
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum APINetwork {
    Bitcoin,
    Testnet,
    Testnet4,
    Signet,
    Regtest,
}

impl From<Network> for APINetwork {
    fn from(sp: Network) -> Self {
        match sp {
            Network::Bitcoin => APINetwork::Bitcoin,
            Network::Testnet => APINetwork::Testnet,
            Network::Testnet4 => APINetwork::Testnet4,
            Network::Regtest => APINetwork::Regtest,
            Network::Signet => APINetwork::Signet,
        }
    }
}

impl From<APINetwork> for Network {
    fn from(val: APINetwork) -> Self {
        match val {
            APINetwork::Bitcoin => Network::Bitcoin,
            APINetwork::Testnet => Network::Testnet,
            APINetwork::Testnet4 => Network::Testnet4,
            APINetwork::Regtest => Network::Regtest,
            APINetwork::Signet => Network::Signet,
        }
    }
}

///////////////////
// APIWalletType //
///////////////////
#[derive(Debug, Clone, PartialEq)]
pub enum APIWalletType {
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

impl From<WalletType> for APIWalletType {
    fn from(wallet_type: WalletType) -> Self {
        match wallet_type {
            WalletType::P2PKH => APIWalletType::P2PKH,
            WalletType::P2WPKH => APIWalletType::P2WPKH,
            WalletType::P2SH => APIWalletType::P2SH,
            WalletType::P2WSH => APIWalletType::P2WSH,
            WalletType::P2TR => APIWalletType::P2TR,
            WalletType::P2SH_WPKH => APIWalletType::P2SH_WPKH,
            WalletType::P2SH_WSH => APIWalletType::P2SH_WSH,
            WalletType::Unknown => APIWalletType::Unknown,
        }
    }
}

impl From<APIWalletType> for WalletType {
    fn from(val: APIWalletType) -> Self {
        match val {
            APIWalletType::P2PKH => WalletType::P2PKH,
            APIWalletType::P2WPKH => WalletType::P2WPKH,
            APIWalletType::P2SH => WalletType::P2SH,
            APIWalletType::P2WSH => WalletType::P2WSH,
            APIWalletType::P2TR => WalletType::P2TR,
            APIWalletType::P2SH_WPKH => WalletType::P2SH_WPKH,
            APIWalletType::P2SH_WSH => WalletType::P2SH_WSH,
            APIWalletType::Unknown => WalletType::Unknown,
        }
    }
}

//////////////////
// APISpendPath //
//////////////////
#[derive(Clone, Default)]
pub struct APISpendPath {
    pub id: u32,
    pub policy_path: Vec<APIPolicyPath>,
    pub threshold: u32,
    pub mfps: Vec<String>,
    pub rel_timelock: u32,
    pub abs_timelock: u32,

    pub wu_base: u32,
    pub wu_in: u32,
    pub wu_out: u32,

    pub tr_depth: i32,

    // Calculated
    pub vb_sweep: f32,
}

impl TryFrom<&SpendPath> for APISpendPath {
    type Error = anyhow::Error;

    fn try_from(sp: &SpendPath) -> Result<Self> {
        Ok(Self {
            id: sp.id,
            policy_path: APIPolicyPath::from_spendpath(sp)?,
            threshold: sp.threshold as u32,
            mfps: sp.mfps.clone(),
            rel_timelock: sp.rel_timelock,
            abs_timelock: sp.abs_timelock,
            wu_base: sp.wu_base,
            wu_in: sp.wu_in,
            wu_out: sp.wu_out,
            tr_depth: (sp.tr_depth as i32) - 1,
            vb_sweep: sp.estimate_tx_vb(1, 1),
        })
    }
}

impl APISpendPath {
    pub fn from_sorted(core_spend_paths: &[SpendPath]) -> Result<Vec<APISpendPath>> {
        let mut api_spend_paths: Vec<APISpendPath> = core_spend_paths
            .iter()
            .map(APISpendPath::try_from)
            .collect::<Result<Vec<APISpendPath>>>()?;

        api_spend_paths.sort_by(|a, b| {
            let tl_a = a.rel_timelock + a.abs_timelock;
            let tl_b = b.rel_timelock + b.abs_timelock;
            tl_a.cmp(&tl_b).then_with(|| {
                let wu_a = a.wu_base + a.wu_in + a.wu_out;
                let wu_b = b.wu_base + b.wu_in + b.wu_out;
                wu_a.cmp(&wu_b)
            })
        });

        Ok(api_spend_paths)
    }
}

#[derive(Clone, Default)]
pub struct APIPolicyPath {
    pub policy_id: String,
    pub path: Vec<u32>,
}

impl APIPolicyPath {
    pub fn from_spendpath(spend_path: &SpendPath) -> Result<Vec<APIPolicyPath>> {
        let mut res = Vec::new();
        for (policy_id, path) in &spend_path.policy_path {
            let path_u32: Vec<u32> = path
                .iter()
                .map(|&x| u32::try_from(x))
                .collect::<Result<Vec<u32>, _>>()?;
            res.push(APIPolicyPath {
                policy_id: policy_id.clone(),
                path: path_u32,
            });
        }
        Ok(res)
    }
}

//////////////////////
// APISpendPathDef //
//////////////////////
#[derive(Clone)]
pub struct APISpendPathDef {
    pub threshold: u32,
    pub mfps: Vec<String>,
    pub rel_timelock: u32,
    pub abs_timelock: u32,
    pub is_key_path: bool,
}

///////////////
// APIPubKey //
///////////////
#[derive(Clone)]
pub struct APIPubKey {
    pub mfp: String,
    pub derivation_path: String,
    pub xpub: String,
}
