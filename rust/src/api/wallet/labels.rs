use super::*;

impl APIWallet {
    /// Persist a label for a transaction. Pass an empty string to remove it.
    /// Automatically propagates to related entities (addresses and UTXOs).
    /// Clearing an inherited (auto) label is a no-op.
    #[frb(sync)]
    pub fn set_tx_label(&self, txid: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        if label.is_empty() {
            match get_tx_label_with_flag(&core.conn, &txid)? {
                Some((_, false)) => {
                    // Explicit label: delete the row and cascade.
                    db_set_tx_label(&core.conn, &txid, "", false, None)?;
                    cascade_delete_label(&core.conn, EntityType::Tx, &txid)?;
                }
                Some((_, true)) => {
                    // Inherited auto-label: no-op — only the source can clear it.
                }
                None => {} // Nothing to do.
            }
        } else {
            db_set_tx_label(&core.conn, &txid, &label, false, None)?;
            propagate_label(&core.conn, &core.wallet, EntityType::Tx, &txid, &label)?;
        }
        Ok(())
    }

    /// Persist a label for an address. Pass an empty string to remove it.
    /// Automatically propagates to related entities (transactions and UTXOs).
    /// Clearing an inherited (auto) label is a no-op.
    #[frb(sync)]
    pub fn set_address_label(&self, address: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        if label.is_empty() {
            match get_address_label_with_flag(&core.conn, &address)? {
                Some((_, false)) => {
                    // Explicit label: delete the row and cascade.
                    db_set_address_label(&core.conn, &address, "", false, None)?;
                    cascade_delete_label(&core.conn, EntityType::Address, &address)?;
                }
                Some((_, true)) => {
                    // Inherited auto-label: no-op — only the source can clear it.
                }
                None => {} // Nothing to do.
            }
        } else {
            db_set_address_label(&core.conn, &address, &label, false, None)?;
            propagate_label(
                &core.conn,
                &core.wallet,
                EntityType::Address,
                &address,
                &label,
            )?;
        }
        Ok(())
    }

    /// Persist a label for a coin (UTXO) by outpoint. Pass an empty string to remove it.
    /// Automatically propagates to related entities (transaction and address).
    /// Clearing an inherited (auto) label is a no-op.
    #[frb(sync)]
    pub fn set_coin_label(&self, txid: String, vout: u32, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let outpoint = format!("{}:{}", txid, vout);

        if label.is_empty() {
            match get_coin_label_with_flag(&core.conn, &outpoint)? {
                Some((_, false)) => {
                    // Explicit label: delete the row and cascade.
                    db_set_coin_label(&core.conn, &outpoint, "", false, None)?;
                    cascade_delete_label(&core.conn, EntityType::Coin, &outpoint)?;
                }
                Some((_, true)) => {
                    // Inherited auto-label: no-op — only the source can clear it.
                }
                None => {} // Nothing to do.
            }
        } else {
            db_set_coin_label(&core.conn, &outpoint, &label, false, None)?;
            propagate_label(
                &core.conn,
                &core.wallet,
                EntityType::Coin,
                &outpoint,
                &label,
            )?;
        }
        Ok(())
    }

