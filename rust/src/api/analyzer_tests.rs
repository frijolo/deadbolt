use super::*;
use crate::core::error::WalletError;

#[test]
fn test_mainnet() -> Result<()> {
    let descriptor = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    let result = analyze_descriptor(String::from(descriptor))?;

    assert_eq!(result.network, APINetwork::Bitcoin);
    assert_eq!(result.wallet_type, APIWalletType::P2WSH);
    assert_eq!(result.keys.len(), 2);
    assert_eq!(result.spend_paths.len(), 1);

    assert_eq!(result.keys[0].mfp, "c449c5c5");
    assert_eq!(result.keys[1].mfp, "c61af686");

    let sp = result
        .spend_paths
        .first()
        .ok_or(WalletError::MissingPolicy)?;
    assert_eq!(sp.threshold, 2);
    assert_eq!(sp.mfps.len(), 2);
    assert_eq!((sp.wu_base + sp.wu_in + sp.wu_out) / 4, 149);
    assert_eq!(sp.abs_timelock.value, 0);
    assert_eq!(sp.rel_timelock.value, 0);
    assert_eq!(sp.tr_depth, -1);

    Ok(())
}

#[test]
fn test_testnet_single_key() -> Result<()> {
    let descriptor = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";
    let result = analyze_descriptor(String::from(descriptor))?;

    assert_eq!(result.network, APINetwork::Testnet);
    assert_eq!(result.wallet_type, APIWalletType::P2PKH);
    assert_eq!(result.keys.len(), 1);
    assert_eq!(result.keys[0].mfp, "73c5da0a");
    assert_eq!(result.spend_paths.len(), 1);

    Ok(())
}

#[test]
fn test_invalid_descriptor_string() {
    // Completely invalid string
    let result = analyze_descriptor("not_a_descriptor".to_string());
    assert!(result.is_err(), "Should fail on invalid descriptor string");

    // Empty string
    let result = analyze_descriptor(String::new());
    assert!(result.is_err(), "Should fail on empty descriptor string");

    // Valid prefix but invalid content
    let result = analyze_descriptor("wsh(garbage_content)".to_string());
    assert!(
        result.is_err(),
        "Should fail on malformed descriptor content"
    );

    // Missing checksum separator (invalid descriptor format)
    let result = analyze_descriptor("pkh(deadbeef)".to_string());
    assert!(result.is_err(), "Should fail on invalid pkh content");
}

