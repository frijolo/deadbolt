// PSBT broadcast-maturity computation.
//
// Pure function over the data the wallet has already materialised in
// `APIPsbtInfo` + `APISpendPath`. Used by:
//   - the auto-broadcast loop (only proceeds when `is_ready()` returns true);
//   - tests, which can drive every branch without a live BDK wallet.
//
// Mirrors the UI logic in `lib/screens/psbt_detail_screen.dart`:
//   - Absolute blocks:    tip_height  >= info.lock_time
//   - Absolute timestamp: now_secs    >= info.lock_time
//   - Relative blocks:    tip_height + 1 >= utxo_max_conf_height + rel_blocks
//     (BIP68 validates against the candidate block tip+1, not the current tip.)
//   - Relative time:      not supported for auto-broadcast in v1.

use crate::api::model::{APIPsbtInfo, APIRelativeTimelockType, APISpendPath};
use flutter_rust_bridge::frb;

/// BIP-65 threshold: nLockTime values below this are block heights; values at
/// or above are Unix timestamps.
const LOCK_TIME_THRESHOLD: u32 = 500_000_000;

#[frb(ignore)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BroadcastReadiness {
    /// All timelocks are satisfied. Safe to broadcast.
    Ready,
    /// At least one timelock is unmet. The transaction will be rejected if
    /// broadcast now.
    Locked,
    /// Cannot decide yet — needs a wallet sync (tip height unknown) or the
    /// UTXO confirmation height was not recorded.
    SyncRequired,
    /// Relative time-based timelock (BIP68 sequence with TYPE_FLAG). Not
    /// covered by v1 of the auto-broadcast feature.
    Unsupported,
}

#[frb(ignore)]
impl BroadcastReadiness {
    pub fn is_ready(self) -> bool {
        matches!(self, BroadcastReadiness::Ready)
    }
}

#[frb(ignore)]
/// Compute whether `info` can be broadcast right now.
///
/// `spend_path` carries the relative-timelock metadata for the path that was
/// selected when the PSBT was built. Pass `None` when the PSBT was built
/// against the default (no-timelock) path — in that case only `info.lock_time`
/// is checked.
pub fn psbt_broadcast_readiness(
    info: &APIPsbtInfo,
    spend_path: Option<&APISpendPath>,
    tip_height: u32,
    now_secs: u64,
) -> BroadcastReadiness {
    // 1. Absolute timelock (taken directly from the PSBT's nLockTime).
    if info.lock_time > 0 {
        if info.lock_time < LOCK_TIME_THRESHOLD {
            if tip_height == 0 {
                return BroadcastReadiness::SyncRequired;
            }
            if tip_height < info.lock_time {
                return BroadcastReadiness::Locked;
            }
        } else {
            let lock = info.lock_time as u64;
            if now_secs < lock {
                return BroadcastReadiness::Locked;
            }
        }
    }

    // 2. Relative timelock (BIP68 sequence). Only known if a spend path was
    //    provided. The path's `rel_timelock.value == 0` means no rel timelock.
    if let Some(path) = spend_path {
        if path.rel_timelock.value > 0 {
            match path.rel_timelock.timelock_type {
                APIRelativeTimelockType::Blocks => {
                    let conf = match info.utxo_max_conf_height {
                        Some(h) if h > 0 => h as u32,
                        _ => return BroadcastReadiness::SyncRequired,
                    };
                    if tip_height == 0 {
                        return BroadcastReadiness::SyncRequired;
                    }
                    let unlock_block = conf.saturating_add(path.rel_timelock.value);
                    // BIP68 validates against the candidate block tip+1, so the
                    // tx is broadcastable as soon as tip+1 >= unlock_block.
                    if tip_height.saturating_add(1) < unlock_block {
                        return BroadcastReadiness::Locked;
                    }
                }
                APIRelativeTimelockType::Time => {
                    // v1: skip auto-broadcast for time-based relative
                    // timelocks. Median-time-past plumbing lands in a
                    // follow-up.
                    return BroadcastReadiness::Unsupported;
                }
            }
        }
    }

    // 3. Inputs gone (RBF'd externally, double-spent, etc.) — cannot broadcast.
    if info.has_spent_inputs {
        return BroadcastReadiness::Locked;
    }

    BroadcastReadiness::Ready
}

#[frb(ignore)]
/// Convenience wrapper for callers that only need a yes/no answer.
pub fn psbt_is_broadcastable_now(
    info: &APIPsbtInfo,
    spend_path: Option<&APISpendPath>,
    tip_height: u32,
    now_secs: u64,
) -> bool {
    psbt_broadcast_readiness(info, spend_path, tip_height, now_secs).is_ready()
}

#[cfg(test)]
#[path = "psbt_maturity_tests.rs"]
mod tests;
