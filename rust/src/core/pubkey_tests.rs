use super::*;

#[test]
fn test_key() -> Result<()> {
    let keystr = "[73c5da0a/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba";

    let pk = PubKey::try_from(keystr)?;

    assert_eq!(pk.mfp().to_string(), "73c5da0a");
    assert_eq!(pk.derivation_path()?.to_string(), "44'/1'/0'");
    assert_eq!(pk.xpub()?.to_string(), "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba");

    let reskey = pk.to_string();
    assert_eq!(&keystr, &reskey);

    let pk = PubKey::new(
        "73c5da0a",
        "44'/1'/0'",
        "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
    )?;

    let reskey = pk.to_string();
    assert_eq!(&keystr, &reskey);

    let compatible_with_mainnet = pk.is_compatible_with_network(Network::Bitcoin)?;
    assert!(!compatible_with_mainnet);
    let compatible_with_signet = pk.is_compatible_with_network(Network::Signet)?;
    assert!(compatible_with_signet);

    Ok(())
}

#[test]
fn test_key_without_derivation_path() -> Result<()> {
    // Test key without derivation path (root xpub)
    let pk = PubKey::new(
        "73c5da0a",
        "",
        "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
    )?;

    assert_eq!(pk.mfp().to_string(), "73c5da0a");
    let expected = "[73c5da0a]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba";
    assert_eq!(pk.to_string(), expected);

    Ok(())
}

#[test]
fn test_key_with_wildcard_preserves_origin_path() -> Result<()> {
    // Test that keys with wildcards preserve the origin derivation path
    let keystr = "[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*";
    let pk = PubKey::try_from(keystr)?;

    assert_eq!(pk.mfp().to_string(), "c449c5c5");
    // BDK converts 'h' notation to apostrophe notation
    assert_eq!(pk.derivation_path()?.to_string(), "48'/0'/0'/2'");
    assert_eq!(pk.xpub()?.to_string(), "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn");

    Ok(())
}

#[test]
fn test_generate_and_detect_nums_xpub() -> Result<()> {
    // Create some test keys
    let key1 = PubKey::try_from(
        "[73c5da0a/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
    )?;
    let key2 = PubKey::try_from(
        "[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn"
    )?;

    let keys = vec![key1, key2];

    // Generate NUMS xpub
    let nums_xpub = PubKey::generate_unspendable_xpub(&keys, Network::Signet)?;

    // Verify NUMS pubkey is used (singleton)
    assert_eq!(nums_xpub.public_key, *get_nums_pubkey());

    // Verify other fields
    assert_eq!(nums_xpub.depth, 0);
    assert_eq!(nums_xpub.parent_fingerprint, Fingerprint::default());
    assert_eq!(nums_xpub.child_number, ChildNumber::from_normal_idx(0)?);

    // Create a PubKey from the NUMS xpub and verify it's detected as unspendable
    let nums_key_str = format!("[00000000]{}", nums_xpub);
    let nums_key = PubKey::try_from(nums_key_str.as_str())?;
    assert!(
        nums_key.is_unspendable(),
        "NUMS key should be detected as unspendable"
    );

    Ok(())
}

#[test]
fn test_regular_key_not_unspendable() -> Result<()> {
    // Regular keys should not be detected as unspendable
    let regular_key = PubKey::try_from(
        "[73c5da0a/44'/1'/0']tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
    )?;
    assert!(
        !regular_key.is_unspendable(),
        "Regular key should not be unspendable"
    );

    Ok(())
}

#[test]
fn test_nums_keys_excluded_from_descriptor() -> Result<()> {
    use bdk_wallet::keys::DescriptorPublicKey;
    use bdk_wallet::miniscript::Descriptor;

    // Descriptor with raw NUMS point as internal key
    let descriptor_str = "tr(50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0,{pk([c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*),pk([73c5da0a/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*)})#kvpt6nlf";

    let descriptor: Descriptor<DescriptorPublicKey> = descriptor_str.parse()?;

    // Extract keys - should NOT include NUMS
    let extracted_keys = PubKey::extract_from_descriptor(&descriptor)?;

    // Should have only 2 script path keys, NUMS excluded
    assert_eq!(
        extracted_keys.len(),
        2,
        "Should extract only 2 script keys, NUMS excluded"
    );

    // No keys should be unspendable
    let nums_count = extracted_keys.iter().filter(|k| k.is_unspendable()).count();
    assert_eq!(nums_count, 0, "Should have no NUMS keys");

    Ok(())
}

#[test]
fn test_taproot_without_keypath_excludes_nums() -> Result<()> {
    use bdk_wallet::keys::DescriptorPublicKey;
    use bdk_wallet::miniscript::Descriptor;

    // Taproot descriptor without keypath (using raw NUMS point)
    let descriptor_str = "tr(50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0,{pk([c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*),pk([73c5da0a/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*)})#kvpt6nlf";

    let descriptor: Descriptor<DescriptorPublicKey> = descriptor_str.parse()?;

    // Extract keys - should only include script path keys, NOT NUMS
    let extracted_keys = PubKey::extract_from_descriptor(&descriptor)?;

    // Should have only 2 keys (script paths), NUMS excluded
    assert_eq!(
        extracted_keys.len(),
        2,
        "Should extract only 2 script keys, NUMS excluded"
    );

    // No unspendable keys
    let nums_count = extracted_keys.iter().filter(|k| k.is_unspendable()).count();
    assert_eq!(nums_count, 0, "Should have no NUMS keys");

    // Both keys should be regular keys
    assert_eq!(extracted_keys[0].mfp().to_string(), "c449c5c5");
    assert_eq!(extracted_keys[1].mfp().to_string(), "73c5da0a");

    Ok(())
}

#[test]
fn test_validate_mfp_format_accepts_valid() {
    assert!(PubKey::validate_mfp_format("73c5da0a").is_ok());
    assert!(PubKey::validate_mfp_format("ABCDEF01").is_ok());
}

#[test]
fn test_validate_mfp_format_rejects_wrong_length() {
    let err = PubKey::validate_mfp_format("73c5da0")
        .unwrap_err()
        .to_string();
    assert!(err.contains("exactly 8 characters"), "got: {err}");
    let err = PubKey::validate_mfp_format("73c5da0aa")
        .unwrap_err()
        .to_string();
    assert!(err.contains("exactly 8 characters"), "got: {err}");
}

#[test]
fn test_validate_mfp_format_rejects_non_hex() {
    let err = PubKey::validate_mfp_format("zzzzzzzz")
        .unwrap_err()
        .to_string();
    assert!(err.contains("hexadecimal"), "got: {err}");
}

#[test]
fn test_validate_network_ok_for_signet_key() -> Result<()> {
    let pk = PubKey::new(
        "73c5da0a",
        "44'/1'/0'",
        "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
    )?;
    pk.validate_network(Network::Signet)?;
    Ok(())
}

#[test]
fn test_validate_network_rejects_mainnet_for_testnet_key() -> Result<()> {
    let pk = PubKey::new(
        "73c5da0a",
        "44'/1'/0'",
        "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba",
    )?;
    let err = pk
        .validate_network(Network::Bitcoin)
        .unwrap_err()
        .to_string();
    assert!(err.contains("not compatible with mainnet"), "got: {err}");
    assert!(err.contains("xpub, ypub, or zpub"), "got: {err}");
    Ok(())
}
