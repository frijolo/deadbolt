use std::collections::HashMap;

use anyhow::Result;
use bdk_wallet::keys::DescriptorPublicKey;

use crate::api::model::{APIAbsoluteTimelock, APIRelativeTimelock};
use crate::core::error::WalletError;
use crate::core::pubkey::PubKey;
use crate::core::wallet::WalletType;

pub mod multisig;
pub mod single_key;
pub mod taproot;

pub use multisig::{build_path_policy, build_policy, build_sh, build_sh_wsh, build_wsh};
pub use single_key::{build_sh_wpkh, build_single_key};
pub use taproot::build_tr;

/// Definition of a spend path for descriptor building
pub struct SpendPathDef {
    pub threshold: usize,
    pub mfps: Vec<String>,
    pub rel_timelock: APIRelativeTimelock,
    pub abs_timelock: APIAbsoluteTimelock,
    pub is_key_path: bool,
    /// Taproot script tree priority (0 = deepest/least likely, higher = shallower/more likely).
    /// Ignored for non-Taproot descriptors.
    pub priority: usize,
}

/// Build a descriptor string from wallet type, keys, and spend path definitions.
///
/// Each spend path branch uses a distinct derivation pair (<0;1>/*, <2;3>/*, ...)
/// so the same xpub in different branches counts as a different key for the
/// policy compiler, avoiding "duplicate keys" errors.
pub fn build_descriptor(
    wallet_type: WalletType,
    keys: &[PubKey],
    spend_paths: &[SpendPathDef],
) -> Result<String> {
    if keys.is_empty() {
        return Err(WalletError::BuilderError("No keys provided".into()).into());
    }
    if spend_paths.is_empty() {
        return Err(WalletError::BuilderError("No spend paths provided".into()).into());
    }

    match wallet_type {
        WalletType::P2PKH => build_single_key("pkh", keys, spend_paths),
        WalletType::P2WPKH => build_single_key("wpkh", keys, spend_paths),
        WalletType::P2SH_WPKH => build_sh_wpkh(keys, spend_paths),
        WalletType::P2WSH => build_wsh(keys, spend_paths),
        WalletType::P2SH_WSH => build_sh_wsh(keys, spend_paths),
        WalletType::P2TR => build_tr(keys, spend_paths),
        WalletType::P2SH => build_sh(keys, spend_paths),
        WalletType::Unknown => Err(WalletError::BuilderError("Unknown wallet type".into()).into()),
    }
}

// --- Key helpers (shared across submodules) ---

/// Construct key string with standard multipath wildcard
pub fn key_with_wildcard(key: &PubKey) -> String {
    format!("{}/<0;1>/*", key)
}

/// Construct key string with an unused derivation pair.
/// Tracks usage by xpub (not MFP) so that two different MFPs sharing the
/// same xpub receive different derivation slots and don't produce duplicates.
pub fn key_with_derivation(key: &PubKey, keys_uses: &mut HashMap<String, usize>) -> String {
    let xpub_id = key
        .xpub()
        .map(|x| x.to_string())
        .unwrap_or_else(|_| key.to_string());
    let uses: &mut usize = keys_uses.entry(xpub_id).or_insert(0);
    let ext = *uses * 2;
    let int = ext + 1;
    *uses += 1;
    format!("{}/<{};{}>/*", key, ext, int)
}

/// Find a key by its master fingerprint
pub fn resolve_key<'a>(mfp: &str, keys: &'a [PubKey]) -> Result<&'a PubKey> {
    keys.iter()
        .find(|k| k.mfp().to_string() == mfp)
        .ok_or_else(|| WalletError::BuilderError(format!("Key not found for MFP: {}", mfp)).into())
}

/// Resolve MFPs to key strings with standard <0;1>/* wildcard
pub fn resolve_key_strings(mfps: &[String], keys: &[PubKey]) -> Result<Vec<String>> {
    mfps.iter()
        .map(|mfp| {
            let key = resolve_key(mfp, keys)?;
            Ok(key_with_wildcard(key))
        })
        .collect()
}

