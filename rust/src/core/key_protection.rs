use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use anyhow::{anyhow, Result};
use argon2::{Algorithm, Argon2, Params, Version};
use rand::rngs::OsRng;
use rand::TryRngCore;
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

/// Generate 32 random bytes and return them as lowercase hex (64 chars).
pub fn generate_data_key() -> String {
    let mut bytes = Zeroizing::new([0u8; 32]);
    OsRng.try_fill_bytes(bytes.as_mut()).expect("OS RNG failed");
    hex::encode(&bytes[..])
}

/// Generate 16 random bytes and return them as lowercase hex (32 chars).
pub fn generate_salt() -> String {
    let mut bytes = Zeroizing::new([0u8; 16]);
    OsRng.try_fill_bytes(bytes.as_mut()).expect("OS RNG failed");
    hex::encode(&bytes[..])
}

/// AES-256-GCM wrap: encrypt `data_key_hex` under `wrapping_key_hex`.
/// Returns hex(nonce || ciphertext || tag) where nonce is 12 random bytes.
pub fn wrap_key(data_key_hex: &str, wrapping_key_hex: &str) -> Result<String> {
    let data_key_bytes = Zeroizing::new(
        hex::decode(data_key_hex).map_err(|e| anyhow!("Invalid data key hex: {}", e))?,
    );
    let wrapping_key_bytes = Zeroizing::new(
        hex::decode(wrapping_key_hex).map_err(|e| anyhow!("Invalid wrapping key hex: {}", e))?,
    );
    if wrapping_key_bytes.len() != 32 {
        return Err(anyhow!("Wrapping key must be 32 bytes"));
    }

    let cipher = Aes256Gcm::new_from_slice(&wrapping_key_bytes)
        .map_err(|e| anyhow!("AES-GCM key init: {}", e))?;

    // Random 12-byte nonce
    let mut nonce_bytes = Zeroizing::new([0u8; 12]);
    OsRng
        .try_fill_bytes(nonce_bytes.as_mut())
        .expect("OS RNG failed");
    let nonce = Nonce::from_slice(nonce_bytes.as_ref());

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
    let combined = Zeroizing::new(
        hex::decode(wrapped_key_hex).map_err(|e| anyhow!("Invalid wrapped key hex: {}", e))?,
    );
    if combined.len() < 12 {
        return Err(anyhow!("Wrapped key too short"));
    }

    let wrapping_key_bytes = Zeroizing::new(
        hex::decode(wrapping_key_hex).map_err(|e| anyhow!("Invalid wrapping key hex: {}", e))?,
    );
    if wrapping_key_bytes.len() != 32 {
        return Err(anyhow!("Wrapping key must be 32 bytes"));
    }

    let nonce = Nonce::from_slice(&combined[..12]);
    let ciphertext = &combined[12..];

    let cipher = Aes256Gcm::new_from_slice(&wrapping_key_bytes)
        .map_err(|e| anyhow!("AES-GCM key init: {}", e))?;

    let plaintext = Zeroizing::new(
        cipher
            .decrypt(nonce, ciphertext)
            .map_err(|_| anyhow!("AES-GCM decrypt failed — wrong key or corrupted data"))?,
    );

    Ok(hex::encode(&*plaintext))
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

    let mut output = Zeroizing::new([0u8; 32]);
    argon2
        .hash_password_into(password.as_bytes(), &salt, output.as_mut())
        .map_err(|e| anyhow!("Argon2id hash: {}", e))?;

    Ok(hex::encode(&output[..]))
}

/// AES-256-GCM encrypt arbitrary bytes under `key_hex`.
/// Returns `nonce[12] || ciphertext || tag`.
pub fn encrypt_bytes(key_hex: &str, plaintext: &[u8]) -> Result<Vec<u8>> {
    let key_bytes =
        Zeroizing::new(hex::decode(key_hex).map_err(|e| anyhow!("Invalid key hex: {}", e))?);
    let cipher =
        Aes256Gcm::new_from_slice(&key_bytes).map_err(|e| anyhow!("AES-GCM key init: {}", e))?;
    let mut nonce_bytes = Zeroizing::new([0u8; 12]);
    OsRng
        .try_fill_bytes(nonce_bytes.as_mut())
        .expect("OS RNG failed");
    let nonce = Nonce::from_slice(nonce_bytes.as_ref());
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
    let key_bytes =
        Zeroizing::new(hex::decode(key_hex).map_err(|e| anyhow!("Invalid key hex: {}", e))?);
    let cipher =
        Aes256Gcm::new_from_slice(&key_bytes).map_err(|e| anyhow!("AES-GCM key init: {}", e))?;
    let nonce = Nonce::from_slice(&ciphertext[..12]);
    cipher
        .decrypt(nonce, &ciphertext[12..])
        .map_err(|_| anyhow!("Decryption failed — wrong password or corrupted data"))
}

/// Parallelism factor for all Argon2id operations.
/// Always 1 — mobile devices have limited memory bandwidth.
pub const DEFAULT_P_COST: u32 = 1;

/// A biometric-derived slot that wraps the wallet data key with a platform-stored random key.
/// The random key lives in the platform's secure storage (Android Keystore / iOS Keychain),
/// gated behind biometric authentication in the Flutter layer.
/// No KDF is used: the biometric key is already 32 bytes of random entropy.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiometricSlot {
    /// Unique identifier (UUID v4) used as the key name in the platform keystore.
    pub id: String,
    /// Wallet data key wrapped with the biometric key via AES-256-GCM.
    pub wrapped_key: String,
}

