use crate::core::spend_path::SpendPath;
use crate::core::wallet::WalletType;
use anyhow::Result;
use bdk_wallet::bitcoin::Network;

/// BIP-65 threshold: nLockTime values strictly below this are block heights;
/// values at or above are Unix timestamps.
pub(crate) const LOCK_TIME_THRESHOLD: u32 = 500_000_000;

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

///////////////////////////
// APIProtectionType     //
///////////////////////////

/// Which protection scheme wraps the per-wallet data key.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum APIProtectionType {
    /// Wrapped with the device key (automatic, no password needed).
    DeviceKey,
    /// Wrapped with a key derived from a user password (Argon2id).
    UserPassword,
    /// Each xpub in the descriptor has its own slot; any one can unlock.
    XpubKey,
}

/// One registered xpub slot in a XpubKey-protected wallet.
#[derive(Debug, Clone)]
pub struct APIXpubSlot {
    /// Master fingerprint (8-char lowercase hex).
    pub mfp: String,
    /// Derivation path suffix stored as a display hint (e.g. "48h/0h/0h/2h").
    /// Empty for legacy slots.
    pub derivation_hint: String,
}

/// One registered biometric slot in a UserPassword or XpubKey wallet.
#[derive(Debug, Clone)]
pub struct APIBiometricSlot {
    /// UUID v4 — used as the key identifier in the platform keystore.
    pub id: String,
}

/// Protection information returned as part of `APIWalletInfo`.
#[derive(Debug, Clone)]
pub struct APIWalletProtection {
    pub protection_type: APIProtectionType,
    /// True when this wallet requires a credential (password or xpub) to open.
    pub needs_password: bool,
    /// The Argon2id security level in use (DeviceKey wallets always report Standard).
    pub security_level: APISecurityLevel,
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
    pub created_at: i64,
    pub last_synced_at: Option<i64>,
    pub protection: APIWalletProtection,
    /// SHA-256 hex of the first external receive address. Only present for locked
    /// (UserPassword / XpubKey) wallets; used to match against discovered accounts
    /// during seed recovery without revealing the descriptor or xpub.
    pub first_address_hash: Option<String>,
}