    /// Return all key labels (mfp → label).
    pub fn get_key_labels(&self) -> Result<Vec<APIKeyLabel>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let map = get_all_key_labels(&core.conn).unwrap_or_default();
        Ok(map
            .into_iter()
            .map(|(mfp, label)| APIKeyLabel { mfp, label })
            .collect())
    }

    /// Persist a label for a key by master fingerprint. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_key_label(&self, mfp: String, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_key_label(&core.conn, &mfp, &label)
    }

    /// Return all spend-path labels (rust_id → label).
    pub fn get_path_labels(&self) -> Result<Vec<APIPathLabel>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let map = get_all_path_labels(&core.conn).unwrap_or_default();
        Ok(map
            .into_iter()
            .map(|(rust_id, label)| APIPathLabel { rust_id, label })
            .collect())
    }

    /// Persist a label for a spend path by rust_id. Pass an empty string to remove it.
    #[frb(sync)]
    pub fn set_path_label(&self, rust_id: u32, label: String) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        db_set_path_label(&core.conn, rust_id, &label)
    }

    /// Repropagate all existing explicit labels to their related entities.
    /// Useful after imports or migrations. Clears all auto labels first.
    #[frb(sync)]
    pub fn repropagate_all_labels(&self) -> Result<()> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        // Clear all auto-labels (identified by a non-NULL source_entity).
        core.conn
            .execute("DELETE FROM tx_labels WHERE source_entity IS NOT NULL", [])?;
        core.conn.execute(
            "DELETE FROM address_labels WHERE source_entity IS NOT NULL",
            [],
        )?;
        core.conn.execute(
            "DELETE FROM coin_labels WHERE source_entity IS NOT NULL",
            [],
        )?;

        // Re-propagate only explicit labels.
        let tx_labels = get_all_tx_labels_with_flag(&core.conn)?;
        for (txid, (label, is_auto)) in tx_labels {
            if !is_auto && !label.is_empty() {
                propagate_label(&core.conn, &core.wallet, EntityType::Tx, &txid, &label)?;
            }
        }

        let address_labels = get_all_address_labels_with_flag(&core.conn)?;
        for (address, (label, is_auto)) in address_labels {
            if !is_auto && !label.is_empty() {
                propagate_label(
                    &core.conn,
                    &core.wallet,
                    EntityType::Address,
                    &address,
                    &label,
                )?;
            }
        }

        let coin_labels = get_all_coin_labels_with_flag(&core.conn)?;
        for (outpoint, (label, is_auto)) in coin_labels {
            if !is_auto && !label.is_empty() {
                propagate_label(
                    &core.conn,
                    &core.wallet,
                    EntityType::Coin,
                    &outpoint,
                    &label,
                )?;
            }
        }

        Ok(())
    }

    // -----------------------------------------------------------------------
    // BIP-329 label import / export
    // -----------------------------------------------------------------------

    /// Export all explicit (non-auto) labels to BIP-329 JSONL format.
    #[frb(sync)]
    pub fn export_bip329(&self) -> Result<Vec<String>> {
        let core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let conn = &core.conn;
        let mut lines: Vec<String> = Vec::new();

        for (txid, (label, is_auto)) in get_all_tx_labels_with_flag(conn)? {
            if !is_auto && !label.is_empty() {
                lines.push(serde_json::json!({"type":"tx","ref":txid,"label":label}).to_string());
            }
        }
        for (address, (label, is_auto)) in get_all_address_labels_with_flag(conn)? {
            if !is_auto && !label.is_empty() {
                lines.push(
                    serde_json::json!({"type":"addr","ref":address,"label":label}).to_string(),
                );
            }
        }
        for (outpoint, (label, is_auto)) in get_all_coin_labels_with_flag(conn)? {
            if !is_auto && !label.is_empty() {
                lines.push(
                    serde_json::json!({"type":"output","ref":outpoint,"label":label}).to_string(),
                );
            }
        }

        // Export key labels as "xpub" type using mfp→xpub map from descriptor.
        let wallet_info = read_wallet_info(conn)?;
        let mfp_to_xpub = extract_xpub_mfp_map(&wallet_info.descriptor);
        for (mfp, label) in get_all_key_labels(conn)? {
            if !label.is_empty() {
                if let Some(xpub) = mfp_to_xpub.get(&mfp) {
                    lines.push(
                        serde_json::json!({"type":"xpub","ref":xpub,"label":label}).to_string(),
                    );
                }
            }
        }

        Ok(lines)
    }

    /// Import labels from BIP-329 JSONL. Sets all as explicit, then re-propagates.
    /// Malformed lines and unknown types are silently skipped.
    #[frb(sync)]
    pub fn import_bip329(&self, lines: Vec<String>) -> Result<()> {
        // Phase 1: apply under lock
        {
            let core = self
                .inner
                .lock()
                .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
            let conn = &core.conn;

            // Build xpub→mfp reverse map from descriptor.
            let wallet_info = read_wallet_info(conn)?;
            let xpub_to_mfp: std::collections::HashMap<String, String> =
                extract_xpub_mfp_map(&wallet_info.descriptor)
                    .into_iter()
                    .map(|(mfp, xpub)| (xpub, mfp))
                    .collect();

            for line in &lines {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                let Ok(obj) = serde_json::from_str::<serde_json::Value>(trimmed) else {
                    continue;
                };
                let Some(t) = obj.get("type").and_then(|v| v.as_str()) else {
                    continue;
                };
                let Some(r) = obj.get("ref").and_then(|v| v.as_str()) else {
                    continue;
                };
                let Some(l) = obj.get("label").and_then(|v| v.as_str()) else {
                    continue;
                };
                if l.is_empty() {
                    continue;
                }
                match t {
                    "tx" => db_set_tx_label(conn, r, l, false, None)?,
                    "addr" => db_set_address_label(conn, r, l, false, None)?,
                    "output" => db_set_coin_label(conn, r, l, false, None)?,
                    "xpub" => {
                        if let Some(mfp) = xpub_to_mfp.get(r) {
                            db_set_key_label(conn, mfp, l)?
                        } else {
                            continue; // xpub not in this wallet's descriptor — ignore
                        }
                    }
                    _ => continue,
                }
            }
        } // lock released

        // Phase 2: re-propagate (re-acquires lock internally)
        self.repropagate_all_labels()
    }
}