/// One xpub-derived wrapping slot for `ProtectionMeta::XpubKey`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XpubSlot {
    /// Master fingerprint (8-char lowercase hex) that identifies the key.
    pub mfp: String,
    pub salt: String,
    pub m_cost: u32,
    pub t_cost: u32,
    pub p_cost: u32,
    /// Derivation path suffix (e.g. "48h/0h/0h/2h") stored for UI hint display.
    /// Empty for legacy slots created before this field was added.
    #[serde(default)]
    pub derivation: String,
    pub wrapped_key: String,
}

/// Wrap `data_key` using `xpub` as credential and return a new slot.
/// `derivation` is the path suffix (e.g. "48h/0h/0h/2h") stored as a display hint.
pub fn wrap_with_xpub(
    mfp: &str,
    xpub: &str,
    data_key: &str,
    m_cost: u32,
    t_cost: u32,
    derivation: &str,
) -> Result<XpubSlot> {
    let salt = generate_salt();
    let wrapping_key = Zeroizing::new(derive_key_from_password(
        xpub,
        &salt,
        m_cost,
        t_cost,
        DEFAULT_P_COST,
    )?);
    let wrapped_key = wrap_key(data_key, &wrapping_key)?;
    Ok(XpubSlot {
        mfp: mfp.to_string(),
        salt,
        m_cost,
        t_cost,
        p_cost: DEFAULT_P_COST,
        derivation: derivation.to_string(),
        wrapped_key,
    })
}

/// Parse a credential that may be a bare xpub or a keyspec `[mfp/path]xpub`.
/// Returns `(mfp_hint, xpub)` where `mfp_hint` is `Some(8-char hex)` if parsed.
pub fn parse_xpub_credential(credential: &str) -> (Option<&str>, &str) {
    let trimmed = credential.trim();
    if let Some(rest) = trimmed.strip_prefix('[') {
        if let Some(bracket_end) = rest.find(']') {
            let inside = &rest[..bracket_end];
            let mfp_end = inside.find('/').unwrap_or(inside.len());
            let mfp = &inside[..mfp_end];
            let xpub = rest[bracket_end + 1..].trim();
            if mfp.len() == 8 && mfp.chars().all(|c| c.is_ascii_hexdigit()) && !xpub.is_empty() {
                return (Some(mfp), xpub);
            }
        }
    }
    (None, trimmed)
}

/// Try `xpub` against slots and return `(data_key, matched_mfp)` on first match.
/// When `mfp_hint` is provided, only the matching slot is tried (fast path).
/// When `mfp_hint` is `None`, all slots are tried in order.
pub fn unwrap_xpub_slots(
    xpub: &str,
    mfp_hint: Option<&str>,
    slots: &[XpubSlot],
) -> Result<(String, String)> {
    for slot in slots {
        if let Some(hint) = mfp_hint {
            if slot.mfp != hint {
                continue;
            }
        }
        let wrapping_key = Zeroizing::new(derive_key_from_password(
            xpub,
            &slot.salt,
            slot.m_cost,
            slot.t_cost,
            slot.p_cost,
        )?);
        if let Ok(data_key) = unwrap_key(&slot.wrapped_key, &wrapping_key) {
            return Ok((data_key, slot.mfp.clone()));
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
        /// Optional biometric slots — each wraps the same data key with a different
        /// platform-keystore-backed random key. Any slot can unlock the wallet.
        #[serde(default)]
        biometric_slots: Vec<BiometricSlot>,
        /// SHA-256 hex of the first external receive address (index 0). Stored so that
        /// locked wallets can be matched against discovered accounts during seed recovery
        /// without revealing the descriptor or xpub.
        #[serde(default)]
        first_address_hash: Option<String>,
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
        /// Optional biometric slots — each wraps the same data key with a different
        /// platform-keystore-backed random key. Any slot can unlock the wallet.
        #[serde(default)]
        biometric_slots: Vec<BiometricSlot>,
        /// SHA-256 hex of the first external receive address (index 0).
        #[serde(default)]
        first_address_hash: Option<String>,
    },
}

/// Try `biometric_key_hex` against all biometric slots and return the data key on first match.
/// The biometric key is used directly as the AES-256-GCM wrapping key (no KDF).
pub fn unwrap_biometric_slots(biometric_key_hex: &str, slots: &[BiometricSlot]) -> Result<String> {
    for slot in slots {
        if let Ok(data_key) = unwrap_key(&slot.wrapped_key, biometric_key_hex) {
            return Ok(data_key);
        }
    }
    Err(anyhow!("biometric key does not match any registered slot"))
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
            let wrapping_key = Zeroizing::new(derive_key_from_password(
                credential, salt, *m_cost, *t_cost, *p_cost,
            )?);
            unwrap_key(wrapped_key, &wrapping_key)
        }
        ProtectionMeta::XpubKey { slots, .. } => resolve_xpub_data_key(credential, slots),
    }
}

/// Resolve the data key from an xpub credential (bare xpub or keyspec).
/// Extracted so `resolve_data_key` and `resolve_wallet_key` share the same path.
pub fn resolve_xpub_data_key(credential: &str, slots: &[XpubSlot]) -> Result<String> {
    let (mfp_hint, xpub) = parse_xpub_credential(credential);
    unwrap_xpub_slots(xpub, mfp_hint, slots).map(|(data_key, _)| data_key)
}

#[cfg(test)]
#[path = "key_protection_tests.rs"]
mod tests;