#[test]
fn test_network_key_incompatibility() {
    // Mainnet descriptor with testnet key (tpub) — should fail
    let mainnet_wsh_with_tpub = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*,[c61af686/48h/0h/0h/2h]tpubDFZd1aJpE1HkahP7DAA6StKP9ZdgNTDM2qiSfpEvsgBYaeFuh53cccWkz6JVHD57g2nFH84kkVRwvabmPGQY68FqfPwHiftnRbbKNwGkagb/<0;1>/*))";
    let result = analyze_descriptor(mainnet_wsh_with_tpub.to_string());
    // tpub keys are not valid in mainnet wsh context — BDK should reject this
    // or our network detection should flag it as testnet and succeed with testnet analysis
    // Either way, validate_key() would catch incompatibility if validate_key is called
    // The main thing: this should not panic
    let _ = result;

    // Testnet key with mainnet descriptor format using xpub (incompatible versions)
    // validate_key should catch this
    let result = validate_key(
        "c449c5c5".to_string(),
        "48h/0h/0h/2h".to_string(),
        "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba".to_string(),
        APINetwork::Bitcoin, // Mainnet network but testnet key
    );
    assert!(
        result.is_err(),
        "Should fail when testnet key is used with mainnet network"
    );
    assert!(
        result.unwrap_err().to_string().contains("not compatible"),
        "Error should mention network incompatibility"
    );
}

#[test]
fn test_validate_key_errors() {
    // Invalid MFP length (not 8 hex chars)
    let result = validate_key(
        "abc".to_string(),
        "48h/0h/0h/2h".to_string(),
        "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
        APINetwork::Bitcoin,
    );
    assert!(result.is_err(), "Should fail on short MFP");
    assert!(
        result.unwrap_err().to_string().contains("8 characters"),
        "Error should mention 8 character requirement"
    );

    // Non-hex MFP
    let result = validate_key(
        "GGGGGGGG".to_string(),
        "48h/0h/0h/2h".to_string(),
        "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
        APINetwork::Bitcoin,
    );
    assert!(result.is_err(), "Should fail on non-hex MFP");
    assert!(
        result.unwrap_err().to_string().contains("hexadecimal"),
        "Error should mention hexadecimal"
    );

    // Invalid xpub (garbage)
    let result = validate_key(
        "c449c5c5".to_string(),
        "48h/0h/0h/2h".to_string(),
        "not_an_xpub".to_string(),
        APINetwork::Bitcoin,
    );
    assert!(result.is_err(), "Should fail on invalid xpub");
}

#[test]
fn test_build_descriptor_policy_failures() {
    use crate::api::model::{APIAbsoluteTimelock, APIRelativeTimelock, APISpendPathDef};

    // Empty keys list
    let result = build_descriptor(
        APIWalletType::P2WSH,
        vec![],
        vec![APISpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".to_string()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }],
    );
    assert!(result.is_err(), "Should fail with no keys");

    // Empty spend paths list
    let result = build_descriptor(
        APIWalletType::P2WSH,
        vec![crate::api::model::APIPubKey {
            mfp: "c449c5c5".to_string(),
            derivation_path: "48h/0h/0h/2h".to_string(),
            xpub: "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
        }],
        vec![],
    );
    assert!(result.is_err(), "Should fail with no spend paths");

    // MFP referenced in path but not in keys
    let result = build_descriptor(
        APIWalletType::P2WSH,
        vec![crate::api::model::APIPubKey {
            mfp: "c449c5c5".to_string(),
            derivation_path: "48h/0h/0h/2h".to_string(),
            xpub: "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn".to_string(),
        }],
        vec![APISpendPathDef {
            threshold: 1,
            mfps: vec!["deadbeef".to_string()], // MFP not in keys
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }],
    );
    assert!(result.is_err(), "Should fail when MFP not found in keys");
}

#[test]
fn test_taproot_without_keypath_roundtrip() -> Result<()> {
    // Descriptor with raw NUMS point (no keypath spend)
    let original_descriptor = "tr(50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0,{pk([c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*),pk([73c5da0a/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*)})#kvpt6nlf";

    // Analyze descriptor
    let result = analyze_descriptor(String::from(original_descriptor))?;

    // Should extract only 2 script path keys (NUMS excluded)
    assert_eq!(result.keys.len(), 2, "Should have only 2 script path keys");

    // No NUMS key should be present
    let nums_key = result.keys.iter().find(|k| k.mfp == "00000000");
    assert!(nums_key.is_none(), "NUMS key should not be in keys list");

    // Convert APISpendPath to APISpendPathDef for rebuild
    let spend_path_defs: Vec<APISpendPathDef> = result
        .spend_paths
        .iter()
        .map(|sp| {
            // Determine if this is a key-path (singlesig with no timelocks at depth 0)
            let is_key_path = sp.threshold == 1
                && sp.mfps.len() == 1
                && sp.rel_timelock.value == 0
                && sp.abs_timelock.value == 0
                && sp.tr_depth == -1; // tr_depth is 0-1 for keypath

            APISpendPathDef {
                threshold: sp.threshold,
                mfps: sp.mfps.clone(),
                rel_timelock: sp.rel_timelock,
                abs_timelock: sp.abs_timelock,
                is_key_path,
                priority: 0,
            }
        })
        .collect();

    // Rebuild descriptor using extracted keys and spend paths
    let rebuilt = build_descriptor(result.wallet_type, result.keys.clone(), spend_path_defs)?;

    // Rebuilt descriptor should NOT contain raw NUMS point
    assert!(
        !rebuilt.contains("50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"),
        "Rebuilt descriptor should not contain raw NUMS point"
    );

    // Rebuilt descriptor should contain NUMS xpub with wildcard (without fingerprint/derivation)
    // Format: tr(xpub.../<0;1>/*,{...})
    assert!(
        rebuilt.starts_with("tr(xpub") || rebuilt.starts_with("tr(tpub"),
        "Rebuilt descriptor should start with NUMS xpub (no fingerprint)"
    );

    assert!(
        rebuilt.contains("/<0;1>/*,{"),
        "NUMS xpub should have wildcard /<0;1>/*"
    );

    // Re-analyze the rebuilt descriptor to verify it's valid
    let reanalyzed = analyze_descriptor(rebuilt)?;
    assert_eq!(
        reanalyzed.keys.len(),
        2,
        "Reanalyzed should still have 2 keys"
    );
    assert_eq!(
        reanalyzed.spend_paths.len(),
        result.spend_paths.len(),
        "Spend paths should match"
    );

    Ok(())
}

// --- validate_descriptor_network ---

const MAINNET_DESC: &str = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
const TESTNET_DESC: &str = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";

#[test]
fn test_validate_descriptor_network_mainnet_ok() -> Result<()> {
    validate_descriptor_network(MAINNET_DESC.to_string(), APINetwork::Bitcoin)
}

#[test]
fn test_validate_descriptor_network_testnet_ok() -> Result<()> {
    validate_descriptor_network(TESTNET_DESC.to_string(), APINetwork::Testnet)
}

#[test]
fn test_validate_descriptor_network_testnet4_ok() -> Result<()> {
    // Testnet4 is in the same testnet family as tpub keys — should pass
    validate_descriptor_network(TESTNET_DESC.to_string(), APINetwork::Testnet4)
}

#[test]
fn test_validate_descriptor_network_signet_ok() -> Result<()> {
    validate_descriptor_network(TESTNET_DESC.to_string(), APINetwork::Signet)
}

#[test]
fn test_validate_descriptor_network_regtest_ok() -> Result<()> {
    validate_descriptor_network(TESTNET_DESC.to_string(), APINetwork::Regtest)
}

#[test]
fn test_validate_descriptor_network_mainnet_desc_testnet_network_err() {
    let result = validate_descriptor_network(MAINNET_DESC.to_string(), APINetwork::Testnet);
    assert!(result.is_err());
    let msg = result.unwrap_err().to_string();
    assert!(
        msg.contains("mainnet"),
        "error should mention 'mainnet': {msg}"
    );
}

#[test]
fn test_validate_descriptor_network_testnet_desc_mainnet_network_err() {
    let result = validate_descriptor_network(TESTNET_DESC.to_string(), APINetwork::Bitcoin);
    assert!(result.is_err());
    let msg = result.unwrap_err().to_string();
    assert!(
        msg.contains("testnet"),
        "error should mention 'testnet': {msg}"
    );
}

#[test]
fn test_validate_descriptor_network_invalid_descriptor_err() {
    let result = validate_descriptor_network("not_a_descriptor".to_string(), APINetwork::Bitcoin);
    assert!(result.is_err());
}

// --- format_descriptor_for_liana ---

#[test]
fn test_format_descriptor_for_liana_multipath_nums() -> Result<()> {
    // Testnet TR descriptor with NUMS xpub as MultiXPub (uses <0;1>/*)
    // This is a real Deadbolt-generated descriptor.
    let descriptor = "tr(tpubD6NzVbkrYhZ4WgRd5dPVwkWEXmzmAuLiJr8SZEtVgsYuE5d5dXLNwf4aFjftJTncXjMPAZmsoUfB615QLkSoqCxkMpKVFcPA4iCf5giaNYT/<0;1>/*,{and_v(v:and_v(v:pk([4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*),pk([ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*)),older(1)),{{and_v(v:multi_a(2,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<2;3>/*,[f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*,[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<2;3>/*),older(2)),and_v(v:multi_a(2,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<4;5>/*,[a045ca01/48'/1'/0'/2']tpubDE2KGCrYbgcNjvSyHG9ytdgR5LhGj8GvWpCGgcMvsTZnuuqE259tatGFhTbg2BvRfoziW4soM8Mhgk6juTAKNaM19GauMPEerjbeY2R2p9J/<0;1>/*,[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<4;5>/*),older(3))},{and_v(v:multi_a(2,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<6;7>/*,[ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<0;1>/*,[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<6;7>/*),older(4)),{and_v(v:multi_a(1,[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<8;9>/*,[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<8;9>/*),older(5)),and_v(v:multi_a(1,[a045ca01/48'/1'/0'/2']tpubDE2KGCrYbgcNjvSyHG9ytdgR5LhGj8GvWpCGgcMvsTZnuuqE259tatGFhTbg2BvRfoziW4soM8Mhgk6juTAKNaM19GauMPEerjbeY2R2p9J/<2;3>/*,[ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<2;3>/*,[f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<2;3>/*),older(6))}}}})#2fdut6vr";

    let result = format_descriptor_for_liana(descriptor.to_string())?;

    let liana = result.expect("Should return Some for TR with NUMS xpub internal key");
    assert!(
        liana.starts_with("tr([00000000]tpub"),
        "Liana descriptor should start with tr([00000000]tpub, got: {}",
        &liana[..50.min(liana.len())]
    );
    assert!(
        !liana.contains('#'),
        "Liana descriptor should not have a checksum"
    );
    Ok(())
}

#[test]
fn test_format_descriptor_for_liana_returns_none_for_non_tr() -> Result<()> {
    let wsh = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    assert!(format_descriptor_for_liana(wsh.to_string())?.is_none());
    Ok(())
}

#[test]
fn test_format_descriptor_for_liana_returns_none_for_tr_with_real_keypath() -> Result<()> {
    // TR descriptor where the internal key has a real origin (real key-path spend)
    let tr_with_keypath = "tr([c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*)#qpe8g8yf";
    assert!(format_descriptor_for_liana(tr_with_keypath.to_string())?.is_none());
    Ok(())
}
