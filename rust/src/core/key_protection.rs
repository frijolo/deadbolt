use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use anyhow::{anyhow, Result};
use argon2::{Algorithm, Argon2, Params, Version};
use rand::rngs::OsRng;
use rand::TryRngCore;
use serde::{Deserialize, Serialize};

/// Generate 32 random bytes and return them as lowercase hex (64 chars).
pub fn generate_data_key() -> String {
    let mut bytes = [0u8; 32];
    OsRng.try_fill_bytes(&mut bytes).expect("OS RNG failed");
    hex::encode(bytes)
}

/// Generate 16 random bytes and return them as lowercase hex (32 chars).
pub fn generate_salt() -> String {
    let mut bytes = [0u8; 16];
    OsRng.try_fill_bytes(&mut bytes).expect("OS RNG failed");
    hex::encode(bytes)
}

/// AES-256-GCM wrap: encrypt `data_key_hex` under `wrapping_key_hex`.
/// Returns hex(nonce || ciphertext || tag) where nonce is 12 random bytes.
pub fn wrap_key(data_key_hex: &str, wrapping_key_hex: &str) -> Result<String> {
    let data_key_bytes =
        hex::decode(data_key_hex).map_err(|e| anyhow!("Invalid data key hex: {}", e))?;
    let wrapping_key_bytes =
        hex::decode(wrapping_key_hex).map_err(|e| anyhow!("Invalid wrapping key hex: {}", e))?;
    if wrapping_key_bytes.len() != 32 {
        return Err(anyhow!("Wrapping key must be 32 bytes"));
    }

    let cipher = Aes256Gcm::new_from_slice(&wrapping_key_bytes)
        .map_err(|e| anyhow!("AES-GCM key init: {}", e))?;

    // Random 12-byte nonce
    let mut nonce_bytes = [0u8; 12];
    OsRng
        .try_fill_bytes(&mut nonce_bytes)
        .expect("OS RNG failed");
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, data_key_bytes.as_ref())
        .map_err(|e| anyhow!("AES-GCM encrypt: {}", e))?;

    // Encode as hex(nonce || ciphertext+tag)
    let mut combined = nonce_bytes.to_vec();
    combined.extend_from_slice(&ciphertext);
    Ok(hex::encode(combined))
}

/// AES-256-GCM unwrap: decrypt the wrapped key produced by `wrap_key`.
/// Input: hex(nonce || ciphertext || tag). Returns the original `data_key_hex`.
pub fn unwrap_key(wrapped_key_hex: &str, wrapping_key_hex: &str) -> Result<String> {
    let combined =
        hex::decode(wrapped_key_hex).map_err(|e| anyhow!("Invalid wrapped key hex: {}", e))?;
    if combined.len() < 12 {
        return Err(anyhow!("Wrapped key too short"));
    }

    let wrapping_key_bytes =
        hex::decode(wrapping_key_hex).map_err(|e| anyhow!("Invalid wrapping key hex: {}", e))?;
    if wrapping_key_bytes.len() != 32 {
        return Err(anyhow!("Wrapping key must be 32 bytes"));
    }

    let nonce = Nonce::from_slice(&combined[..12]);
    let ciphertext = &combined[12..];

    let cipher = Aes256Gcm::new_from_slice(&wrapping_key_bytes)
        .map_err(|e| anyhow!("AES-GCM key init: {}", e))?;

    let plaintext = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| anyhow!("AES-GCM decrypt failed — wrong key or corrupted data"))?;

    Ok(hex::encode(plaintext))
}

/// Argon2id KDF: derive a 32-byte key hex from a password and a salt hex.
pub fn derive_key_from_password(
    password: &str,
    salt_hex: &str,
    m_cost: u32,
    t_cost: u32,
    p_cost: u32,
) -> Result<String> {
    let salt = hex::decode(salt_hex).map_err(|e| anyhow!("Invalid salt hex: {}", e))?;

    let params = Params::new(m_cost, t_cost, p_cost, Some(32))
        .map_err(|e| anyhow!("Argon2 params: {}", e))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut output = [0u8; 32];
    argon2
        .hash_password_into(password.as_bytes(), &salt, &mut output)
        .map_err(|e| anyhow!("Argon2id hash: {}", e))?;

    Ok(hex::encode(output))
}

/// AES-256-GCM encrypt arbitrary bytes under `key_hex`.
/// Returns `nonce[12] || ciphertext || tag`.
pub fn encrypt_bytes(key_hex: &str, plaintext: &[u8]) -> Result<Vec<u8>> {
    let key_bytes = hex::decode(key_hex).map_err(|e| anyhow!("Invalid key hex: {}", e))?;
    let cipher =
        Aes256Gcm::new_from_slice(&key_bytes).map_err(|e| anyhow!("AES-GCM key init: {}", e))?;
    let mut nonce_bytes = [0u8; 12];
    OsRng
        .try_fill_bytes(&mut nonce_bytes)
        .expect("OS RNG failed");
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ct = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| anyhow!("AES-GCM encrypt: {}", e))?;
    let mut out = nonce_bytes.to_vec();
    out.extend_from_slice(&ct);
    Ok(out)
}

