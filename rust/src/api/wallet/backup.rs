use super::*;

// ---------------------------------------------------------------------------
// Backup functions (.deadbolt format)
// ---------------------------------------------------------------------------

/// Return type of `import_wallet_backup` — carries the restored wallet info.
pub struct WalletImportResult {
    pub wallet: crate::api::model::APIWalletInfo,
}
//
// Format v1:
// {
//   "version": 1,
//   "wallet_name": "...",
//   "network": "bitcoin",
//   "created_at": 1234567890,
//   "protection": { "type": 1, "salt": "<hex>", "m_cost": 65536, "t_cost": 3, "p_cost": 1 },
//   "data_key_wrapped": "<hex(nonce||AES-GCM(export_key, data_key_bytes))>",
//   "data": "<base64(nonce||AES-GCM(export_key, raw_sqlcipher_db_bytes))>"
// }
//
// The backup password always protects both the raw DB file and the data_key.
// On import: derive export_key → unwrap data_key → decrypt DB → re-key to new data_key.

/// Export a wallet to a self-contained encrypted `.deadbolt` backup (v2 format).
///
/// `export_protection` must be `UserPassword` or `XpubKey`.
/// - `UserPassword`: provide `export_password`; the credential is protected with Argon2id.
/// - `XpubKey`: xpubs are auto-extracted from the descriptor; each gets its own slot.
///
/// `security_level` controls the Argon2id parameters for the export credential slots.
/// The returned bytes should be saved as a `.deadbolt` file.
pub fn export_wallet_backup(
    wallet_path: String,
    device_key_hex: String,
    open_password: Option<String>,
    export_protection: APIProtectionType,
    export_password: Option<String>,
    security_level: APISecurityLevel,
) -> Result<Vec<u8>> {
    use crate::core::key_protection::{
        derive_key_from_password, generate_salt, wrap_with_xpub, DEFAULT_P_COST,
    };
    use base64::{engine::general_purpose, Engine as _};

    if matches!(export_protection, APIProtectionType::DeviceKey) {
        return Err(anyhow::anyhow!(
            "DeviceKey protection cannot be used for backup export"
        ));
    }

    let wallet_data_key =
        resolve_wallet_key(&wallet_path, &device_key_hex, open_password.as_deref())?;
    let row = {
        let conn = open_encrypted_connection(&wallet_path, &wallet_data_key)?;
        read_wallet_info(&conn)?
    };

    // Read a complete, consistent snapshot of the database by using VACUUM INTO,
    // which consolidates the WAL into the destination file atomically.  Reading
    // the raw .db file directly would miss any writes still pending in the WAL.
    // The destination file is encrypted with the same key as the source because
    // SQLCipher applies its codec at the pager level during VACUUM INTO.
    let temp_path = format!("{}.export_tmp", wallet_path);
    // Remove any leftover temp file from a previously aborted export.
    let _ = std::fs::remove_file(&temp_path);
    let db_bytes = {
        let conn = open_encrypted_connection(&wallet_path, &wallet_data_key)?;
        conn.execute(
            &format!("VACUUM INTO '{}'", temp_path.replace('\'', "''")),
            [],
        )?;
        drop(conn);
        let bytes = std::fs::read(&temp_path);
        let _ = std::fs::remove_file(&temp_path);
        bytes?
    };
    let export_data_key = generate_data_key();
    let m_cost = security_level.m_cost();
    let t_cost = security_level.t_cost();

    let (ptype, slots): (u64, Vec<serde_json::Value>) = match export_protection {
        APIProtectionType::UserPassword => {
            let password = export_password
                .ok_or_else(|| anyhow::anyhow!("Export password required for UserPassword"))?;
            let salt = generate_salt();
            let wrapping_key =
                derive_key_from_password(&password, &salt, m_cost, t_cost, DEFAULT_P_COST)?;
            let wrapped_key =
                crate::core::key_protection::wrap_key(&export_data_key, &wrapping_key)?;
            let slot = serde_json::json!({
                "mfp": "",
                "salt": salt,
                "m_cost": m_cost,
                "t_cost": t_cost,
                "p_cost": DEFAULT_P_COST,
                "wrapped_key": wrapped_key
            });
            (1, vec![slot])
        }
        APIProtectionType::XpubKey => {
            let map = super::extract_xpub_mfp_map(&row.descriptor);
            if map.is_empty() {
                return Err(anyhow::anyhow!(
                    "No xpubs found in descriptor for XpubKey export"
                ));
            }
            let slots = map
                .iter()
                .map(|(mfp, xpub)| {
                    let slot = wrap_with_xpub(mfp, xpub, &export_data_key, m_cost, t_cost, "")?;
                    serde_json::to_value(&slot).map_err(|e| anyhow::anyhow!(e))
                })
                .collect::<Result<Vec<_>>>()?;
            (2, slots)
        }
        APIProtectionType::DeviceKey => {
            return Err(anyhow::anyhow!("DeviceKey wallets cannot be exported"))
        }
    };

    let encrypted_db = encrypt_bytes(&export_data_key, &db_bytes)?;
    let data_b64 = general_purpose::STANDARD.encode(&encrypted_db);

    let wallet_data_key_bytes = hex::decode(&wallet_data_key)?;
    let encrypted_wallet_key = encrypt_bytes(&export_data_key, &wallet_data_key_bytes)?;
    let data_key_wrapped = hex::encode(&encrypted_wallet_key);

    let backup = serde_json::json!({
        "version": 2,
        "wallet_name": row.name,
        "network": row.network,
        "created_at": row.created_at,
        "protection": {
            "type": ptype,
            "slots": slots
        },
        "data_key_wrapped": data_key_wrapped,
        "data": data_b64,
    });

    Ok(serde_json::to_vec(&backup)?)
}

