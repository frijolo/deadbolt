// Pure planning logic for spaced TX plans: given a set of UTXOs and a
// `PlannerParams`, deterministically sample per-TX delays, feerates and
// split intents. No BDK, no DB, no I/O — randomness flows through an
// injected `rand::Rng` so callers pick `OsRng` in production and a
// seeded `StdRng` in tests.

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use rand::seq::SliceRandom;
use rand::Rng;

#[frb(ignore)]
#[derive(Debug, Clone, PartialEq)]
pub struct PlannerParams {
    pub feerate_min_msatvb: u64,
    pub feerate_max_msatvb: u64,
    pub delay_blocks_min: u32,
    pub delay_blocks_max: u32,
    pub split_probability: f64,
    pub min_split_output: u64,
}

#[frb(ignore)]
impl PlannerParams {
    pub fn validate(&self) -> Result<()> {
        if self.feerate_min_msatvb == 0 {
            return Err(anyhow!("feerate_min_msatvb must be > 0"));
        }
        if self.feerate_min_msatvb > self.feerate_max_msatvb {
            return Err(anyhow!("feerate_min_msatvb > feerate_max_msatvb"));
        }
        if self.delay_blocks_min == 0 {
            return Err(anyhow!("delay_blocks_min must be ≥ 1"));
        }
        if self.delay_blocks_min > self.delay_blocks_max {
            return Err(anyhow!("delay_blocks_min > delay_blocks_max"));
        }
        if !(0.0..=1.0).contains(&self.split_probability) {
            return Err(anyhow!("split_probability must be in [0, 1]"));
        }
        Ok(())
    }
}

#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannerUtxo {
    /// Stable identifier (typically `outpoint.to_string()`). Used for
    /// equality / ordering in tests; opaque to the planner.
    pub outpoint_key: String,
    pub amount_sat: u64,
    /// Block height at which the UTXO was confirmed. `None` means unknown
    /// (treated as "matured already" — the planner won't add a rel-timelock
    /// floor for it).
    pub conf_height: Option<u32>,
}

#[frb(ignore)]
#[derive(Debug, Clone, PartialEq)]
pub enum SplitIntent {
    /// 1-output transaction (input − fee).
    None,
    /// 2-output candidate. `ratio` ∈ [0.2, 0.8] gives the share of the
    /// first output. Final gating happens after fee calc:
    /// `min(ratio, 1-ratio) * net_out ≥ min_split_output`.
    Try { ratio: f64 },
}

#[frb(ignore)]
#[derive(Debug, Clone, PartialEq)]
pub struct PlanIntent {
    pub utxo: PlannerUtxo,
    /// Delta to add to current tip — fed directly to
    /// `create_psbt(nlocktime_delta_blocks)`. Already covers any rel
    /// timelock floor required by the chosen spend path so the absolute
    /// nLockTime alone gates broadcast.
    pub nlocktime_delta_blocks: u32,
    pub feerate_msatvb: u64,
    pub split: SplitIntent,
}

/// Top-level planner. Returns one `PlanIntent` per input UTXO, ordered
/// so the broadcast schedule maximises privacy:
///
/// - `delay_blocks_min`..`delay_blocks_max` is sampled per intent as the
///   **gap** between consecutive broadcasts. The first intent uses its
///   sampled gap as its own `nlocktime_delta_blocks` (relative to tip);
///   each subsequent intent stacks its gap on top of the previous
///   intent's delta. This guarantees a minimum block separation between
///   any two children of the plan instead of letting two intents collide
///   on the same block.
/// - UTXOs are ordered **mature first, immature last**. Mature UTXOs are
///   shuffled (preserving the existing privacy property). Immature ones
///   are sorted by ascending rel-timelock floor so the schedule grows
///   monotonically and the rel-floor only rarely overrides the gap.
/// - When the accumulated delta is below an intent's rel-timelock floor
///   the floor wins, and the cumulative anchor advances to that floor —
///   so subsequent intents keep their minimum spacing from the actual
///   broadcast height, not from the pre-floor estimate.
///
/// Arguments:
/// - `tip_height`: current chain tip.
/// - `rel_timelock_blocks`: BIP68 relative-blocks requirement of the
///   chosen spend path; pass `0` if the path has no rel timelock.
/// - `rng`: any `rand::Rng`. Use `OsRng` in production, a seeded
///   `StdRng` in tests.
#[frb(ignore)]
pub fn plan_intents<R: Rng + ?Sized>(
    utxos: Vec<PlannerUtxo>,
    params: &PlannerParams,
    tip_height: u32,
    rel_timelock_blocks: u32,
    rng: &mut R,
) -> Result<Vec<PlanIntent>> {
    params.validate()?;

    let ordered = order_utxos(utxos, tip_height, rel_timelock_blocks, rng);

    let mut intents = Vec::with_capacity(ordered.len());
    let mut cum_delta: u32 = 0;
    for utxo in ordered {
        let gap = sample_inclusive_u32(rng, params.delay_blocks_min, params.delay_blocks_max);
        cum_delta = cum_delta
            .checked_add(gap)
            .ok_or_else(|| anyhow!("cumulative nlocktime delta overflows u32"))?;
        let rel_floor = rel_timelock_floor(tip_height, rel_timelock_blocks, utxo.conf_height);
        let delta = cum_delta.max(rel_floor);
        // Advance the anchor so the next gap stacks on the actually-used
        // delta — otherwise an immature UTXO bumped by its floor would
        // let the next intent broadcast right after it.
        cum_delta = delta;

        let feerate_msatvb = if params.feerate_min_msatvb >= params.feerate_max_msatvb {
            params.feerate_min_msatvb
        } else {
            rng.random_range(params.feerate_min_msatvb..=params.feerate_max_msatvb)
        };

        let split = if rng.random::<f64>() < params.split_probability {
            // ratio ∈ [0.2, 0.8]
            let ratio = 0.2 + rng.random::<f64>() * 0.6;
            SplitIntent::Try { ratio }
        } else {
            SplitIntent::None
        };

        intents.push(PlanIntent {
            utxo,
            nlocktime_delta_blocks: delta,
            feerate_msatvb,
            split,
        });
    }
    Ok(intents)
}

