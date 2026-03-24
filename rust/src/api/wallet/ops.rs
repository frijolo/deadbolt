use super::*;

/// Delete any PSBTs whose transaction is now known to the wallet
/// (broadcast externally and seen by Electrum during sync/rescan).
fn cleanup_broadcast_psbts(core: &mut CoreWallet) {
    if let Ok(rows) = list_psbt_rows(&core.conn) {
        for row in rows {
            if row.txid.is_empty() {
                continue;
            }
            if let Ok(txid) = row.txid.parse::<bdk_wallet::bitcoin::Txid>() {
                if core.wallet.tx_graph().get_tx(txid).is_some() {
                    apply_psbt_label_to_tx(&core.conn, &row);
                    let _ = delete_psbt_row(&core.conn, row.id);
                }
            }
        }
    }
}

impl APIWallet {
    /// Store the Electrum URL so it can be used by detail queries (e.g. fetching
    /// unknown input transactions). Call this before sync if you want it available
    /// immediately without waiting for sync to complete.
    #[frb(sync)]
    pub fn set_electrum_url(&self, url: String) {
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = url;
        }
    }

    /// Sync with Electrum, persist, and update last_synced_at.
    ///
    /// Uses full_scan on first sync (last_synced_at is None) to discover all addresses
    /// up to the stop gap. Uses incremental sync on subsequent calls to only check
    /// already-revealed script pubkeys, which is much faster.
    pub async fn sync(&self, electrum_url: String) -> Result<()> {
        use bdk_electrum::electrum_client;
        use bdk_electrum::BdkElectrumClient;

        // Phase 1: build the scan request (holds mutex briefly, then releases).
        let (is_first_sync, request_full, request_sync) = {
            let core = self.lock_wallet()?;
            let first = read_wallet_info(&core.conn)?.last_synced_at.is_none();
            let full_req = if first {
                Some(core.wallet.start_full_scan())
            } else {
                None
            };
            let sync_req = if first {
                None
            } else {
                Some(core.wallet.start_sync_with_revealed_spks())
            };
            (first, full_req, sync_req)
        };

        // Phase 2: network I/O — mutex NOT held so other threads can read the wallet.
        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);
        let update_full = if is_first_sync {
            Some(client.full_scan(request_full.unwrap(), STOP_GAP, BATCH_SIZE, false)?)
        } else {
            None
        };
        let update_sync = if !is_first_sync {
            Some(client.sync(request_sync.unwrap(), BATCH_SIZE, false)?)
        } else {
            None
        };

        // Phase 3: apply update and persist (re-acquires mutex).
        let (network, now_ts) = {
            let mut core = self.lock_wallet()?;
            if let Some(u) = update_full {
                core.wallet.apply_update(u)?;
            } else if let Some(u) = update_sync {
                core.wallet.apply_update(u)?;
            }
            core.persist()?;
            let now_ts = touch_last_synced(&core.conn)?;
            cleanup_broadcast_psbts(&mut core);
            (APINetwork::from(core.wallet.network()), now_ts)
        };

        if wallet_needs_password(&self.path) {
            refresh_user_password_meta_cache(&self.path, network, Some(now_ts));
        }
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(())
    }

    /// Force a full scan regardless of sync history (re-discovers all addresses).
    pub async fn rescan(&self, electrum_url: String) -> Result<()> {
        use bdk_electrum::electrum_client;
        use bdk_electrum::BdkElectrumClient;

        // Phase 1: build request (holds mutex briefly, then releases).
        let request = {
            let core = self.lock_wallet()?;
            core.wallet.start_full_scan()
        };

        // Phase 2: network I/O — mutex NOT held.
        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);
        let update = client.full_scan(request, STOP_GAP, BATCH_SIZE, false)?;

        // Phase 3: apply update and persist (re-acquires mutex).
        let (network, now_ts) = {
            let mut core = self.lock_wallet()?;
            core.wallet.apply_update(update)?;
            core.persist()?;
            let now_ts = touch_last_synced(&core.conn)?;
            cleanup_broadcast_psbts(&mut core);
            (APINetwork::from(core.wallet.network()), now_ts)
        };

        if wallet_needs_password(&self.path) {
            refresh_user_password_meta_cache(&self.path, network, Some(now_ts));
        }
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(())
    }
}