///////////////////
// APIWalletType //
///////////////////
#[derive(Debug, Clone, Copy, PartialEq)]
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
        } else if consensus < LOCK_TIME_THRESHOLD {
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
                if self.value >= LOCK_TIME_THRESHOLD {
                    return Err(crate::core::error::WalletError::BuilderError(
                        "Block height must be < 500,000,000".into(),
                    )
                    .into());
                }
                Ok(self.value)
            }
            APIAbsoluteTimelockType::Timestamp => {
                if self.value < LOCK_TIME_THRESHOLD {
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

    /// Per-MFP multipath lanes (every chain index this key contributes in this
    /// spend path). For canonical `<0;1>/*` this is `[0, 1]`; for non-canonical
    /// pairs like `<8;9>/*` it is `[8, 9]`. HW signing uses the full set to
    /// recognise UTXOs derived via either lane (e.g. change UTXOs whose path
    /// ends in the second component of the pair).
    pub key_changes: std::collections::HashMap<String, Vec<u32>>,

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
            key_changes: sp
                .key_changes
                .iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect(),
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
// APIFiatPrice   //
////////////////////

pub struct APIFiatPrice {
    pub txid: String,
    /// BTC price in the requested fiat currency at the time of the transaction.
    pub btc_price: f64,
}

///////////////////////
// APITxMissingFiat  //
///////////////////////

pub struct APITxMissingFiat {
    pub txid: String,
    /// Unix timestamp of confirmation; None for unconfirmed transactions.
    pub confirmation_time: Option<i64>,
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
    /// Unix timestamp of the block that confirmed this UTXO; None = unconfirmed.
    pub confirmation_time: Option<u64>,
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
// APIRecipient   //
////////////////////
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct APIRecipient {
    pub address: String,
    pub amount_sat: u64,
    /// When `Some`, this recipient is an OP_RETURN data carrier instead of a
    /// payment output. `address` is empty and `amount_sat` is ignored (forced to 0).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub op_return_data: Option<Vec<u8>>,
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
    pub recipients: Vec<APIRecipient>,
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
    /// Absolute nLockTime from the unsigned transaction (Height-based, < 500_000_000).
    /// 0 when no timelock is set. When > 0, the transaction cannot be broadcast
    /// until the chain tip reaches this block height.
    pub lock_time: u32,
    /// When true, this PSBT is queued to be broadcast automatically as soon as
    /// its timelock matures. Persisted per-wallet in `unsigned_txs`.
    pub auto_broadcast: bool,
}

/////////////////////////////
// APIAutoBroadcastResult  //
/////////////////////////////

/// Outcome of a single auto-broadcast attempt during
/// [`APIWallet::try_auto_broadcast_due`]. One entry is emitted per attempt
/// that produced an observable result (success or error). PSBTs whose
/// timelock has not yet matured are skipped silently.
#[derive(Clone)]
pub struct APIAutoBroadcastResult {
    /// PSBT row id at the time of the attempt.
    pub id: i64,
    /// Broadcast txid on success.
    pub txid: Option<String>,
    /// Error message on failure. `None` when [`txid`] is `Some`.
    pub error: Option<String>,
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
    /// Number of unconfirmed descendants that would also be evicted by the replacement.
    /// BIP-125 Rule 4 requires covering their fees too.
    pub descendant_count: u32,
    /// Sum of fees of all unconfirmed descendants (sats).
    /// None if any descendant's input values are unknown (Electrum fetch was not attempted
    /// for descendants — the UI should treat the minimum as a lower bound in that case).
    pub descendant_fee_sat: Option<u64>,
    /// Total virtual size of all unconfirmed descendants (vbytes).
    pub descendant_vsize: u32,
    /// Minimum absolute fee for a replacement tx (BIP-125 Rule 4 / PaysForRBF).
    /// = sum(orig_fee + descendant_fees) + orig_vsize × 1 sat/vB
    /// orig_vsize is used as a proxy for new_vsize (unknown at query time).
    /// The Dart layer refines this with the actual new tx vsize.
    pub min_fee_sat: u64,
    /// Minimum fee rate the replacement must strictly exceed (ImprovesFeerateDiagram).
    /// = package_rate(orig + descendants) when descendants are known; orig_rate otherwise.
    pub min_fee_rate_sat_per_vb: f64,
}

//////////////////
// APICpfpInfo  //
//////////////////
#[derive(Clone, Debug)]
pub struct APICpfpInfo {
    /// Total fee of all unconfirmed ancestor txs (sats). None if any ancestor fee is unknown.
    pub ancestor_fee_sat: Option<u64>,
    /// Total virtual size of all unconfirmed ancestor txs (vbytes).
    pub ancestor_vsize: u32,
    /// Ancestor fee rate (sat/vB): ancestor_fee / ancestor_vsize. 0.0 if fee unknown.
    pub ancestor_fee_rate_sat_per_vb: f64,
    /// Number of unconfirmed ancestor txs in the package (including direct parents).
    pub ancestor_count: u32,
}

/////////////////////
// APITxPreview    //
/////////////////////
/// Preview of an unsigned transaction before persisting a PSBT.
///
/// All amounts are in sats. `fee_rate_sat_per_vb` is the back-computed effective rate
/// even when the caller passed an absolute fee. `total_wu` is BDK's actual weight for the
/// resulting tx (drain or change present). `has_change` is true when a change output was added.
///
/// `insufficient_funds` is set instead of returning an error so the UI can render
/// gracefully while the user is still typing. Other fields hold sentinel zeros in that case.
///
/// `recipients` contains the canonical-encoded recipient addresses (parsed by BDK) and the
/// final amounts — for the drain recipient the amount reflects what BDK actually assigned.
///
/// `rbf_min_fee_sats` is the minimum absolute fee (BIP-125 Rule 4 / PaysForRBF) that the
/// replacement tx must strictly exceed, computed from the conflict cluster and the actual
/// new tx vsize. None when no RBF conflicts were declared.
#[derive(Clone)]
pub struct APITxPreview {
    pub fee_sats: u64,
    pub fee_rate_sat_per_vb: f64,
    pub change_sats: u64,
    pub send_sats: u64,
    pub total_wu: u64,
    pub has_change: bool,
    pub insufficient_funds: bool,
    pub recipients: Vec<APIRecipient>,
    pub rbf_min_fee_sats: Option<u64>,
}

//////////////////////////
// APIPsbtSignerStatus  //
//////////////////////////
#[derive(Clone, Debug)]
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
#[derive(Clone, Default)]
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
    /// When `Some`, this output is an OP_RETURN data carrier; `address` is empty
    /// and `value_sat` is 0 (Bitcoin standardness).
    pub op_return_data: Option<Vec<u8>>,
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

//////////////////////
// APISecurityLevel //
//////////////////////

/// Argon2id brute-force resistance level for backup export and change-protection.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum APISecurityLevel {
    /// m=65536 (64 MB), t=5 — ~300 ms on mobile. Good for interactive unlocking.
    Standard,
    /// m=262144 (256 MB), t=6 — ~1.6 s on mobile. Requires deliberate effort.
    High,
    /// m=524288 (512 MB), t=10 — ~5.5 s on mobile. For long-term key storage.
    Extreme,
}

impl APISecurityLevel {
    pub fn m_cost(self) -> u32 {
        match self {
            Self::Standard => 65536,
            Self::High => 262144,
            Self::Extreme => 524288,
        }
    }

    pub fn t_cost(self) -> u32 {
        match self {
            Self::Standard => 5,
            Self::High => 6,
            Self::Extreme => 10,
        }
    }

    /// Infer level from stored m_cost (best match; defaults to Standard).
    pub fn from_m_cost(m_cost: u32) -> Self {
        if m_cost >= 524288 {
            Self::Extreme
        } else if m_cost >= 262144 {
            Self::High
        } else {
            Self::Standard
        }
    }
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

////////////////////
// APIHotKeyInfo  //
////////////////////

/// Metadata about a hot signing key stored inside the wallet.
/// The seed itself is never exposed via FFI — only the MFP and type.
#[derive(Clone)]
pub struct APIHotKeyInfo {
    /// Master fingerprint (8 lowercase hex chars).
    pub mfp: String,
    /// "mnemonic" or "xprv".
    pub seed_type: String,
    /// Unix timestamp (seconds) when this key was added.
    pub created_at: i64,
}

////////////////////
// APIHotKeyList  //
////////////////////

pub struct APIHotKeyList {
    /// Successfully loaded hot keys.
    pub keys: Vec<APIHotKeyInfo>,
    /// Error messages for seed entries that could not be loaded from the database.
    pub corrupt_rows: Vec<String>,
}

////////////////////////////
// APIDescriptorSig       //
////////////////////////////

/// A stored descriptor ownership signature for one participating key.
#[derive(Clone)]
pub struct APIDescriptorSig {
    /// Master fingerprint (8 lowercase hex chars) of the signing key.
    pub mfp: String,
    /// Full descriptor key entry, e.g. `[aabbccdd/48'/0'/0'/2']xpub…`
    pub xpub_entry: String,
    /// Signature type, determines the verification algorithm: "bip322" | "message"
    pub sig_method: String,
    /// Unix timestamp (seconds) when the signature was created.
    pub signed_at: i64,
    /// Whether the signature currently passes verification against the stored descriptor.
    pub is_valid: bool,
}

///////////////////////
// APIAccountInfo    //
///////////////////////

/// One BIP44-style account discovered during a seed scan.
pub struct APIAccountInfo {
    pub account_index: u32,
    /// e.g. "84'/0'/3'"
    pub derivation_path: String,
    /// "[mfp/84'/0'/3']xpub…"
    pub keyspec: String,
    pub wallet_type: APIWalletType,
    /// First external receive address (m/0/0). Used for wallet matching.
    pub first_address: String,
    pub tx_count: u32,
    pub balance_sat: u64,
}

/// Result of [discover_accounts].
pub struct APIDiscoveredAccounts {
    pub accounts: Vec<APIAccountInfo>,
    /// Total number of accounts scanned (including empty ones).
    pub scanned_count: u32,
}

/////////////////////
// APISpacedPlan…  //
/////////////////////

/// Input parameters for `plan_spaced_txs`.
///
/// The plan's `kind` is derived inside Rust from `dst_wallet_path`: empty
/// or equal to the source wallet's own path → `REFRESH`, anything else →
/// `MIGRATE`. The label is only used for history rendering; the planning
/// logic itself is identical for both modes.
#[derive(Clone)]
pub struct APISpacedPlanParams {
    pub dst_wallet_path: String,
    /// Human-readable destination wallet name. Optional snapshot taken
    /// at plan time so `Migrate` child PSBTs/transactions carry a label
    /// that names the destination (e.g. `"→ Cold: <coin label>"`).
    /// Ignored for `Refresh` plans; `None` keeps the legacy label
    /// format. Renames after plan creation do NOT propagate.
    pub dst_wallet_name: Option<String>,
    pub feerate_min_msatvb: u64,
    pub feerate_max_msatvb: u64,
    pub delay_blocks_min: u32,
    pub delay_blocks_max: u32,
    pub split_probability: f64,
    pub min_split_output: u64,
    pub spend_path_id: u32,
    pub threshold: u32,
    pub mfps: Vec<String>,
    pub policy_path: Vec<APIPolicyPath>,
    /// Pre-peeked destination addresses. Caller must supply at least
    /// `eligible_utxo_count` entries — one per UTXO. Excess addresses are
    /// ignored. v1 builds 1-output txs; split (2-output) support lands in
    /// a follow-up step and will consume 2 addresses per split tx.
    pub dst_addresses: Vec<String>,
    /// Optional allow-list of UTXOs (txid:vout). Empty = every confirmed UTXO.
    pub selected_utxos: Vec<APICoinControl>,
    /// Optional seed for deterministic planning (UI re-roll, tests). `None`
    /// = OS RNG.
    pub rng_seed: Option<u64>,
}

#[derive(Clone, Debug)]
pub struct APISpacedPlanRow {
    pub psbt_id: i64,
    pub utxo_txid: String,
    pub utxo_vout: u32,
    pub amount_sat: u64,
    pub conf_height: Option<u32>,
    pub nlocktime_delta_blocks: u32,
    /// Absolute block height (tip_height + delta) at which auto-broadcast
    /// will fire. Useful for UI ETAs.
    pub abs_nlocktime: u32,
    pub feerate_sat_per_vb: f64,
    pub fee_sat: u64,
    pub net_out_sat: u64,
    /// 1 entry for a single-output tx; 2 entries when `split == true`.
    pub recipient_addresses: Vec<String>,
    /// Parallel to `recipient_addresses` — the per-output amount BDK
    /// actually assigned. Reading these is preferable to reverse-engineering
    /// the split from `net_out_sat` × `split_ratio`.
    pub recipient_amounts_sat: Vec<u64>,
    /// True when this row was emitted as 2 outputs to break the
    /// change-output heuristic (§3 split rule).
    pub split: bool,
    /// Target ratio used to sample the split (≈ first-output share). The
    /// realised ratio may differ slightly because BDK pays the fee from
    /// the drain output. `None` when `split == false`.
    pub split_ratio: Option<f64>,
    /// "Inheritable" label derived from the source UTXO — its effective
    /// coin label, or a generated fallback (see `default_plan_label`).
    /// In `Refresh` plans this is also what gets written onto the
    /// PSBT/tx row; in `Migrate` plans the PSBT/tx itself carries the
    /// fixed `"Migration → <wallet_name>"` string instead, and this
    /// field is only used by the cubit to seed the destination
    /// wallet's `address_labels` (the source DB can't reach the dst).
    pub label: String,
}

/// Full read of a spaced TX plan and its (still-pending) child PSBTs.
///
/// Once a child PSBT auto-broadcasts, its `unsigned_txs` row is deleted
/// by `try_auto_broadcast_one`. The running view should correlate the
/// missing rows with the wallet's tx history (or with the
/// `autoBroadcasted` events emitted by `WalletSyncService`).
#[derive(Clone, Debug)]
pub struct APISpacedPlanDetailRow {
    pub psbt_id: i64,
    pub utxo_txid: String,
    pub utxo_vout: u32,
    pub amount_sat: u64,
    pub fee_sat: u64,
    pub abs_nlocktime: u32,
    pub auto_broadcast: bool,
    pub has_spent_inputs: bool,
    pub recipients: Vec<APIRecipient>,
}

#[derive(Clone, Debug)]
pub struct APISpacedPlanDetail {
    pub plan_id: i64,
    pub kind: String,
    pub dst_wallet_path: String,
    pub status: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub feerate_min_msatvb: u64,
    pub feerate_max_msatvb: u64,
    pub delay_blocks_min: u32,
    pub delay_blocks_max: u32,
    pub split_probability: f64,
    pub min_split_output: u64,
    pub spend_path_id: u32,
    /// Children still in `unsigned_txs` (i.e. not yet broadcast).
    pub rows: Vec<APISpacedPlanDetailRow>,
}

#[derive(Clone, Debug)]
pub struct APICommitSpacedPlanReport {
    pub plan_id: i64,
    /// `true` when every child PSBT was fully signed and the plan moved to
    /// `SIGNED`. `false` when at least one PSBT lacks signatures — caller
    /// shows `unsigned_psbt_ids` so the user can finish signing.
    pub committed: bool,
    pub total_count: u32,
    pub signed_count: u32,
    pub unsigned_psbt_ids: Vec<i64>,
}

#[derive(Clone, Debug)]
pub struct APISpacedPlanSummary {
    pub plan_id: i64,
    pub tip_height: u32,
    pub rows: Vec<APISpacedPlanRow>,
    pub total_amount_sat: u64,
    pub total_fee_sat: u64,
    pub dropped_utxo_count: u32,
}

/// One auto-label entry handed to
/// [`APIWallet::set_spaced_plan_address_labels`] so the cubit can seed
/// the destination wallet's `address_labels` for a `Migrate` plan.
///
/// `source_entity` is reconstructed inside Rust from `(plan_id,
/// src_txid, src_vout)` to keep the encoding canonical and to let
/// `clear_spaced_plan_labels(plan_id)` sweep these rows on cancel.
#[derive(Clone, Debug)]
pub struct APISpacedPlanAddressLabel {
    pub plan_id: i64,
    pub src_txid: String,
    pub src_vout: u32,
    pub address: String,
    pub label: String,
}

/// One child PSBT of a spaced plan, packed for batch signing.
///
/// Returned by `prepare_spaced_plan_psbts` so the cubit/UI can drive a
/// single signing ceremony over every row without re-reading the wallet
/// once per PSBT.
#[derive(Clone, Debug)]
pub struct APISpacedPlanChildPsbt {
    pub psbt_id: i64,
    pub psbt_b64: String,
    pub signers: Vec<APIPsbtSignerStatus>,
    pub is_finalized: bool,
}

/// One signed PSBT in a batch handed back to
/// `apply_spaced_plan_signed_psbts`. `psbt_id` must reference a child of
/// the target plan or the call rejects with an error before any merge
/// runs.
#[derive(Clone, Debug)]
pub struct APISignedChildPsbt {
    pub psbt_id: i64,
    pub signed_b64: String,
}

/// Result of a batch sign / merge operation. The cubit feeds this into
/// the draft view's per-row badges (✓ / ✗ / ⌛) without re-reading the
/// plan.
///
/// `signed_ids` lists ids whose updated PSBT row now carries the new
/// signatures; `failed` lists ids that errored out, with the underlying
/// message. The two lists never overlap. Ids that the caller did not
/// touch in this batch are absent from both.
#[derive(Clone, Debug)]
pub struct APIBatchSignReport {
    pub plan_id: i64,
    pub total: u32,
    pub signed_ids: Vec<i64>,
    pub failed: Vec<APIBatchSignFailure>,
}

#[derive(Clone, Debug)]
pub struct APIBatchSignFailure {
    pub psbt_id: i64,
    pub error: String,
}

/// Plan-level signing context (descriptor + policy info) plus every
/// pending child PSBT. Plan-level fields are hoisted out of the per-row
/// struct because they are constant for the whole plan.
#[derive(Clone, Debug)]
pub struct APISpacedPlanSigningBundle {
    pub plan_id: i64,
    pub descriptor: String,
    pub network: APINetwork,
    pub threshold: u32,
    pub mfps: Vec<String>,
    /// Per-MFP multipath lanes for the plan's spend path. Mirrors
    /// `APISpendPath.key_changes` and feeds straight into the HW
    /// signing sheet (`keyChanges` parameter) for multi-leaf taproot.
    pub key_changes: std::collections::HashMap<String, Vec<u32>>,
    pub children: Vec<APISpacedPlanChildPsbt>,
}

// ─── KeychainKind ↔ APIKeychain ──────────────────────────────────────────────

impl From<bdk_wallet::KeychainKind> for APIKeychain {
    fn from(k: bdk_wallet::KeychainKind) -> Self {
        match k {
            bdk_wallet::KeychainKind::External => APIKeychain::External,
            bdk_wallet::KeychainKind::Internal => APIKeychain::Internal,
        }
    }
}

impl From<APIKeychain> for bdk_wallet::KeychainKind {
    fn from(k: APIKeychain) -> Self {
        match k {
            APIKeychain::External => bdk_wallet::KeychainKind::External,
            APIKeychain::Internal => bdk_wallet::KeychainKind::Internal,
        }
    }
}

#[cfg(test)]
#[path = "model_tests.rs"]
mod tests;
