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

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;
        let is_first_sync = read_wallet_info(&core.conn)?.last_synced_at.is_none();

        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);

        if is_first_sync {
            let request = core.wallet.start_full_scan();
            let update = client.full_scan(request, STOP_GAP, BATCH_SIZE, false)?;
            core.wallet.apply_update(update)?;
        } else {
            let request = core.wallet.start_sync_with_revealed_spks();
            let update = client.sync(request, BATCH_SIZE, false)?;
            core.wallet.apply_update(update)?;
        }

        core.persist()?;
        touch_last_synced(&core.conn)?;

        // Auto-delete PSBTs whose transaction is now known to the wallet
        // (broadcast externally and seen by Electrum during this sync).
        cleanup_broadcast_psbts(&mut core);

        drop(core);
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(())
    }

    /// Force a full scan regardless of sync history (re-discovers all addresses).
    pub async fn rescan(&self, electrum_url: String) -> Result<()> {
        use bdk_electrum::electrum_client;
        use bdk_electrum::BdkElectrumClient;

        let mut core = self
            .inner
            .lock()
            .map_err(|_| anyhow::anyhow!("wallet lock poisoned"))?;

        let client = BdkElectrumClient::new(electrum_client::Client::new(&electrum_url)?);
        let request = core.wallet.start_full_scan();
        let update = client.full_scan(request, STOP_GAP, BATCH_SIZE, false)?;
        core.wallet.apply_update(update)?;
        core.persist()?;
        touch_last_synced(&core.conn)?;

        // Auto-delete PSBTs whose transaction is now known after rescan.
        cleanup_broadcast_psbts(&mut core);

        drop(core);
        if let Ok(mut u) = self.electrum_url.lock() {
            *u = electrum_url;
        }

        Ok(())
    }
}