/// AES-256-GCM decrypt bytes produced by [`encrypt_bytes`].
/// Input must be `nonce[12] || ciphertext || tag`.
pub fn decrypt_bytes(key_hex: &str, ciphertext: &[u8]) -> Result<Vec<u8>> {
    if ciphertext.len() < 12 {
        return Err(anyhow!("Ciphertext too short"));
    }
    let key_bytes = hex::decode(key_hex).map_err(|e| anyhow!("Invalid key hex: {}", e))?;
    let cipher =
        Aes256Gcm::new_from_slice(&key_bytes).map_err(|e| anyhow!("AES-GCM key init: {}", e))?;
    let nonce = Nonce::from_slice(&ciphertext[..12]);
    cipher
        .decrypt(nonce, &ciphertext[12..])
        .map_err(|_| anyhow!("Decryption failed — wrong password or corrupted data"))
}

/// Default Argon2id parameters (~300ms on a modern CPU).
pub const DEFAULT_M_COST: u32 = 65536;
pub const DEFAULT_T_COST: u32 = 3;
pub const DEFAULT_P_COST: u32 = 1;

/// One xpub-derived wrapping slot for `ProtectionMeta::XpubKey`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XpubSlot {
    /// Master fingerprint (8-char lowercase hex) that identifies the key.
    pub mfp: String,
    pub salt: String,
    pub m_cost: u32,
    pub t_cost: u32,
    pub p_cost: u32,
    pub wrapped_key: String,
}

/// Wrap `data_key` using `xpub` as credential and return a new slot.
pub fn wrap_with_xpub(mfp: &str, xpub: &str, data_key: &str) -> Result<XpubSlot> {
    let salt = generate_salt();
    let wrapping_key =
        derive_key_from_password(xpub, &salt, DEFAULT_M_COST, DEFAULT_T_COST, DEFAULT_P_COST)?;
    let wrapped_key = wrap_key(data_key, &wrapping_key)?;
    Ok(XpubSlot {
        mfp: mfp.to_string(),
        salt,
        m_cost: DEFAULT_M_COST,
        t_cost: DEFAULT_T_COST,
        p_cost: DEFAULT_P_COST,
        wrapped_key,
    })
}

/// Try `xpub` against every slot and return the data key on first match.
pub fn unwrap_xpub_slots(xpub: &str, slots: &[XpubSlot]) -> Result<String> {
    for slot in slots {
        let wrapping_key =
            derive_key_from_password(xpub, &slot.salt, slot.m_cost, slot.t_cost, slot.p_cost)?;
        if let Ok(data_key) = unwrap_key(&slot.wrapped_key, &wrapping_key) {
            return Ok(data_key);
        }
    }
    Err(anyhow!("xpub does not match any registered slot"))
}

/// The protection metadata stored alongside each wallet .db file.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ProtectionMeta {
    DeviceKey {
        version: u8,
        wrapped_key: String,
    },
    UserPassword {
        version: u8,
        salt: String,
        m_cost: u32,
        t_cost: u32,
        p_cost: u32,
        wrapped_key: String,
        /// Plaintext wallet name stored so the wallet can be shown in the list
        /// even when locked (without requiring the password).
        #[serde(default)]
        display_name: Option<String>,
        /// Cached network string (e.g. "bitcoin", "testnet") — filled at creation
        /// and refreshed whenever the wallet is successfully opened.
        #[serde(default)]
        network: Option<String>,
        /// Cached last-synced Unix timestamp — refreshed whenever the wallet is
        /// successfully opened.
        #[serde(default)]
        last_synced_at: Option<i64>,
    },
    /// Each xpub in the descriptor gets its own slot; any one can unlock.
    XpubKey {
        version: u8,
        slots: Vec<XpubSlot>,
        #[serde(default)]
        display_name: Option<String>,
        #[serde(default)]
        network: Option<String>,
        #[serde(default)]
        last_synced_at: Option<i64>,
    },
}

