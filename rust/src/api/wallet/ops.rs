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
        let client = create_electrum_client(&electrum_url)?;
        let update_full = if is_first_sync {
            let req = request_full
                .ok_or_else(|| anyhow::anyhow!("full scan request missing for first sync"))?;
            Some(client.full_scan(req, STOP_GAP, BATCH_SIZE, false)?)
        } else {
            None
        };
        let update_sync = if !is_first_sync {
            let req = request_sync
                .ok_or_else(|| anyhow::anyhow!("sync request missing for incremental sync"))?;
            Some(client.sync(req, BATCH_SIZE, false)?)
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
        // Phase 1: build request (holds mutex briefly, then releases).
        let request = {
            let core = self.lock_wallet()?;
            core.wallet.start_full_scan()
        };

        // Phase 2: network I/O — mutex NOT held.
        let client = create_electrum_client(&electrum_url)?;
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

    /// Open a reactive Electrum subscription for this wallet.
    ///
    /// Subscribes to block headers + all revealed SPKs of the wallet.
    /// Emits `true` through `sink` whenever a notification arrives
    /// (new block or scriptpubkey activity). The caller should trigger
    /// a sync on each event.
    ///
    /// Returns immediately; the listener runs on a blocking thread.
    /// The loop exits when the Dart sink is closed (StreamSubscription.cancel).
    pub async fn start_subscription(
        &self,
        electrum_url: String,
        sink: crate::frb_generated::StreamSink<bool>,
    ) -> Result<()> {
        use bdk_electrum::electrum_client::ElectrumApi;
        use bdk_wallet::KeychainKind;

        // Phase 1: ensure at least MIN_GAP addresses are revealed per keychain,
        // then capture all SPKs (mutex held briefly, then released).
        const MIN_GAP: usize = 20;
        let spks: Vec<bdk_wallet::bitcoin::ScriptBuf> = {
            let mut core = self.lock_wallet()?;
            for &keychain in &[KeychainKind::External, KeychainKind::Internal] {
                let current = core
                    .wallet
                    .spk_index()
                    .revealed_keychain_spks(keychain)
                    .count();
                for _ in current..MIN_GAP {
                    core.wallet.reveal_next_address(keychain);
                }
            }
            let _ = core.persist(); // best-effort — subscription should proceed even if persist fails
            let ext: Vec<_> = core
                .wallet
                .spk_index()
                .revealed_keychain_spks(KeychainKind::External)
                .map(|(_, spk)| spk.to_owned())
                .collect();
            let int: Vec<_> = core
                .wallet
                .spk_index()
                .revealed_keychain_spks(KeychainKind::Internal)
                .map(|(_, spk)| spk.to_owned())
                .collect();
            ext.into_iter().chain(int).collect()
        };

        // Phase 2: spawn blocking thread (does not hold the mutex).
        //
        // Outer reconnect loop + inner poll loop.
        // When the Electrum client becomes corrupted (e.g. a notification arrives for
        // an unknown scripthash — change address from an RBF tx — the cooperative
        // _reader_thread inside electrum-client fails, causing ping() to return an error),
        // we close the client and reconnect from scratch rather than trying to repair state.
        tokio::task::spawn_blocking(move || {
            // 3 s ping interval: detects dead connections quickly without rate-limiting public servers.
            // 3 s reconnect delay: fast recovery from local corruption (RBF), polite on real network failures.
            const PING_SECS: u64 = 3;
            const RECONNECT_DELAY_SECS: u64 = 3;

            'reconnect: loop {
                let client = match create_raw_electrum_client(&electrum_url) {
                    Ok(c) => c,
                    Err(_) => {
                        std::thread::sleep(std::time::Duration::from_secs(RECONNECT_DELAY_SECS));
                        continue 'reconnect;
                    }
                };

                if client.block_headers_subscribe().is_err() {
                    std::thread::sleep(std::time::Duration::from_secs(RECONNECT_DELAY_SECS));
                    continue 'reconnect;
                }

                let subscribed: Vec<&bdk_wallet::bitcoin::ScriptBuf> = spks
                    .iter()
                    .filter(|spk| client.script_subscribe(spk.as_script()).is_ok())
                    .collect();

                // Emit a trigger on reconnect so Dart syncs and catches up on missed blocks.
                if sink.add(true).is_err() {
                    break 'reconnect;
                }

                loop {
                    std::thread::sleep(std::time::Duration::from_secs(PING_SECS));

                    // ping() forces a socket read (electrum-client has no passive reader thread).
                    // An error means the connection is dead — reconnect cleanly.
                    if client.ping().is_err() {
                        std::thread::sleep(std::time::Duration::from_secs(RECONNECT_DELAY_SECS));
                        continue 'reconnect;
                    }

                    let mut triggered = false;
                    let mut corrupted = false;

                    match client.block_headers_pop() {
                        Ok(Some(_)) => triggered = true,
                        Err(_) => corrupted = true,
                        _ => {}
                    }

                    for spk in &subscribed {
                        match client.script_pop(spk.as_script()) {
                            Ok(Some(_)) => triggered = true,
                            Err(_) => {
                                corrupted = true;
                                break;
                            }
                            _ => {}
                        }
                    }

                    if corrupted {
                        std::thread::sleep(std::time::Duration::from_secs(RECONNECT_DELAY_SECS));
                        continue 'reconnect;
                    }

                    if triggered && sink.add(true).is_err() {
                        break 'reconnect;
                    }
                }
            }
        });

        Ok(())
    }
}
