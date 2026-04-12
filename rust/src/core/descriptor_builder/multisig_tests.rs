use super::*;
use crate::api::model::{APIAbsoluteTimelock, APIRelativeTimelock};

fn make_path(threshold: usize, mfps: &[&str], rel: u32, abs: u32) -> SpendPathDef {
    SpendPathDef {
        threshold,
        mfps: mfps.iter().map(|s| s.to_string()).collect(),
        rel_timelock: APIRelativeTimelock::from_consensus(rel),
        abs_timelock: APIAbsoluteTimelock::from_consensus(abs),
        is_key_path: false,
        priority: 0,
    }
}

// --- is_simple_multisig ---

#[test]
fn test_is_simple_multisig_true_for_single_path_no_timelocks_multiple_keys() {
    let paths = vec![make_path(2, &["aabb", "ccdd"], 0, 0)];
    assert!(is_simple_multisig(&paths));
}

#[test]
fn test_is_simple_multisig_false_when_single_key() {
    // Single key = not a multisig path
    let paths = vec![make_path(1, &["aabb"], 0, 0)];
    assert!(!is_simple_multisig(&paths));
}

#[test]
fn test_is_simple_multisig_false_when_multiple_paths() {
    let paths = vec![
        make_path(2, &["aabb", "ccdd"], 0, 0),
        make_path(1, &["aabb"], 144, 0),
    ];
    assert!(!is_simple_multisig(&paths));
}

#[test]
fn test_is_simple_multisig_false_when_rel_timelock() {
    let paths = vec![make_path(2, &["aabb", "ccdd"], 144, 0)];
    assert!(!is_simple_multisig(&paths));
}

#[test]
fn test_is_simple_multisig_false_when_abs_timelock() {
    let paths = vec![make_path(2, &["aabb", "ccdd"], 0, 800000)];
    assert!(!is_simple_multisig(&paths));
}

// --- build_balanced_or_tree ---

#[test]
fn test_build_balanced_or_tree_two_policies() {
    let p1 = ConcretePolicy::Unsatisfiable;
    let p2 = ConcretePolicy::Unsatisfiable;
    let result = build_balanced_or_tree(vec![p1, p2]);
    // Should wrap both in an Or
    match result {
        ConcretePolicy::Or(branches) => assert_eq!(branches.len(), 2),
        other => panic!("Expected Or, got {:?}", other),
    }
}

#[test]
fn test_build_balanced_or_tree_single_policy_passes_through() {
    let p = ConcretePolicy::Unsatisfiable;
    let result = build_balanced_or_tree(vec![p]);
    // Single policy should be returned as-is (no Or wrapper)
    assert!(matches!(result, ConcretePolicy::Unsatisfiable));
}

#[test]
fn test_build_balanced_or_tree_three_policies_produces_or() {
    let policies = vec![
        ConcretePolicy::Unsatisfiable,
        ConcretePolicy::Unsatisfiable,
        ConcretePolicy::Unsatisfiable,
    ];
    let result = build_balanced_or_tree(policies);
    // Three policies: (p1 OR p2) at level 1, then (result OR p3) at level 2
    assert!(matches!(result, ConcretePolicy::Or(_)));
}
