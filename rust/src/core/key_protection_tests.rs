use super::*;

#[test]
fn test_generate_data_key_length() {
    let key = generate_data_key().unwrap();
    assert_eq!(key.len(), 64, "32 bytes → 64 hex chars");
    assert!(key.chars().all(|c| c.is_ascii_hexdigit()));
}

#[test]
fn test_generate_salt_length() {
    let salt = generate_salt().unwrap();
    assert_eq!(salt.len(), 32, "16 bytes → 32 hex chars");
}

#[test]
fn test_generate_data_key_unique() {
    assert_ne!(generate_data_key().unwrap(), generate_data_key().unwrap());
}

#[test]
fn test_wrap_unwrap_roundtrip() {
    let data_key = generate_data_key().unwrap();
    let wrapping_key = generate_data_key().unwrap(); // also 32 bytes
    let wrapped = wrap_key(&data_key, &wrapping_key).expect("wrap failed");
    let recovered = unwrap_key(&wrapped, &wrapping_key).expect("unwrap failed");
    assert_eq!(recovered, data_key);
}

#[test]
fn test_unwrap_wrong_key_fails() {
    let data_key = generate_data_key().unwrap();
    let wrapping_key = generate_data_key().unwrap();
    let wrapped = wrap_key(&data_key, &wrapping_key).expect("wrap failed");

    let wrong_key = generate_data_key().unwrap();
    let result = unwrap_key(&wrapped, &wrong_key);
    assert!(result.is_err(), "Should fail with wrong key");
}

#[test]
fn test_derive_key_deterministic() {
    let password = "test-password-123";
    let salt = generate_salt().unwrap();
    let key1 = derive_key_from_password(password, &salt, 1024, 1, 1).unwrap();
    let key2 = derive_key_from_password(password, &salt, 1024, 1, 1).unwrap();
    assert_eq!(key1, key2, "Same password+salt must yield same key");
}

#[test]
fn test_derive_key_different_passwords() {
    let salt = generate_salt().unwrap();
    let key1 = derive_key_from_password("password1", &salt, 1024, 1, 1).unwrap();
    let key2 = derive_key_from_password("password2", &salt, 1024, 1, 1).unwrap();
    assert_ne!(key1, key2);
}

#[test]
fn test_derive_key_different_salts() {
    let salt1 = generate_salt().unwrap();
    let salt2 = generate_salt().unwrap();
    let key1 = derive_key_from_password("same-password", &salt1, 1024, 1, 1).unwrap();
    let key2 = derive_key_from_password("same-password", &salt2, 1024, 1, 1).unwrap();
    assert_ne!(key1, key2);
}

#[test]
fn test_resolve_data_key_device_type() {
    let data_key = generate_data_key().unwrap();
    let device_key = generate_data_key().unwrap();
    let wrapped = wrap_key(&data_key, &device_key).unwrap();
    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key: wrapped,
    };
    let resolved = resolve_data_key(&meta, &device_key).unwrap();
    assert_eq!(resolved, data_key);
}

#[test]
fn test_resolve_data_key_password_type() {
    let data_key = generate_data_key().unwrap();
    let password = "my-wallet-password";
    let salt = generate_salt().unwrap();
    let wrapping_key = derive_key_from_password(password, &salt, 1024, 1, 1).unwrap();
    let wrapped = wrap_key(&data_key, &wrapping_key).unwrap();
    let meta = ProtectionMeta::UserPassword {
        version: 1,
        salt,
        m_cost: 1024,
        t_cost: 1,
        p_cost: 1,
        wrapped_key: wrapped,
        display_name: None,
        network: None,
        last_synced_at: None,
        biometric_slots: vec![],
    };
    let resolved = resolve_data_key(&meta, password).unwrap();
    assert_eq!(resolved, data_key);
}