/// Split UTXOs into mature / immature groups and produce a single
/// ordered vector: mature ones first (shuffled), then immature ones
/// sorted by ascending rel-timelock floor. When `rel_timelock_blocks`
/// is 0 every UTXO is mature and the result is just a shuffle.
fn order_utxos<R: Rng + ?Sized>(
    utxos: Vec<PlannerUtxo>,
    tip_height: u32,
    rel_timelock_blocks: u32,
    rng: &mut R,
) -> Vec<PlannerUtxo> {
    let mut mature: Vec<PlannerUtxo> = Vec::with_capacity(utxos.len());
    let mut immature: Vec<(u32, PlannerUtxo)> = Vec::new();
    for u in utxos {
        let floor = rel_timelock_floor(tip_height, rel_timelock_blocks, u.conf_height);
        if floor == 0 {
            mature.push(u);
        } else {
            immature.push((floor, u));
        }
    }
    mature.shuffle(rng);
    // Stable sort by ascending floor; ties keep insertion order which is
    // wallet-list order — deterministic given the input.
    immature.sort_by_key(|(floor, _)| *floor);
    let mut out = mature;
    out.extend(immature.into_iter().map(|(_, u)| u));
    out
}

/// Minimum delta (in blocks from `tip_height`) needed so the tx's
/// absolute nLockTime alone matures past a BIP68 rel-timelock.
///
/// Returns `0` when no rel timelock applies or when the UTXO is already
/// mature.
#[frb(ignore)]
pub fn rel_timelock_floor(
    tip_height: u32,
    rel_timelock_blocks: u32,
    conf_height: Option<u32>,
) -> u32 {
    if rel_timelock_blocks == 0 {
        return 0;
    }
    let conf = match conf_height {
        Some(h) if h > 0 => h,
        // Unknown / unconfirmed: assume freshly mined at the tip so the
        // floor is the full rel-timelock window.
        _ => tip_height,
    };
    let unlock_height = conf.saturating_add(rel_timelock_blocks);
    unlock_height.saturating_sub(tip_height)
}

/// Apply the §3 post-ratio split gate.
///
/// Returns `true` if a TX whose **net output value** (input − fee) is
/// `net_out_sat` should actually be split at `ratio`. When this is
/// false the planner intent falls back to a single output.
#[frb(ignore)]
pub fn split_passes_gate(net_out_sat: u64, ratio: f64, min_split_output: u64) -> bool {
    if !(0.0..=1.0).contains(&ratio) {
        return false;
    }
    let smaller = ratio.min(1.0 - ratio);
    let smaller_output_sat = ((net_out_sat as f64) * smaller).floor() as u64;
    smaller_output_sat >= min_split_output
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn sample_inclusive_u32<R: Rng + ?Sized>(rng: &mut R, min: u32, max: u32) -> u32 {
    if min >= max {
        return min;
    }
    rng.random_range(min..=max)
}

#[cfg(test)]
#[path = "spaced_planner_tests.rs"]
mod tests;
