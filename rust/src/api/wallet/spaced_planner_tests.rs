use super::*;
use rand::rngs::StdRng;
use rand::SeedableRng;

fn params_default() -> PlannerParams {
    PlannerParams {
        feerate_min_msatvb: 2_000,
        feerate_max_msatvb: 8_000,
        delay_blocks_min: 1,
        delay_blocks_max: 100,
        split_probability: 0.5,
        min_split_output: 100_000,
    }
}

fn utxos(n: usize) -> Vec<PlannerUtxo> {
    (0..n)
        .map(|i| PlannerUtxo {
            outpoint_key: format!("op:{i}"),
            amount_sat: 1_000_000 + i as u64 * 100_000,
            conf_height: Some(700_000 + i as u32),
        })
        .collect()
}

// ---------------------------------------------------------------------------
// PlannerParams::validate
// ---------------------------------------------------------------------------

#[test]
fn validate_accepts_sane_values() {
    assert!(params_default().validate().is_ok());
}

#[test]
fn validate_rejects_zero_feerate_min() {
    let p = PlannerParams {
        feerate_min_msatvb: 0,
        ..params_default()
    };
    assert!(p.validate().is_err());
}

#[test]
fn validate_rejects_inverted_feerate() {
    let p = PlannerParams {
        feerate_min_msatvb: 9_000,
        feerate_max_msatvb: 8_000,
        ..params_default()
    };
    assert!(p.validate().is_err());
}

#[test]
fn validate_rejects_zero_delay_min() {
    let p = PlannerParams {
        delay_blocks_min: 0,
        ..params_default()
    };
    assert!(p.validate().is_err());
}

#[test]
fn validate_rejects_inverted_delay() {
    let p = PlannerParams {
        delay_blocks_min: 50,
        delay_blocks_max: 10,
        ..params_default()
    };
    assert!(p.validate().is_err());
}

#[test]
fn validate_rejects_split_probability_out_of_range() {
    for bad in [-0.1, 1.1, f64::NAN] {
        let p = PlannerParams {
            split_probability: bad,
            ..params_default()
        };
        assert!(p.validate().is_err(), "{bad} should be rejected");
    }
}

// ---------------------------------------------------------------------------
// Determinism + invariants
// ---------------------------------------------------------------------------

#[test]
fn same_seed_yields_identical_intents() {
    let mut a = StdRng::seed_from_u64(42);
    let mut b = StdRng::seed_from_u64(42);
    let pa = plan_intents(utxos(8), &params_default(), 800_000, 0, &mut a).unwrap();
    let pb = plan_intents(utxos(8), &params_default(), 800_000, 0, &mut b).unwrap();
    assert_eq!(pa, pb);
}

#[test]
fn different_seeds_yield_different_orderings_eventually() {
    // Pick two seeds that produce a different permutation on 16 elements.
    let mut a = StdRng::seed_from_u64(1);
    let mut b = StdRng::seed_from_u64(2);
    let pa = plan_intents(utxos(16), &params_default(), 800_000, 0, &mut a).unwrap();
    let pb = plan_intents(utxos(16), &params_default(), 800_000, 0, &mut b).unwrap();
    let order_a: Vec<&str> = pa.iter().map(|p| p.utxo.outpoint_key.as_str()).collect();
    let order_b: Vec<&str> = pb.iter().map(|p| p.utxo.outpoint_key.as_str()).collect();
    assert_ne!(order_a, order_b);
}

#[test]
fn output_covers_every_input_utxo() {
    let mut rng = StdRng::seed_from_u64(7);
    let input = utxos(20);
    let intents = plan_intents(input.clone(), &params_default(), 800_000, 0, &mut rng).unwrap();
    assert_eq!(intents.len(), input.len());
    let mut seen: Vec<&str> = intents
        .iter()
        .map(|p| p.utxo.outpoint_key.as_str())
        .collect();
    seen.sort();
    let mut expected: Vec<&str> = input.iter().map(|u| u.outpoint_key.as_str()).collect();
    expected.sort();
    assert_eq!(seen, expected);
}

