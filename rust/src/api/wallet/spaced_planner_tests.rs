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
fn delay_and_feerate_stay_within_band() {
    let mut rng = StdRng::seed_from_u64(99);
    let params = params_default();
    let intents = plan_intents(utxos(50), &params, 800_000, 0, &mut rng).unwrap();
    for p in &intents {
        assert!(
            p.nlocktime_delta_blocks >= params.delay_blocks_min
                && p.nlocktime_delta_blocks <= params.delay_blocks_max,
            "delta {} out of band",
            p.nlocktime_delta_blocks
        );
        assert!(
            p.feerate_msatvb >= params.feerate_min_msatvb
                && p.feerate_msatvb <= params.feerate_max_msatvb,
            "feerate {} out of band",
            p.feerate_msatvb
        );
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
    assert!(intents.iter().all(|p| p.nlocktime_delta_blocks == 7));
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
    // tip 800_000, rel 200, UTXOs confirmed at 799_900..799_999 (unlocked
    // anywhere from 100_100..100_199 height). delay band 1..10 — below
    // every floor. Every intent's delta must be ≥ its UTXO's floor.
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

    for intent in &intents {
        let conf = intent.utxo.conf_height.unwrap();
        let expected_floor = (conf + 200).saturating_sub(800_000);
        assert!(
            intent.nlocktime_delta_blocks >= expected_floor,
            "delta {} below floor {}",
            intent.nlocktime_delta_blocks,
            expected_floor,
        );
        // Sampled delay is in [1, 10] which is well below the floor, so
        // every intent's delta should sit exactly at the floor.
        assert_eq!(intent.nlocktime_delta_blocks, expected_floor);
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