/// Import a `.deadbolt` backup (v1 or v2) and add it as a new wallet in `wallets_dir`.
///
/// `import_credential`: password for UserPassword backups, xpub or keyspec for XpubKey backups.
/// Returns the restored wallet info together with signature verification status.
pub fn import_wallet_backup(
    backup_bytes: Vec<u8>,
    import_credential: String,
    device_key_hex: String,
    wallets_dir: String,
) -> Result<WalletImportResult> {
    use crate::core::key_protection::{
        derive_key_from_password, generate_data_key, resolve_xpub_data_key, wrap_key,
        ProtectionMeta, XpubSlot,
    };
    use crate::core::wallet_meta::write_meta;
    use base64::{engine::general_purpose, Engine as _};

    let backup: serde_json::Value = serde_json::from_slice(&backup_bytes)
        .map_err(|e| anyhow::anyhow!("Invalid backup format: {}", e))?;

    let version = backup["version"]
        .as_u64()
        .ok_or_else(|| anyhow::anyhow!("Missing version in backup"))?;

    let data_b64 = backup["data"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing data in backup"))?;
    let data_key_wrapped_hex = backup["data_key_wrapped"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing data_key_wrapped in backup"))?;

    // Resolve export_data_key from whichever version/protection format is present.
    let export_data_key = if version == 1 {
        // v1: protection has salt/m_cost/t_cost/p_cost directly; import_credential is a password.
        let protection = &backup["protection"];
        let salt = protection["salt"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing salt in v1 backup"))?;
        let m_cost = protection["m_cost"].as_u64().unwrap_or(65536) as u32;
        let t_cost = protection["t_cost"].as_u64().unwrap_or(3) as u32;
        let p_cost = protection["p_cost"].as_u64().unwrap_or(1) as u32;
        // In v1, export_key = Argon2id(password, salt) and data_key_wrapped was encrypted
        // with export_key directly (there is no intermediate export_data_key).
        // Re-use the same path: derive the key and treat it as export_data_key.
        derive_key_from_password(&import_credential, salt, m_cost, t_cost, p_cost)?
    } else if version == 2 {
        // v2: protection has type + slots array.
        let protection = &backup["protection"];
        let ptype = protection["type"].as_u64().unwrap_or(0);
        let slots = protection["slots"]
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("Missing slots in v2 backup"))?;

        // Deserialize all slots (same XpubSlot format for both ptype=1 and ptype=2).
        let xpub_slots: Vec<XpubSlot> = slots
            .iter()
            .map(|s| serde_json::from_value(s.clone()))
            .collect::<Result<_, _>>()
            .map_err(|e| anyhow::anyhow!("Invalid slot in v2 backup: {}", e))?;

        if ptype == 1 {
            // UserPassword: single slot, credential is the password.
            let slot = xpub_slots
                .first()
                .ok_or_else(|| anyhow::anyhow!("No slots in v2 UserPassword backup"))?;
            let wrapping_key = derive_key_from_password(
                &import_credential,
                &slot.salt,
                slot.m_cost,
                slot.t_cost,
                slot.p_cost,
            )?;
            crate::core::key_protection::unwrap_key(&slot.wrapped_key, &wrapping_key)?
        } else if ptype == 2 {
            // XpubKey: try each slot with the provided xpub/keyspec credential.
            resolve_xpub_data_key(&import_credential, &xpub_slots)
                .map_err(|_| anyhow::anyhow!("xpub does not match any slot in backup"))?
        } else {
            return Err(anyhow::anyhow!("Unknown backup protection type: {}", ptype));
        }
    } else {
        return Err(anyhow::anyhow!("Unsupported backup version: {}", version));
    };

    let wallet_key_encrypted = hex::decode(data_key_wrapped_hex)?;
    let wallet_data_key_bytes = decrypt_bytes(&export_data_key, &wallet_key_encrypted)?;
    let wallet_data_key = hex::encode(&wallet_data_key_bytes);

    let encrypted_db = general_purpose::STANDARD
        .decode(data_b64)
        .map_err(|e| anyhow::anyhow!("base64 decode: {}", e))?;
    let db_bytes = decrypt_bytes(&export_data_key, &encrypted_db)?;

    std::fs::create_dir_all(&wallets_dir)?;
    let uuid = generate_uuid_v4();
    let path = std::path::Path::new(&wallets_dir)
        .join(format!("{}.db", uuid))
        .to_string_lossy()
        .to_string();
    std::fs::write(&path, &db_bytes)?;

    let new_data_key = generate_data_key();
    crate::core::wallet_persistence::rekey_database(&path, &wallet_data_key, &new_data_key)?;

    let wrapped_key = wrap_key(&new_data_key, &device_key_hex)?;
    let meta = ProtectionMeta::DeviceKey {
        version: 1,
        wrapped_key,
    };
    write_meta(&path, &meta)?;

    let conn = open_encrypted_connection(&path, &new_data_key)?;
    let row = read_wallet_info(&conn)?;
    drop(conn);

    let wallet = super::row_to_api_info(path, row)?;
    Ok(WalletImportResult { wallet })
}

/// Inspect a `.deadbolt` backup and return its protection type without decrypting it.
pub fn inspect_wallet_backup(backup_bytes: Vec<u8>) -> Result<APIProtectionType> {
    let backup: serde_json::Value = serde_json::from_slice(&backup_bytes)
        .map_err(|e| anyhow::anyhow!("Invalid backup format: {}", e))?;
    let ptype = backup["protection"]["type"].as_u64().unwrap_or(0);
    Ok(match ptype {
        1 => APIProtectionType::UserPassword,
        2 => APIProtectionType::XpubKey,
        _ => APIProtectionType::DeviceKey,
    })
}