/// Parse a key string into a DescriptorPublicKey
pub fn parse_dpk(key_str: &str, mfp: &str) -> Result<DescriptorPublicKey> {
    key_str.parse::<DescriptorPublicKey>().map_err(|_| {
        WalletError::BuilderError(format!("Failed to parse key for MFP: {}", mfp)).into()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::descriptor::DescriptorAnalyzer;

    fn mainnet_keys() -> Vec<PubKey> {
        vec![
            PubKey::new(
                "c449c5c5",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )
            .unwrap(),
            PubKey::new(
                "c61af686",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )
            .unwrap(),
        ]
    }

    #[test]
    fn test_build_simple_wsh_multisig() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 2,
            mfps: vec!["c449c5c5".into(), "c61af686".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh(sortedmulti(2,"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);
        assert_eq!(analyzer.public_keys()?.len(), 2);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 2);

        Ok(())
    }

    #[test]
    fn test_build_wsh_with_timelock() -> Result<()> {
        let keys = mainnet_keys();
        // Primary: 2-of-2, Recovery: 1-of-1 with timelock (same key c449c5c5 in both)
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 2);

        Ok(())
    }

    #[test]
    fn test_build_taproot() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;
        assert!(paths.len() >= 2);

        Ok(())
    }

    #[test]
    fn test_build_single_key_wpkh() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2WPKH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wpkh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WPKH);
        assert_eq!(analyzer.public_keys()?.len(), 1);

        Ok(())
    }

    #[test]
    fn test_build_sh_wsh_multisig() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 2,
            mfps: vec!["c449c5c5".into(), "c61af686".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2SH_WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("sh(wsh(sortedmulti(2,"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2SH_WSH);
        assert_eq!(analyzer.public_keys()?.len(), 2);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 2);

        Ok(())
    }

    #[test]
    fn test_build_3of5_multisig() -> Result<()> {
        let keys = vec![
            PubKey::new(
                "aabbccdd",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
            PubKey::new(
                "bbccddee",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )?,
            PubKey::new(
                "ccddeeff",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
            PubKey::new(
                "ddeeff00",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )?,
            PubKey::new(
                "eeff0011",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
        ];

        let spend_paths = vec![SpendPathDef {
            threshold: 3,
            mfps: vec![
                "aabbccdd".into(),
                "bbccddee".into(),
                "ccddeeff".into(),
                "ddeeff00".into(),
                "eeff0011".into(),
            ],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh(sortedmulti(3,"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);
        assert_eq!(analyzer.public_keys()?.len(), 5);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 3);
        assert_eq!(paths[0].mfps.len(), 5);

        Ok(())
    }

    #[test]
    fn test_build_complex_recovery_setup() -> Result<()> {
        let keys = mainnet_keys();
        // Scenario: 2-of-2 immediate, 1-of-2 after 1 day, 1-of-1 after 1 week
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144), // ~1 day
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(1008), // ~1 week
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 3);

        // Verify all expected timelocks are present
        let timelocks: Vec<u32> = paths.iter().map(|p| p.rel_timelock).collect();
        assert!(timelocks.contains(&0));
        assert!(timelocks.contains(&144));
        assert!(timelocks.contains(&1008));

        Ok(())
    }

    #[test]
    fn test_build_with_absolute_timelock() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(800000), // Block height
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 2);

        let timelocked_path = paths.iter().find(|p| p.abs_timelock > 0).unwrap();
        assert_eq!(timelocked_path.abs_timelock, 800000);
        assert_eq!(timelocked_path.threshold, 1);

        Ok(())
    }

    #[test]
    fn test_build_roundtrip() -> Result<()> {
        // Test: build -> analyze -> rebuild -> should produce equivalent descriptor
        let keys = mainnet_keys();
        let original_paths = vec![
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor1 = build_descriptor(WalletType::P2WSH, &keys, &original_paths)?;
        let analyzer = DescriptorAnalyzer::analyze(&descriptor1)?;
        let analyzed_paths = analyzer.spend_paths()?;

        let reconstructed_paths: Vec<SpendPathDef> = analyzed_paths
            .iter()
            .map(|sp| SpendPathDef {
                threshold: sp.threshold,
                mfps: sp.mfps.clone(),
                rel_timelock: APIRelativeTimelock::from_consensus(sp.rel_timelock),
                abs_timelock: APIAbsoluteTimelock::from_consensus(sp.abs_timelock),
                is_key_path: false,
                priority: 0,
            })
            .collect();

        let descriptor2 = build_descriptor(WalletType::P2WSH, &keys, &reconstructed_paths)?;
        let analyzer2 = DescriptorAnalyzer::analyze(&descriptor2)?;
        let paths2 = analyzer2.spend_paths()?;

        assert_eq!(paths2.len(), analyzed_paths.len());
        for (p1, p2) in analyzed_paths.iter().zip(paths2.iter()) {
            assert_eq!(p1.threshold, p2.threshold);
            assert_eq!(p1.rel_timelock, p2.rel_timelock);
            assert_eq!(p1.abs_timelock, p2.abs_timelock);
        }

        Ok(())
    }

    #[test]
    fn test_build_sh_wpkh() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2SH_WPKH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("sh(wpkh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2SH_WPKH);
        assert_eq!(analyzer.public_keys()?.len(), 1);

        Ok(())
    }

    #[test]
    fn test_build_pkh() -> Result<()> {
        let keys = mainnet_keys();
        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: false,
            priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2PKH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("pkh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2PKH);
        assert_eq!(analyzer.public_keys()?.len(), 1);

        Ok(())
    }

    #[test]
    fn test_build_taproot_with_keypath() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true, // Mark as key-path
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));
        assert!(descriptor.contains("c449c5c5"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 2);

        let key_path = paths
            .iter()
            .find(|p| p.rel_timelock == 0 && p.abs_timelock == 0);
        assert!(key_path.is_some());

        let script_path = paths.iter().find(|p| p.rel_timelock == 144);
        assert!(script_path.is_some());

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_only() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![SpendPathDef {
            threshold: 1,
            mfps: vec!["c449c5c5".into()],
            rel_timelock: APIRelativeTimelock::from_consensus(0),
            abs_timelock: APIAbsoluteTimelock::from_consensus(0),
            is_key_path: true,
            priority: 0,
        }];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));
        assert!(!descriptor.contains("{{"));
        assert!(descriptor.contains("c449c5c5"));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0].threshold, 1);

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_errors() {
        let keys = mainnet_keys();

        // Error: Multiple paths marked as key-path
        let result = build_descriptor(
            WalletType::P2TR,
            &keys,
            &vec![
                SpendPathDef {
                    threshold: 1,
                    mfps: vec!["c449c5c5".into()],
                    rel_timelock: APIRelativeTimelock::from_consensus(0),
                    abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                    is_key_path: true,
                    priority: 0,
                },
                SpendPathDef {
                    threshold: 1,
                    mfps: vec!["c61af686".into()],
                    rel_timelock: APIRelativeTimelock::from_consensus(0),
                    abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                    is_key_path: true,
                    priority: 0,
                },
            ],
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Only one"));

        // Error: Key-path with multisig
        let result = build_descriptor(
            WalletType::P2TR,
            &keys,
            &vec![SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true,
                priority: 0,
            }],
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("singlesig"));

        // Error: Key-path with timelock
        let result = build_descriptor(
            WalletType::P2TR,
            &keys,
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true,
                priority: 0,
            }],
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("no timelocks"));
    }

    #[test]
    fn test_build_taproot_two_singlesig_no_timelocks() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("tr("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        assert!(!paths.is_empty());

        Ok(())
    }

    #[test]
    fn test_build_errors() {
        let keys = mainnet_keys();

        // Error: no keys provided
        let result = build_descriptor(
            WalletType::P2WSH,
            &[],
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());

        // Error: no spend paths provided
        let result = build_descriptor(WalletType::P2WSH, &keys, &[]);
        assert!(result.is_err());

        // Error: WPKH requires exactly 1 key with threshold 1
        let result = build_descriptor(
            WalletType::P2WPKH,
            &keys,
            &vec![SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());

        // Error: Unknown wallet type
        let result = build_descriptor(
            WalletType::Unknown,
            &keys,
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());

        // Error: MFP not found in keys
        let result = build_descriptor(
            WalletType::P2WSH,
            &keys,
            &vec![SpendPathDef {
                threshold: 1,
                mfps: vec!["deadbeef".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            }],
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_build_taproot_nums_only_script_paths() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        assert!(
            descriptor.starts_with("tr(xpub") || descriptor.starts_with("tr(tpub"),
            "Should start with NUMS xpub without fingerprint"
        );
        assert!(
            descriptor.contains("/<0;1>/*,{"),
            "NUMS xpub should have wildcard /<0;1>/*"
        );
        assert!(
            !descriptor
                .contains("50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"),
            "Should not contain raw NUMS point"
        );

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2TR);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 2);

        for path in &paths {
            assert!(
                path.tr_depth > 0,
                "All paths should be script paths with NUMS"
            );
        }

        let has_key1 = paths
            .iter()
            .any(|p| p.mfps.contains(&"c449c5c5".to_string()));
        let has_key2 = paths
            .iter()
            .any(|p| p.mfps.contains(&"c61af686".to_string()));
        assert!(has_key1, "Should have path with key c449c5c5");
        assert!(has_key2, "Should have path with key c61af686");

        Ok(())
    }

    #[test]
    fn test_build_taproot_multiple_singlesig_no_timelocks() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        assert_eq!(paths.len(), 2, "Should preserve all input paths");

        for path in &paths {
            assert_eq!(path.threshold, 1, "All paths should be singlesig");
            assert_eq!(path.mfps.len(), 1, "All paths should have 1 key");
        }

        let mfps: Vec<String> = paths.iter().flat_map(|p| p.mfps.clone()).collect();
        assert!(
            mfps.contains(&"c449c5c5".to_string()),
            "Should have key c449c5c5"
        );
        assert!(
            mfps.contains(&"c61af686".to_string()),
            "Should have key c61af686"
        );

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_plus_singlesig_no_timelocks() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        assert!(
            descriptor.contains("c449c5c5"),
            "Should use explicit key-path key"
        );
        assert!(
            !descriptor
                .contains("50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"),
            "Should NOT use NUMS when key-path is specified"
        );

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        assert_eq!(paths.len(), 2, "Should have both key-path and script path");

        let key_path = paths.iter().find(|p| p.tr_depth == 0);
        assert!(key_path.is_some(), "Should have a key-path (tr_depth=0)");
        let key_path = key_path.unwrap();
        assert_eq!(key_path.threshold, 1);
        assert_eq!(key_path.mfps.len(), 1);
        assert_eq!(key_path.mfps[0], "c449c5c5", "Key-path should use c449c5c5");

        let script_path = paths.iter().find(|p| p.tr_depth > 0);
        assert!(
            script_path.is_some(),
            "Should have a script path (trDepth>=0)"
        );
        let script_path = script_path.unwrap();
        assert_eq!(script_path.threshold, 1);
        assert_eq!(script_path.mfps.len(), 1);
        assert_eq!(
            script_path.mfps[0], "c61af686",
            "Script path should use c61af686"
        );

        Ok(())
    }

    #[test]
    fn test_build_taproot_complex_multisig_plus_singlesig() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true,
                priority: 0,
            },
            SpendPathDef {
                threshold: 2,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(1008),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        assert_eq!(paths.len(), 3, "Should have all 3 paths");

        let key_path = paths.iter().find(|p| p.tr_depth == 0);
        assert!(key_path.is_some());
        assert_eq!(key_path.unwrap().mfps[0], "c449c5c5");

        let multisig = paths.iter().find(|p| p.threshold == 2);
        assert!(multisig.is_some());
        assert_eq!(multisig.unwrap().mfps.len(), 2);

        let timelock = paths.iter().find(|p| p.rel_timelock == 1008);
        assert!(timelock.is_some());
        assert_eq!(timelock.unwrap().threshold, 1);

        Ok(())
    }

    #[test]
    fn test_build_taproot_three_singlesig_no_timelocks() -> Result<()> {
        let keys = vec![
            PubKey::new(
                "aaaaaaaa",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
            PubKey::new(
                "bbbbbbbb",
                "48h/0h/0h/2h",
                "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj",
            )?,
            PubKey::new(
                "cccccccc",
                "48h/0h/0h/2h",
                "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn",
            )?,
        ];

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["aaaaaaaa".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["bbbbbbbb".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["cccccccc".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        assert_eq!(paths.len(), 3, "All 3 singlesig paths should be preserved");

        for path in &paths {
            assert_eq!(path.threshold, 1);
            assert_eq!(path.mfps.len(), 1);
        }

        let all_mfps: Vec<String> = paths.iter().flat_map(|p| p.mfps.clone()).collect();
        assert!(all_mfps.contains(&"aaaaaaaa".to_string()));
        assert!(all_mfps.contains(&"bbbbbbbb".to_string()));
        assert!(all_mfps.contains(&"cccccccc".to_string()));

        Ok(())
    }

    #[test]
    fn test_build_taproot_keypath_preserves_exact_key() -> Result<()> {
        let keys = mainnet_keys();

        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: true, // THIS is the key-path
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(144),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2TR, &keys, &spend_paths)?;

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        let paths = analyzer.spend_paths()?;

        assert_eq!(paths.len(), 3);

        let key_path = paths.iter().find(|p| p.tr_depth == 0);
        assert!(key_path.is_some(), "Should have key-path");

        assert_eq!(
            key_path.unwrap().mfps[0],
            "c61af686",
            "Key-path should be c61af686 as explicitly marked, not arbitrarily chosen"
        );

        let script_paths: Vec<_> = paths.iter().filter(|p| p.tr_depth > 0).collect();
        assert_eq!(script_paths.len(), 2);

        Ok(())
    }

    #[test]
    fn test_build_wsh_multi_and_singlesig_with_timelock() -> Result<()> {
        let keys = mainnet_keys();

        // or(multi(1, a, b), and(a, older(1)))
        let spend_paths = vec![
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into(), "c61af686".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(0),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
            SpendPathDef {
                threshold: 1,
                mfps: vec!["c449c5c5".into()],
                rel_timelock: APIRelativeTimelock::from_consensus(1),
                abs_timelock: APIAbsoluteTimelock::from_consensus(0),
                is_key_path: false,
                priority: 0,
            },
        ];

        let descriptor = build_descriptor(WalletType::P2WSH, &keys, &spend_paths)?;
        assert!(descriptor.starts_with("wsh("));

        let analyzer = DescriptorAnalyzer::analyze(&descriptor)?;
        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);
        assert_eq!(analyzer.public_keys()?.len(), 2);

        let paths = analyzer.spend_paths()?;
        assert_eq!(paths.len(), 2);

        let multisig = paths
            .iter()
            .find(|p| p.mfps.len() == 2 && p.rel_timelock == 0)
            .expect("1-of-2 multisig path not found");
        assert_eq!(multisig.threshold, 1);
        assert_eq!(multisig.abs_timelock, 0);
        assert!(multisig.key_changes.get("c449c5c5").is_some());
        assert!(multisig.key_changes.get("c61af686").is_some());

        let and_older = paths
            .iter()
            .find(|p| p.rel_timelock == 1)
            .expect("and(a, older(1)) path not found");
        assert_eq!(and_older.threshold, 1);
        assert_eq!(and_older.mfps.len(), 1);
        assert_eq!(and_older.mfps[0], "c449c5c5");
        assert_eq!(and_older.abs_timelock, 0);
        assert!(and_older.key_changes.get("c449c5c5").is_some());

        Ok(())
    }

    #[test]
    fn test_complex_andor_wsh_multiple_spend_paths() -> Result<()> {
        // Complex descriptor with andor and nested or_i branches
        let descriptor_str = "wsh(andor(multi(1,[8a72f038/48'/1'/0'/2']tpubDEcRT2cqDCSsazuUTXpeNBjH9mbkw2BuQYzrWCzEpGkSUa4EabUVxZxsu9BghUm9XKeFpGS3Bicawwoomv655NjuLNm9AQ8c5SsEWhXr51Y/<4;5>/*,[bdc0483f/48'/1'/0'/2']tpubDFZd1aJpE1HkahP7DAA6StKP9ZdgNTDM2qiSfpEvsgBYaeFuh53cccWkz6JVHD57g2nFH84kkVRwvabmPGQY68FqfPwHiftnRbbKNwGkagb/<6;7>/*,[c8e8e42a/48'/1'/0'/2']tpubDFiG42yh4Y34gX9V9bFoXHQHjKs7UXt4YZ8LPgj4WeGT2aEeLvt1gPTTyq76jNSW9ACYYuJrydVYZt6QnPrr78JXvWrPbdBkNKduyo4rSDn/<4;5>/*,[fa729acd/48'/1'/0'/2']tpubDEYPwkpA7sMmwV2hRCtwb9Ye4Pvb7q3ZcLD8jDAXmxGSp3HNkkii3tiSX8Vde7NioPKCCa5aPzdaG68F8YE92znVDzfepV7brVk1wZn6Xm9/<6;7>/*),older(61200),or_i(or_i(and_v(v:and_v(v:pkh([bdc0483f/48'/1'/0'/2']tpubDFZd1aJpE1HkahP7DAA6StKP9ZdgNTDM2qiSfpEvsgBYaeFuh53cccWkz6JVHD57g2nFH84kkVRwvabmPGQY68FqfPwHiftnRbbKNwGkagb/<0;1>/*),pkh([fa729acd/48'/1'/0'/2']tpubDEYPwkpA7sMmwV2hRCtwb9Ye4Pvb7q3ZcLD8jDAXmxGSp3HNkkii3tiSX8Vde7NioPKCCa5aPzdaG68F8YE92znVDzfepV7brVk1wZn6Xm9/<0;1>/*)),older(2)),and_v(v:thresh(2,pkh([8a72f038/48'/1'/0'/2']tpubDEcRT2cqDCSsazuUTXpeNBjH9mbkw2BuQYzrWCzEpGkSUa4EabUVxZxsu9BghUm9XKeFpGS3Bicawwoomv655NjuLNm9AQ8c5SsEWhXr51Y/<0;1>/*),a:pkh([bdc0483f/48'/1'/0'/2']tpubDFZd1aJpE1HkahP7DAA6StKP9ZdgNTDM2qiSfpEvsgBYaeFuh53cccWkz6JVHD57g2nFH84kkVRwvabmPGQY68FqfPwHiftnRbbKNwGkagb/<2;3>/*),a:pkh([fa729acd/48'/1'/0'/2']tpubDEYPwkpA7sMmwV2hRCtwb9Ye4Pvb7q3ZcLD8jDAXmxGSp3HNkkii3tiSX8Vde7NioPKCCa5aPzdaG68F8YE92znVDzfepV7brVk1wZn6Xm9/<2;3>/*)),older(52560))),or_i(and_v(v:thresh(2,pkh([bdc0483f/48'/1'/0'/2']tpubDFZd1aJpE1HkahP7DAA6StKP9ZdgNTDM2qiSfpEvsgBYaeFuh53cccWkz6JVHD57g2nFH84kkVRwvabmPGQY68FqfPwHiftnRbbKNwGkagb/<4;5>/*),a:pkh([c8e8e42a/48'/1'/0'/2']tpubDFiG42yh4Y34gX9V9bFoXHQHjKs7UXt4YZ8LPgj4WeGT2aEeLvt1gPTTyq76jNSW9ACYYuJrydVYZt6QnPrr78JXvWrPbdBkNKduyo4rSDn/<0;1>/*),a:pkh([fa729acd/48'/1'/0'/2']tpubDEYPwkpA7sMmwV2hRCtwb9Ye4Pvb7q3ZcLD8jDAXmxGSp3HNkkii3tiSX8Vde7NioPKCCa5aPzdaG68F8YE92znVDzfepV7brVk1wZn6Xm9/<4;5>/*)),older(52561)),and_v(v:and_v(v:pkh([8a72f038/48'/1'/0'/2']tpubDEcRT2cqDCSsazuUTXpeNBjH9mbkw2BuQYzrWCzEpGkSUa4EabUVxZxsu9BghUm9XKeFpGS3Bicawwoomv655NjuLNm9AQ8c5SsEWhXr51Y/<2;3>/*),pkh([c8e8e42a/48'/1'/0'/2']tpubDFiG42yh4Y34gX9V9bFoXHQHjKs7UXt4YZ8LPgj4WeGT2aEeLvt1gPTTyq76jNSW9ACYYuJrydVYZt6QnPrr78JXvWrPbdBkNKduyo4rSDn/<2;3>/*)),older(56880))))))#cpfrv0ey";

        use crate::core::descriptor::DescriptorAnalyzer;
        let analyzer = DescriptorAnalyzer::analyze(descriptor_str)?;

        assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);
        let paths = analyzer.spend_paths()?;

        assert_eq!(
            paths.len(),
            5,
            "Expected 5 spend paths, got {}",
            paths.len()
        );

        // Path 1: 1 of 4 older(61200)
        let path1 = paths
            .iter()
            .find(|p| p.threshold == 1 && p.rel_timelock == 61200)
            .expect("Path 1 (1 of 4, older(61200)) not found");
        assert_eq!(path1.mfps.len(), 4);
        assert_eq!(path1.key_changes.get("8a72f038"), Some(&4u32));
        assert_eq!(path1.key_changes.get("bdc0483f"), Some(&6u32));
        assert_eq!(path1.key_changes.get("c8e8e42a"), Some(&4u32));
        assert_eq!(path1.key_changes.get("fa729acd"), Some(&6u32));

        // Path 2: 2 of 2 older(2)
        let path2 = paths
            .iter()
            .find(|p| p.threshold == 2 && p.rel_timelock == 2)
            .expect("Path 2 (2 of 2, older(2)) not found");
        assert_eq!(path2.mfps.len(), 2);
        assert_eq!(path2.key_changes.get("bdc0483f"), Some(&0u32));
        assert_eq!(path2.key_changes.get("fa729acd"), Some(&0u32));

        // Path 3: 2 of 3 older(52560)
        let path3 = paths
            .iter()
            .find(|p| p.threshold == 2 && p.rel_timelock == 52560)
            .expect("Path 3 (2 of 3, older(52560)) not found");
        assert_eq!(path3.mfps.len(), 3);
        assert_eq!(path3.key_changes.get("8a72f038"), Some(&0u32));
        assert_eq!(path3.key_changes.get("bdc0483f"), Some(&2u32));
        assert_eq!(path3.key_changes.get("fa729acd"), Some(&2u32));

        // Path 4: 2 of 3 older(52561)
        let path4 = paths
            .iter()
            .find(|p| p.threshold == 2 && p.rel_timelock == 52561)
            .expect("Path 4 (2 of 3, older(52561)) not found");
        assert_eq!(path4.mfps.len(), 3);
        assert_eq!(path4.key_changes.get("bdc0483f"), Some(&4u32));
        assert_eq!(path4.key_changes.get("c8e8e42a"), Some(&0u32));
        assert_eq!(path4.key_changes.get("fa729acd"), Some(&4u32));

        // Path 5: 2 of 2 older(56880)
        let path5 = paths
            .iter()
            .find(|p| p.threshold == 2 && p.rel_timelock == 56880)
            .expect("Path 5 (2 of 2, older(56880)) not found");
        assert_eq!(path5.mfps.len(), 2);
        assert_eq!(path5.key_changes.get("8a72f038"), Some(&2u32));
        assert_eq!(path5.key_changes.get("c8e8e42a"), Some(&2u32));

        Ok(())
    }
}