#[test]
fn test_resolve_data_key_wrong_password_fails() {
    let data_key = generate_data_key().unwrap();
    let password = "correct-password";
    let salt = generate_salt().unwrap();
    let wrapping_key = derive_key_from_password(password, &salt, 1024, 1, 1).unwrap();
    let wrapped = wrap_key(&data_key, &wrapping_key).unwrap();
    let meta = ProtectionMeta::UserPassword {
        version: 1,
        salt,
        m_cost: 1024,
        t_cost: 1,
        p_cost: 1,
        wrapped_key: wrapped,
        display_name: None,
        network: None,
        last_synced_at: None,
        biometric_slots: vec![],
    };
    let result = resolve_data_key(&meta, "wrong-password");
    assert!(result.is_err(), "Should fail with wrong password");
}

#[test]
fn test_protection_meta_serde_device_key() {
    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key: "aabbcc".to_string(),
    };
    let json = serde_json::to_string(&meta).unwrap();
    let back: ProtectionMeta = serde_json::from_str(&json).unwrap();
    match back {
        ProtectionMeta::DeviceKey {
            version,
            wrapped_key,
        } => {
            assert_eq!(version, 1);
            assert_eq!(wrapped_key, "aabbcc");
        }
        _ => panic!("Wrong variant"),
    }
}

#[test]
fn test_protection_meta_serde_user_password() {
    let meta = ProtectionMeta::UserPassword {
        version: 1,
        salt: "deadbeef".to_string(),
        m_cost: 65536,
        t_cost: 3,
        p_cost: 1,
        wrapped_key: "cafebabe".to_string(),
        display_name: Some("Test Wallet".to_string()),
        network: Some("bitcoin".to_string()),
        last_synced_at: None,
        biometric_slots: vec![],
    };
    let json = serde_json::to_string(&meta).unwrap();
    let back: ProtectionMeta = serde_json::from_str(&json).unwrap();
    match back {
        ProtectionMeta::UserPassword { salt, m_cost, .. } => {
            assert_eq!(salt, "deadbeef");
            assert_eq!(m_cost, 65536);
        }
        _ => panic!("Wrong variant"),
    }
}

// ---------------------------------------------------------------------------
// XpubKey tests
// ---------------------------------------------------------------------------

const TEST_XPUB: &str = "xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn";
const TEST_XPUB2: &str = "xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj";

#[test]
fn test_wrap_with_xpub_roundtrip() {
    let data_key = generate_data_key().unwrap();
    let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key, 1024, 1, "").unwrap();
    assert_eq!(slot.mfp, "c449c5c5");

    let slots = vec![slot];
    let (recovered, mfp) = unwrap_xpub_slots(TEST_XPUB, None, &slots).unwrap();
    assert_eq!(recovered, data_key);
    assert_eq!(mfp, "c449c5c5");
}

#[test]
fn test_unwrap_xpub_wrong_xpub_fails() {
    let data_key = generate_data_key().unwrap();
    let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key, 1024, 1, "").unwrap();
    let result = unwrap_xpub_slots(TEST_XPUB2, None, &[slot]);
    assert!(result.is_err(), "Different xpub must not unlock");
}

#[test]
fn test_unwrap_xpub_any_slot_works() {
    let data_key = generate_data_key().unwrap();
    let slot1 = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key, 1024, 1, "").unwrap();
    let slot2 = wrap_with_xpub("c61af686", TEST_XPUB2, &data_key, 1024, 1, "").unwrap();
    let slots = vec![slot1, slot2];

    let (r1, mfp1) = unwrap_xpub_slots(TEST_XPUB, None, &slots).unwrap();
    let (r2, mfp2) = unwrap_xpub_slots(TEST_XPUB2, None, &slots).unwrap();
    assert_eq!(r1, data_key);
    assert_eq!(r2, data_key);
    assert_eq!(mfp1, "c449c5c5");
    assert_eq!(mfp2, "c61af686");
}