#[test]
fn deltas_are_monotonic_and_gaps_stay_within_band() {
    let mut rng = StdRng::seed_from_u64(99);
    let params = params_default();
    let intents = plan_intents(utxos(50), &params, 800_000, 0, &mut rng).unwrap();
    let mut prev: u32 = 0;
    for (i, p) in intents.iter().enumerate() {
        let gap = p.nlocktime_delta_blocks - prev;
        assert!(
            gap >= params.delay_blocks_min && gap <= params.delay_blocks_max,
            "intent {i}: gap {gap} out of band [{}, {}] (delta={}, prev={})",
            params.delay_blocks_min,
            params.delay_blocks_max,
            p.nlocktime_delta_blocks,
            prev,
        );
        assert!(
            p.feerate_msatvb >= params.feerate_min_msatvb
                && p.feerate_msatvb <= params.feerate_max_msatvb,
            "feerate {} out of band",
            p.feerate_msatvb
        );
        prev = p.nlocktime_delta_blocks;
    }
}

#[test]
fn split_probability_zero_disables_split() {
    let params = PlannerParams {
        split_probability: 0.0,
        ..params_default()
    };
    let mut rng = StdRng::seed_from_u64(123);
    let intents = plan_intents(utxos(40), &params, 800_000, 0, &mut rng).unwrap();
    assert!(intents.iter().all(|p| p.split == SplitIntent::None));
}

#[test]
fn split_probability_one_makes_every_intent_a_split() {
    let params = PlannerParams {
        split_probability: 1.0,
        ..params_default()
    };
    let mut rng = StdRng::seed_from_u64(456);
    let intents = plan_intents(utxos(40), &params, 800_000, 0, &mut rng).unwrap();
    for p in &intents {
        match p.split {
            SplitIntent::Try { ratio } => {
                assert!((0.2..=0.8).contains(&ratio), "ratio {} out of range", ratio);
            }
            SplitIntent::None => panic!("expected split, got None"),
        }
    }
}

#[test]
fn collapsed_band_is_constant_and_legal() {
    let params = PlannerParams {
        feerate_min_msatvb: 5_000,
        feerate_max_msatvb: 5_000,
        delay_blocks_min: 7,
        delay_blocks_max: 7,
        ..params_default()
    };
    let mut rng = StdRng::seed_from_u64(0);
    let intents = plan_intents(utxos(10), &params, 800_000, 0, &mut rng).unwrap();
    assert!(intents.iter().all(|p| p.feerate_msatvb == 5_000));
    // With a fixed gap of 7, deltas should be 7, 14, 21, ..., 70.
    for (i, p) in intents.iter().enumerate() {
        let expected = ((i as u32) + 1) * 7;
        assert_eq!(p.nlocktime_delta_blocks, expected);
    }
}

#[test]
fn empty_utxo_list_yields_empty_plan() {
    let mut rng = StdRng::seed_from_u64(0);
    let intents = plan_intents(vec![], &params_default(), 800_000, 0, &mut rng).unwrap();
    assert!(intents.is_empty());
}

#[test]
fn invalid_params_propagate_error() {
    let mut rng = StdRng::seed_from_u64(0);
    let params = PlannerParams {
        feerate_min_msatvb: 0,
        ..params_default()
    };
    assert!(plan_intents(utxos(3), &params, 800_000, 0, &mut rng).is_err());
}

// ---------------------------------------------------------------------------
// rel_timelock_floor
// ---------------------------------------------------------------------------

#[test]
fn rel_floor_zero_when_no_rel_timelock() {
    assert_eq!(rel_timelock_floor(800_000, 0, Some(700_000)), 0);
}

#[test]
fn rel_floor_zero_when_utxo_already_mature() {
    // conf at 700_000, rel = 100 → unlock at 700_100, well below tip 800_000.
    assert_eq!(rel_timelock_floor(800_000, 100, Some(700_000)), 0);
}

#[test]
fn rel_floor_positive_when_utxo_not_yet_mature() {
    // conf at 799_950, rel = 100 → unlock at 800_050; tip 800_000 → floor 50.
    assert_eq!(rel_timelock_floor(800_000, 100, Some(799_950)), 50);
}

#[test]
fn rel_floor_uses_tip_when_conf_height_unknown() {
    // Unknown conf height → assume mined at tip → full window.
    assert_eq!(rel_timelock_floor(800_000, 144, None), 144);
}

