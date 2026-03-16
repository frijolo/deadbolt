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

impl APINetwork {
    /// Human-readable lowercase name for error messages and display.
    pub fn display_name(&self) -> &'static str {
        match self {
            APINetwork::Bitcoin => "mainnet",
            APINetwork::Testnet => "testnet",
            APINetwork::Testnet4 => "testnet4",
            APINetwork::Signet => "signet",
            APINetwork::Regtest => "regtest",
        }
    }

    /// Canonical serialization string stored in wallet_info.network column.
    pub fn as_str(&self) -> &'static str {
        match self {
            APINetwork::Bitcoin => "bitcoin",
            APINetwork::Testnet => "testnet",
            APINetwork::Testnet4 => "testnet4",
            APINetwork::Signet => "signet",
            APINetwork::Regtest => "regtest",
        }
    }
}

impl TryFrom<&str> for APINetwork {
    type Error = anyhow::Error;

    fn try_from(s: &str) -> Result<Self> {
        match s {
            "bitcoin" => Ok(APINetwork::Bitcoin),
            "testnet" => Ok(APINetwork::Testnet),
            "testnet4" => Ok(APINetwork::Testnet4),
            "signet" => Ok(APINetwork::Signet),
            "regtest" => Ok(APINetwork::Regtest),
            _ => Err(anyhow::anyhow!("Unknown network: {}", s)),
        }
    }
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
// APIWalletInfo //
///////////////////
#[derive(Clone)]
pub struct APIWalletInfo {
    pub wallet_path: String,
    pub name: String,
    pub descriptor: String,
    pub network: APINetwork,
    pub source_project_id: Option<i64>,
    pub created_at: i64,
    pub last_synced_at: Option<i64>,
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
            Self {
                timelock_type: APIAbsoluteTimelockType::Blocks,
                value: 0,
            }
        } else if consensus < 500_000_000 {
            Self {
                timelock_type: APIAbsoluteTimelockType::Blocks,
                value: consensus,
            }
        } else {
            Self {
                timelock_type: APIAbsoluteTimelockType::Timestamp,
                value: consensus,
            }
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
                        "Block height must be < 500,000,000".into(),
                    )
                    .into());
                }
                Ok(self.value)
            }
            APIAbsoluteTimelockType::Timestamp => {
                if self.value < 500_000_000 {
                    return Err(crate::core::error::WalletError::BuilderError(
                        "Timestamp must be >= 500,000,000".into(),
                    )
                    .into());
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
            Self {
                timelock_type: APIRelativeTimelockType::Blocks,
                value: 0,
            }
        } else if (consensus & Self::TYPE_FLAG) == 0 {
            let blocks = consensus & Self::SEQUENCE_LOCKTIME_MASK;
            Self {
                timelock_type: APIRelativeTimelockType::Blocks,
                value: blocks,
            }
        } else {
            let units = consensus & Self::SEQUENCE_LOCKTIME_MASK;
            let seconds = units * 512;
            Self {
                timelock_type: APIRelativeTimelockType::Time,
                value: seconds,
            }
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
                    return Err(crate::core::error::WalletError::BuilderError(format!(
                        "Block count must be <= {}",
                        Self::SEQUENCE_LOCKTIME_MASK
                    ))
                    .into());
                }
                Ok(self.value)
            }
            APIRelativeTimelockType::Time => {
                let units = self.value.div_ceil(512);
                if units > Self::SEQUENCE_LOCKTIME_MASK {
                    return Err(crate::core::error::WalletError::BuilderError(format!(
                        "Time value too large (max {} seconds)",
                        Self::SEQUENCE_LOCKTIME_MASK * 512
                    ))
                    .into());
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
    /// Taproot script tree priority (0 = deepest/least likely, higher = shallower/more likely).
    /// Ignored for non-Taproot descriptors.
    pub priority: u32,
}

////////////////
// APIKeychain //
////////////////
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum APIKeychain {
    /// External keychain — receive addresses (<0>/*)
    External,
    /// Internal keychain — change addresses (<1>/*)
    Internal,
}

////////////////
// APIAddress //
////////////////
#[derive(Clone)]
pub struct APIAddress {
    pub address: String,
    pub index: u32,
    pub keychain: APIKeychain,
    pub balance_sat: u64,
    /// True if this address has appeared in at least one transaction output.
    pub is_used: bool,
    /// Number of transactions in which this address appears as an output.
    pub tx_count: u32,
    /// Explicit user-set label (use for editing).
    pub label: Option<String>,
    /// Display label — own label if set, otherwise propagated from a related entity.
    pub effective_label: Option<String>,
    /// True when `effective_label` is auto-propagated from a related entity, not explicitly set.
    pub is_auto: bool,
}

////////////////
// APIBalance //
////////////////
#[derive(Clone)]
pub struct APIBalance {
    pub confirmed: u64,
    pub trusted_pending: u64,
    pub untrusted_pending: u64,
    pub immature: u64,
}

////////////////////
// APITransaction //
////////////////////
#[derive(Clone)]
pub struct APITransaction {
    pub txid: String,
    pub received: u64,
    pub sent: u64,
    pub fee: Option<u64>,
    pub confirmation_height: Option<u32>,
    pub confirmation_time: Option<u64>, // Unix timestamp; None = unconfirmed
    /// Explicit user-set label (use for editing).
    pub label: Option<String>,
    /// Display label — own label if set, otherwise propagated from a related entity.
    pub effective_label: Option<String>,
    /// True when `effective_label` is auto-propagated from a related entity, not explicitly set.
    pub is_auto: bool,
}

/////////////////////////
// APITransactionPage  //
/////////////////////////
#[derive(Clone)]
pub struct APITransactionPage {
    pub transactions: Vec<APITransaction>,
    pub total_count: u32,
    pub has_more: bool,
}

////////////
// APIUtxo //
////////////
#[derive(Clone)]
pub struct APIUtxo {
    pub txid: String,
    pub vout: u32,
    pub value_sat: u64,
    pub keychain: APIKeychain,
    pub derivation_index: u32,
    pub address: String,
    pub is_confirmed: bool,
    pub confirmation_height: Option<u32>,
    /// Explicit user-set label (use for editing).
    pub label: Option<String>,
    /// Display label — own label if set, otherwise inherited from a related entity.
    pub effective_label: Option<String>,
    /// True when `effective_label` is auto-propagated from a related entity, not explicitly set.
    pub is_auto: bool,
    /// IDs of pending PSBTs (unsigned_txs.id) that spend this UTXO.
    /// Empty for most coins; populated by get_utxos().
    pub pending_psbt_ids: Vec<i64>,
    /// TXID of an unconfirmed (mempool) transaction that spends this UTXO, if any.
    /// Higher-priority indicator than pending_psbt_ids: the spend has already been broadcast.
    pub mempool_spending_txid: Option<String>,
}

////////////////////
// APIPsbtInfo    //
////////////////////
#[derive(Clone)]
pub struct APIPsbtInfo {
    pub id: i64,
    pub psbt_base64: String,
    /// Txid of the unsigned transaction (deterministic, independent of signatures).
    pub txid: String,
    /// Explicit user-set label (use for editing).
    pub label: Option<String>,
    /// Display label — own label if set, otherwise inherited from the recipient address.
    pub effective_label: Option<String>,
    /// True when `effective_label` is auto-propagated from the recipient address label.
    pub is_auto: bool,
    /// True when the recipient is one of this wallet's own addresses.
    pub is_self_transfer: bool,
    pub created_at: i64,
    pub recipient: String,
    pub amount_sat: u64,
    pub fee_sat: u64,
    pub spend_path_id: u32,
    pub threshold: u32,
    pub mfps: Vec<String>,
    /// Max confirmation height of the input UTXOs at PSBT creation time.
    /// Used to compute unlock block for relative timelocks:
    ///   unlock_block = utxo_max_conf_height + timelock_blocks
    pub utxo_max_conf_height: Option<i64>,
    /// True when at least one input of this PSBT has been confirmed-spent by
    /// another transaction. The PSBT can no longer be broadcast.
    pub has_spent_inputs: bool,
}

//////////////////////
// APIImportPsbt    //
//////////////////////

/// Returned by [APIWallet::import_psbt].
/// `was_merged` is true when the imported PSBT was combined with an existing record;
/// false when a brand-new record was created.
pub struct APIImportPsbtResult {
    pub psbt: APIPsbtInfo,
    pub was_merged: bool,
}

//////////////////////
// APICoinControl   //
//////////////////////
#[derive(Clone)]
pub struct APICoinControl {
    pub txid: String,
    pub vout: u32,
}

//////////////////
// APIRbfInfo   //
//////////////////
#[derive(Clone)]
pub struct APIRbfInfo {
    /// Fee paid by the original spending tx (sats).
    pub orig_fee_sat: u64,
    /// Virtual size of the original spending tx (vbytes).
    pub orig_vsize: u32,
    /// Fee rate of the original spending tx (sat/vB).
    pub orig_fee_rate_sat_per_vb: f64,
    /// Approximate minimum fee for a replacement tx.
    /// Two constraints apply (Dart takes the max):
    ///   Rule 4 (PaysForRBF):        orig_fee + new_vsize × 1 sat/vB
    ///   ImprovesFeerateDiagram:     orig_fee_rate × new_vsize  (rate must not decrease)
    /// Computed here with orig_vsize as a proxy for new_vsize (unknown at query time).
    /// The Dart layer refines both constraints with the actual new tx vsize.
    pub min_fee_sat: u64,
    /// Minimum fee rate the replacement must strictly exceed (ImprovesFeerateDiagram).
    /// Equal to orig_fee_rate_sat_per_vb — fixed, independent of the new tx's size.
    pub min_fee_rate_sat_per_vb: f64,
}

//////////////////////////
// APIPsbtSignerStatus  //
//////////////////////////
#[derive(Clone)]
pub struct APIPsbtSignerStatus {
    pub mfp: String,
    pub has_signed: bool,
}

/////////////////////
// APIPsbtAnalysis //
/////////////////////
#[derive(Clone)]
pub struct APIPsbtAnalysis {
    pub signers: Vec<APIPsbtSignerStatus>,
    pub is_finalized: bool,
}

//////////////////////
// Detail view types //
//////////////////////

/// Compact UTXO summary shown inside tx/address detail dialogs.
#[derive(Clone)]
pub struct APIRelatedUtxo {
    pub txid: String,
    pub vout: u32,
    pub address: String,
    pub value_sat: u64,
    /// Display label (own or propagated via the label inheritance system).
    pub effective_label: Option<String>,
    /// True when `effective_label` is auto-propagated, not explicitly set on this coin.
    pub is_auto: bool,
}

/// Compact transaction summary shown inside coin/address detail dialogs.
#[derive(Clone)]
pub struct APIRelatedTx {
    pub txid: String,
    /// Display label (own or propagated via the label inheritance system).
    pub effective_label: Option<String>,
    /// True when `effective_label` is auto-propagated, not explicitly set on this tx.
    pub is_auto: bool,
    pub confirmation_height: Option<u32>,
    /// Sats received by this specific address/coin in this tx.
    pub addr_received: u64,
    /// Sats spent from this specific address/coin in this tx.
    pub addr_spent: u64,
    pub fee: Option<u64>,
}

/// Output address entry shown inside a transaction detail dialog.
#[derive(Clone)]
pub struct APIRelatedAddress {
    pub address: String,
    /// Amount at this address in this transaction. None when the previous
    /// output could not be resolved (e.g. external input tx not in graph).
    pub value_sat: Option<u64>,
    /// Display label (own or propagated via the label inheritance system).
    pub effective_label: Option<String>,
    /// True when `effective_label` is auto-propagated, not explicitly set on this address.
    pub is_auto: bool,
    /// True if this address belongs to our wallet.
    pub is_mine: bool,
}

/// Full detail for a transaction.
#[derive(Clone)]
pub struct APITxDetails {
    pub tx: APITransaction,
    /// Unspent output coins created by this transaction.
    pub related_utxos: Vec<APIRelatedUtxo>,
    /// Input addresses (previous outputs spent by this transaction).
    pub input_addresses: Vec<APIRelatedAddress>,
    /// All output addresses of this transaction.
    pub output_addresses: Vec<APIRelatedAddress>,
}

/// Full detail for a UTXO.
#[derive(Clone)]
pub struct APIUtxoDetails {
    pub utxo: APIUtxo,
    /// Display label for this UTXO's address — own label if set, otherwise propagated.
    pub address_effective_label: Option<String>,
    /// True when `address_effective_label` is auto-propagated, not explicitly set on the address.
    pub address_label_is_auto: bool,
    /// The transaction that created this UTXO.
    pub creating_tx: APIRelatedTx,
}

/// Full detail for an address.
#[derive(Clone)]
pub struct APIAddressDetails {
    pub address: APIAddress,
    /// Unspent coins at this address.
    pub related_utxos: Vec<APIRelatedUtxo>,
    /// All transactions that sent to or spent from this address (unconfirmed first).
    pub related_txs: Vec<APIRelatedTx>,
}

////////////////////
// Hardware wallet //
////////////////////

/// A detected hardware wallet device (BitBox02 or similar).
pub struct APIHwDevice {
    /// Platform-specific device path used to open it (e.g. hidapi path on Linux).
    pub device_path: String,
    /// Human-readable product name, e.g. "BitBox02".
    pub product_string: String,
    /// USB serial number (may be empty).
    pub serial_number: String,
}

/// Result of [`connect_hw_device`] / [`connect_hw_device_android`].
pub struct APIHwConnectResult {
    /// Opaque session identifier used in subsequent hw_* calls.
    pub session_id: String,
    /// If `Some(code)`: show the code to the user and call `wait_hw_pairing`.
    /// If `None`: device was already paired; it is ready immediately.
    pub pairing_code: Option<String>,
}

/// Device info readable from a connected session via [`get_hw_session_info`]
/// or [`hw_active_session`].
pub struct APIHwSessionInfo {
    /// Opaque session identifier used for subsequent operations.
    pub session_id: String,
    /// Human-readable product name, e.g. "BitBox02".
    pub product_string: String,
    /// Root fingerprint (lowercase hex, 8 chars), e.g. "aabbccdd".
    /// Empty string if pairing has not been completed yet.
    pub root_fingerprint: String,
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