#[test]
fn test_protection_meta_serde_xpub_key() {
    let data_key = generate_data_key().unwrap();
    let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key, 1024, 1, "").unwrap();
    let meta = ProtectionMeta::XpubKey {
        version: 1,
        slots: vec![slot],
        display_name: Some("Test".to_string()),
        network: Some("bitcoin".to_string()),
        last_synced_at: None,
        biometric_slots: vec![],
    };
    let json = serde_json::to_string(&meta).unwrap();
    let back: ProtectionMeta = serde_json::from_str(&json).unwrap();
    match back {
        ProtectionMeta::XpubKey { slots, network, .. } => {
            assert_eq!(slots.len(), 1);
            assert_eq!(slots[0].mfp, "c449c5c5");
            assert_eq!(network.as_deref(), Some("bitcoin"));
        }
        _ => panic!("Wrong variant"),
    }
}

#[test]
fn test_parse_xpub_credential_bare() {
    let (mfp, xpub) = parse_xpub_credential(TEST_XPUB);
    assert!(mfp.is_none());
    assert_eq!(xpub, TEST_XPUB);
}

#[test]
fn test_parse_xpub_credential_keyspec() {
    let keyspec = format!("[c449c5c5/48h/0h/0h/2h]{}", TEST_XPUB);
    let (mfp, xpub) = parse_xpub_credential(&keyspec);
    assert_eq!(mfp, Some("c449c5c5"));
    assert_eq!(xpub, TEST_XPUB);
}

#[test]
fn test_parse_xpub_credential_keyspec_no_path() {
    let keyspec = format!("[c449c5c5]{}", TEST_XPUB);
    let (mfp, xpub) = parse_xpub_credential(&keyspec);
    assert_eq!(mfp, Some("c449c5c5"));
    assert_eq!(xpub, TEST_XPUB);
}

#[test]
fn test_unwrap_xpub_slots_with_mfp_hint() {
    let data_key = generate_data_key().unwrap();
    let slot1 = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key, 1024, 1, "").unwrap();
    let slot2 = wrap_with_xpub("c61af686", TEST_XPUB2, &data_key, 1024, 1, "").unwrap();
    let slots = vec![slot1, slot2];

    // With correct MFP hint, only the matching slot is tried.
    let (r, mfp) = unwrap_xpub_slots(TEST_XPUB, Some("c449c5c5"), &slots).unwrap();
    assert_eq!(r, data_key);
    assert_eq!(mfp, "c449c5c5");

    // Wrong MFP hint → no slot is tried → error.
    let r2 = unwrap_xpub_slots(TEST_XPUB, Some("deadbeef"), &slots);
    assert!(r2.is_err());
}

#[test]
fn test_resolve_data_key_xpub_with_keyspec() {
    let data_key = generate_data_key().unwrap();
    let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key, 1024, 1, "").unwrap();
    let meta = ProtectionMeta::XpubKey {
        version: 1,
        slots: vec![slot],
        display_name: None,
        network: None,
        last_synced_at: None,
        biometric_slots: vec![],
    };
    // Keyspec credential → MFP hint extracted → direct slot match.
    let keyspec = format!("[c449c5c5/48h/0h/0h/2h]{}", TEST_XPUB);
    let resolved = resolve_data_key(&meta, &keyspec).unwrap();
    assert_eq!(resolved, data_key);
}

#[test]
fn test_resolve_data_key_xpub_type() {
    let data_key = generate_data_key().unwrap();
    let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key, 1024, 1, "").unwrap();
    let meta = ProtectionMeta::XpubKey {
        version: 1,
        slots: vec![slot],
        display_name: None,
        network: None,
        last_synced_at: None,
        biometric_slots: vec![],
    };
    let resolved = resolve_data_key(&meta, TEST_XPUB).unwrap();
    assert_eq!(resolved, data_key);

    let bad = resolve_data_key(&meta, TEST_XPUB2);
    assert!(bad.is_err());
}