#[test]
fn plan_respects_rel_timelock_floor() {
    // tip 800_000, rel 200, UTXOs confirmed at 799_900..799_999 (unlock
    // heights 800_100..800_199 — every UTXO immature). Gap band 1..10.
    //
    // Expected schedule:
    //   - Immature UTXOs sorted by ascending floor (conf 799_900 first,
    //     floor 100; conf 799_999 last, floor 199).
    //   - Each intent's delta = max(prev_delta + gap, own floor). Since
    //     gaps ∈ [1, 10] and floors grow by 1..1 between neighbours,
    //     the cumulative gap quickly overtakes the floor — but the
    //     first intent's delta must be ≥ its own floor (100).
    let params = PlannerParams {
        delay_blocks_min: 1,
        delay_blocks_max: 10,
        ..params_default()
    };
    let utxos: Vec<PlannerUtxo> = (0..30)
        .map(|i| PlannerUtxo {
            outpoint_key: format!("op:{i}"),
            amount_sat: 500_000,
            conf_height: Some(799_900 + i),
        })
        .collect();
    let mut rng = StdRng::seed_from_u64(11);
    let intents = plan_intents(utxos.clone(), &params, 800_000, 200, &mut rng).unwrap();

    // Immature ordering: conf_height ascending (= floor ascending).
    let confs: Vec<u32> = intents
        .iter()
        .map(|i| i.utxo.conf_height.unwrap())
        .collect();
    let mut sorted = confs.clone();
    sorted.sort();
    assert_eq!(confs, sorted, "immature UTXOs must be ordered by floor");

    let mut prev: u32 = 0;
    for intent in &intents {
        let conf = intent.utxo.conf_height.unwrap();
        let floor = (conf + 200).saturating_sub(800_000);
        assert!(
            intent.nlocktime_delta_blocks >= floor,
            "delta {} below floor {}",
            intent.nlocktime_delta_blocks,
            floor,
        );
        // Each delta must be ≥ prev + min_gap (monotonic, gap respected).
        assert!(
            intent.nlocktime_delta_blocks >= prev + params.delay_blocks_min,
            "delta {} violates min gap from prev {}",
            intent.nlocktime_delta_blocks,
            prev,
        );
        prev = intent.nlocktime_delta_blocks;
    }
}

#[test]
fn mature_utxos_come_before_immature() {
    // 5 mature (deep conf) + 5 immature (just confirmed) with rel = 100.
    let mut utxos = Vec::new();
    for i in 0..5 {
        utxos.push(PlannerUtxo {
            outpoint_key: format!("mature:{i}"),
            amount_sat: 500_000,
            conf_height: Some(700_000 + i), // very old
        });
    }
    for i in 0..5 {
        utxos.push(PlannerUtxo {
            outpoint_key: format!("immature:{i}"),
            amount_sat: 500_000,
            conf_height: Some(799_950 + i),
        });
    }
    let params = params_default();
    let mut rng = StdRng::seed_from_u64(5);
    let intents = plan_intents(utxos, &params, 800_000, 100, &mut rng).unwrap();

    let mut seen_immature = false;
    for intent in &intents {
        let is_mature = intent.utxo.outpoint_key.starts_with("mature:");
        if !is_mature {
            seen_immature = true;
        } else {
            assert!(
                !seen_immature,
                "mature UTXO {} appeared after an immature one",
                intent.utxo.outpoint_key
            );
        }
    }
}

// ---------------------------------------------------------------------------
// split_passes_gate
// ---------------------------------------------------------------------------

#[test]
fn split_gate_passes_when_smaller_output_above_threshold() {
    // 1_000_000 sat * 0.4 = 400_000 sat smaller output — above 100_000.
    assert!(split_passes_gate(1_000_000, 0.4, 100_000));
}

#[test]
fn split_gate_fails_when_smaller_output_below_threshold() {
    // 200_000 sat * 0.2 = 40_000 sat — below 100_000 threshold.
    assert!(!split_passes_gate(200_000, 0.2, 100_000));
}

#[test]
fn split_gate_symmetric_in_ratio() {
    assert_eq!(
        split_passes_gate(1_000_000, 0.3, 100_000),
        split_passes_gate(1_000_000, 0.7, 100_000)
    );
}

#[test]
fn split_gate_rejects_invalid_ratio() {
    assert!(!split_passes_gate(1_000_000, -0.1, 100_000));
    assert!(!split_passes_gate(1_000_000, 1.5, 100_000));
}

#[test]
fn split_gate_handles_zero_net_out() {
    assert!(!split_passes_gate(0, 0.5, 1));
    assert!(split_passes_gate(0, 0.5, 0)); // threshold 0 ⇒ trivially true
}
