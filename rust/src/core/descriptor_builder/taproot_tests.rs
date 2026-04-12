use super::*;

// --- build_taproot_tree ---

#[test]
fn test_taproot_tree_zero_scripts_returns_error() {
    let result = build_taproot_tree(&[]);
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("no scripts"));
}

#[test]
fn test_taproot_tree_single_script_passes_through() {
    let result = build_taproot_tree(&["pk(aabb)".to_string()]);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "pk(aabb)");
}

#[test]
fn test_taproot_tree_two_scripts_produces_pair() {
    let result = build_taproot_tree(&["pk(aabb)".to_string(), "pk(ccdd)".to_string()]);
    assert!(result.is_ok());
    let tree = result.unwrap();
    assert_eq!(tree, "{pk(aabb),pk(ccdd)}");
}

#[test]
fn test_taproot_tree_three_scripts_is_nested() {
    let scripts = vec![
        "pk(aa)".to_string(),
        "pk(bb)".to_string(),
        "pk(cc)".to_string(),
    ];
    let result = build_taproot_tree(&scripts);
    assert!(result.is_ok());
    let tree = result.unwrap();
    // 3 scripts: left = {pk(aa)}, right = {pk(bb),pk(cc)}
    assert!(tree.contains("pk(aa)"));
    assert!(tree.contains("pk(bb)"));
    assert!(tree.contains("pk(cc)"));
    assert!(tree.starts_with('{'));
    assert!(tree.ends_with('}'));
}

#[test]
fn test_taproot_tree_four_scripts_is_balanced() {
    let scripts = vec![
        "pk(aa)".to_string(),
        "pk(bb)".to_string(),
        "pk(cc)".to_string(),
        "pk(dd)".to_string(),
    ];
    let result = build_taproot_tree(&scripts);
    assert!(result.is_ok());
    let tree = result.unwrap();
    // 4 scripts: left = {pk(aa),pk(bb)}, right = {pk(cc),pk(dd)}
    assert_eq!(tree, "{{pk(aa),pk(bb)},{pk(cc),pk(dd)}}");
}

// --- build_layered_tree ---

#[test]
fn test_layered_tree_empty_returns_error() {
    let result = build_layered_tree(vec![]);
    assert!(result.is_err());
}

#[test]
fn test_layered_tree_single_level_single_script() {
    let result = build_layered_tree(vec![vec!["pk(aabb)".to_string()]]);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "pk(aabb)");
}

#[test]
fn test_layered_tree_single_level_two_scripts() {
    let result = build_layered_tree(vec![vec!["pk(aa)".to_string(), "pk(bb)".to_string()]]);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), "{pk(aa),pk(bb)}");
}

#[test]
fn test_layered_tree_two_levels_nests_deeper_first() {
    // Priority 0 (deeper) = first layer; priority 1 (shallower) = outer layer
    // Level 0: ["pk(deep)"], Level 1: ["pk(shallow)"]
    // Expected: {"pk(shallow)", "pk(deep)"}  — the prev subtree is appended to current
    let result = build_layered_tree(vec![
        vec!["pk(deep)".to_string()], // processed first → becomes inner subtree
        vec!["pk(shallow)".to_string()], // processed second → wraps inner
    ]);
    assert!(result.is_ok());
    let tree = result.unwrap();
    assert!(tree.contains("pk(deep)"));
    assert!(tree.contains("pk(shallow)"));
}
