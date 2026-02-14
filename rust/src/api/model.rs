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

///////////////////////////
// Timelock Types & Enums //
///////////////////////////

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum APIAbsoluteTimelockType {
    Blocks,
    Timestamp,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum APIRelativeTimelockType {
    Blocks,
    Time,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct APIAbsoluteTimelock {
    pub timelock_type: APIAbsoluteTimelockType,
    pub value: u32,
}

impl APIAbsoluteTimelock {
    pub fn from_consensus(consensus: u32) -> Self {
        if consensus == 0 {
            Self { timelock_type: APIAbsoluteTimelockType::Blocks, value: 0 }
        } else if consensus < 500_000_000 {
            Self { timelock_type: APIAbsoluteTimelockType::Blocks, value: consensus }
        } else {
            Self { timelock_type: APIAbsoluteTimelockType::Timestamp, value: consensus }
        }
    }

    pub fn to_consensus(&self) -> Result<u32> {
        // 0 means no timelock, valid for any type
        if self.value == 0 {
            return Ok(0);
        }

        match self.timelock_type {
            APIAbsoluteTimelockType::Blocks => {
                if self.value >= 500_000_000 {
                    return Err(crate::core::error::WalletError::BuilderError(
                        "Block height must be < 500,000,000".into()
                    ).into());
                }
                Ok(self.value)
            }
            APIAbsoluteTimelockType::Timestamp => {
                if self.value < 500_000_000 {
                    return Err(crate::core::error::WalletError::BuilderError(
                        "Timestamp must be >= 500,000,000".into()
                    ).into());
                }
                Ok(self.value)
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct APIRelativeTimelock {
    pub timelock_type: APIRelativeTimelockType,
    pub value: u32,
}

impl APIRelativeTimelock {
    const TYPE_FLAG: u32 = 0x00400000;
    const SEQUENCE_LOCKTIME_MASK: u32 = 0x0000FFFF;

    pub fn from_consensus(consensus: u32) -> Self {
        if consensus == 0 {
            Self { timelock_type: APIRelativeTimelockType::Blocks, value: 0 }
        } else if (consensus & Self::TYPE_FLAG) == 0 {
            let blocks = consensus & Self::SEQUENCE_LOCKTIME_MASK;
            Self { timelock_type: APIRelativeTimelockType::Blocks, value: blocks }
        } else {
            let units = consensus & Self::SEQUENCE_LOCKTIME_MASK;
            let seconds = units * 512;
            Self { timelock_type: APIRelativeTimelockType::Time, value: seconds }
        }
    }

    pub fn to_consensus(&self) -> Result<u32> {
        // 0 means no timelock, valid for any type
        if self.value == 0 {
            return Ok(0);
        }

        match self.timelock_type {
            APIRelativeTimelockType::Blocks => {
                if self.value > Self::SEQUENCE_LOCKTIME_MASK {
                    return Err(crate::core::error::WalletError::BuilderError(
                        format!("Block count must be <= {}", Self::SEQUENCE_LOCKTIME_MASK)
                    ).into());
                }
                Ok(self.value)
            }
            APIRelativeTimelockType::Time => {
                let units = (self.value + 511) / 512; // Round up
                if units > Self::SEQUENCE_LOCKTIME_MASK {
                    return Err(crate::core::error::WalletError::BuilderError(
                        format!("Time value too large (max {} seconds)", Self::SEQUENCE_LOCKTIME_MASK * 512)
                    ).into());
                }
                Ok(units | Self::TYPE_FLAG)
            }
        }
    }
}

//////////////////
// APISpendPath //
//////////////////
#[derive(Clone)]
pub struct APISpendPath {
    pub id: u32,
    pub policy_path: Vec<APIPolicyPath>,
    pub threshold: u32,
    pub mfps: Vec<String>,
    pub rel_timelock: APIRelativeTimelock,
    pub abs_timelock: APIAbsoluteTimelock,

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
            rel_timelock: APIRelativeTimelock::from_consensus(sp.rel_timelock),
            abs_timelock: APIAbsoluteTimelock::from_consensus(sp.abs_timelock),
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
            // Use consensus values for sorting
            let tl_a = a.rel_timelock.to_consensus().unwrap_or(0)
                     + a.abs_timelock.to_consensus().unwrap_or(0);
            let tl_b = b.rel_timelock.to_consensus().unwrap_or(0)
                     + b.abs_timelock.to_consensus().unwrap_or(0);
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
    pub rel_timelock: APIRelativeTimelock,
    pub abs_timelock: APIAbsoluteTimelock,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_absolute_blocks_roundtrip() {
        let original = APIAbsoluteTimelock {
            timelock_type: APIAbsoluteTimelockType::Blocks,
            value: 800_000,
        };
        let consensus = original.to_consensus().unwrap();
        let decoded = APIAbsoluteTimelock::from_consensus(consensus);
        assert_eq!(decoded, original);
    }

    #[test]
    fn test_absolute_timestamp_roundtrip() {
        let original = APIAbsoluteTimelock {
            timelock_type: APIAbsoluteTimelockType::Timestamp,
            value: 1704067200,
        };
        let consensus = original.to_consensus().unwrap();
        let decoded = APIAbsoluteTimelock::from_consensus(consensus);
        assert_eq!(decoded, original);
    }

    #[test]
    fn test_relative_blocks_roundtrip() {
        let original = APIRelativeTimelock {
            timelock_type: APIRelativeTimelockType::Blocks,
            value: 144,
        };
        let consensus = original.to_consensus().unwrap();
        let decoded = APIRelativeTimelock::from_consensus(consensus);
        assert_eq!(decoded, original);
    }

    #[test]
    fn test_relative_time_roundtrip() {
        let original = APIRelativeTimelock {
            timelock_type: APIRelativeTimelockType::Time,
            value: 86400, // 1 day
        };
        let consensus = original.to_consensus().unwrap();
        let decoded = APIRelativeTimelock::from_consensus(consensus);
        // May differ slightly due to 512-second granularity
        assert!((decoded.value as i32 - original.value as i32).abs() < 512);
    }

    #[test]
    fn test_absolute_blocks_validation() {
        let invalid = APIAbsoluteTimelock {
            timelock_type: APIAbsoluteTimelockType::Blocks,
            value: 500_000_000,
        };
        assert!(invalid.to_consensus().is_err());
    }

    #[test]
    fn test_absolute_timestamp_validation() {
        let invalid = APIAbsoluteTimelock {
            timelock_type: APIAbsoluteTimelockType::Timestamp,
            value: 499_999_999,
        };
        assert!(invalid.to_consensus().is_err());
    }
}