/// Resolve the data key from protection metadata.
/// - For `DeviceKey`: `credential` is the device key hex.
/// - For `UserPassword`: `credential` is the user's password.
/// - For `XpubKey`: `credential` is any registered xpub string.
pub fn resolve_data_key(meta: &ProtectionMeta, credential: &str) -> Result<String> {
    match meta {
        ProtectionMeta::DeviceKey { wrapped_key, .. } => unwrap_key(wrapped_key, credential),
        ProtectionMeta::UserPassword {
            salt,
            m_cost,
            t_cost,
            p_cost,
            wrapped_key,
            ..
        } => {
            let wrapping_key =
                derive_key_from_password(credential, salt, *m_cost, *t_cost, *p_cost)?;
            unwrap_key(wrapped_key, &wrapping_key)
        }
        ProtectionMeta::XpubKey { slots, .. } => unwrap_xpub_slots(credential, slots),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_data_key_length() {
        let key = generate_data_key();
        assert_eq!(key.len(), 64, "32 bytes → 64 hex chars");
        assert!(key.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_generate_salt_length() {
        let salt = generate_salt();
        assert_eq!(salt.len(), 32, "16 bytes → 32 hex chars");
    }

    #[test]
    fn test_generate_data_key_unique() {
        assert_ne!(generate_data_key(), generate_data_key());
    }

    #[test]
    fn test_wrap_unwrap_roundtrip() {
        let data_key = generate_data_key();
        let wrapping_key = generate_data_key(); // also 32 bytes
        let wrapped = wrap_key(&data_key, &wrapping_key).expect("wrap failed");
        let recovered = unwrap_key(&wrapped, &wrapping_key).expect("unwrap failed");
        assert_eq!(recovered, data_key);
    }

    #[test]
    fn test_unwrap_wrong_key_fails() {
        let data_key = generate_data_key();
        let wrapping_key = generate_data_key();
        let wrapped = wrap_key(&data_key, &wrapping_key).expect("wrap failed");

        let wrong_key = generate_data_key();
        let result = unwrap_key(&wrapped, &wrong_key);
        assert!(result.is_err(), "Should fail with wrong key");
    }

    #[test]
    fn test_derive_key_deterministic() {
        let password = "test-password-123";
        let salt = generate_salt();
        let key1 = derive_key_from_password(password, &salt, 1024, 1, 1).unwrap();
        let key2 = derive_key_from_password(password, &salt, 1024, 1, 1).unwrap();
        assert_eq!(key1, key2, "Same password+salt must yield same key");
    }

    #[test]
    fn test_derive_key_different_passwords() {
        let salt = generate_salt();
        let key1 = derive_key_from_password("password1", &salt, 1024, 1, 1).unwrap();
        let key2 = derive_key_from_password("password2", &salt, 1024, 1, 1).unwrap();
        assert_ne!(key1, key2);
    }

    #[test]
    fn test_derive_key_different_salts() {
        let salt1 = generate_salt();
        let salt2 = generate_salt();
        let key1 = derive_key_from_password("same-password", &salt1, 1024, 1, 1).unwrap();
        let key2 = derive_key_from_password("same-password", &salt2, 1024, 1, 1).unwrap();
        assert_ne!(key1, key2);
    }

    #[test]
    fn test_resolve_data_key_device_type() {
        let data_key = generate_data_key();
        let device_key = generate_data_key();
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
        let data_key = generate_data_key();
        let password = "my-wallet-password";
        let salt = generate_salt();
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
        };
        let resolved = resolve_data_key(&meta, password).unwrap();
        assert_eq!(resolved, data_key);
    }

    #[test]
    fn test_resolve_data_key_wrong_password_fails() {
        let data_key = generate_data_key();
        let password = "correct-password";
        let salt = generate_salt();
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
        let data_key = generate_data_key();
        let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key).unwrap();
        assert_eq!(slot.mfp, "c449c5c5");

        let slots = vec![slot];
        let recovered = unwrap_xpub_slots(TEST_XPUB, &slots).unwrap();
        assert_eq!(recovered, data_key);
    }

    #[test]
    fn test_unwrap_xpub_wrong_xpub_fails() {
        let data_key = generate_data_key();
        let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key).unwrap();
        let result = unwrap_xpub_slots(TEST_XPUB2, &[slot]);
        assert!(result.is_err(), "Different xpub must not unlock");
    }

    #[test]
    fn test_unwrap_xpub_any_slot_works() {
        let data_key = generate_data_key();
        let slot1 = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key).unwrap();
        let slot2 = wrap_with_xpub("c61af686", TEST_XPUB2, &data_key).unwrap();
        let slots = vec![slot1, slot2];

        let r1 = unwrap_xpub_slots(TEST_XPUB, &slots).unwrap();
        let r2 = unwrap_xpub_slots(TEST_XPUB2, &slots).unwrap();
        assert_eq!(r1, data_key);
        assert_eq!(r2, data_key);
    }

    #[test]
    fn test_protection_meta_serde_xpub_key() {
        let data_key = generate_data_key();
        let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key).unwrap();
        let meta = ProtectionMeta::XpubKey {
            version: 1,
            slots: vec![slot],
            display_name: Some("Test".to_string()),
            network: Some("bitcoin".to_string()),
            last_synced_at: None,
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
    fn test_resolve_data_key_xpub_type() {
        let data_key = generate_data_key();
        let slot = wrap_with_xpub("c449c5c5", TEST_XPUB, &data_key).unwrap();
        let meta = ProtectionMeta::XpubKey {
            version: 1,
            slots: vec![slot],
            display_name: None,
            network: None,
            last_synced_at: None,
        };
        let resolved = resolve_data_key(&meta, TEST_XPUB).unwrap();
        assert_eq!(resolved, data_key);

        let bad = resolve_data_key(&meta, TEST_XPUB2);
        assert!(bad.is_err());
    }
}
