use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};
use std::sync::{Mutex, RwLock};

use anyhow::Result;

/// Whether the user has enabled Tor routing (survives stop/start cycles).
static TOR_ENABLED: AtomicBool = AtomicBool::new(false);

static TOR_MANAGER: std::sync::LazyLock<TorManager> = std::sync::LazyLock::new(TorManager::new);

pub struct TorManager {
    running: AtomicBool,
    socks_port: AtomicU16,
    data_dir: Mutex<PathBuf>,
    shutdown_tx: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    /// Last error from a Tor stream connection attempt.
    last_connection_error: Mutex<Option<String>>,
    /// Bootstrap progress 0.0–1.0 and human-readable status line.
    bootstrap_status: RwLock<(f32, String)>,
}

impl TorManager {
    fn new() -> Self {
        Self {
            running: AtomicBool::new(false),
            socks_port: AtomicU16::new(0),
            data_dir: Mutex::new(std::env::temp_dir().join("deadbolt_tor")),
            shutdown_tx: Mutex::new(None),
            last_connection_error: Mutex::new(None),
            bootstrap_status: RwLock::new((0.0, String::new())),
        }
    }

    fn update_bootstrap(&self, frac: f32, label: String) {
        if let Ok(mut s) = self.bootstrap_status.write() {
            *s = (frac, label);
        }
    }

    fn bootstrap_progress(&self) -> (f32, String) {
        self.bootstrap_status
            .read()
            .map(|s| s.clone())
            .unwrap_or((0.0, String::new()))
    }

    fn set_data_dir(&self, path: &str) {
        if let Ok(mut d) = self.data_dir.lock() {
            *d = PathBuf::from(path);
        }
    }

    fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }

    fn socks_addr(&self) -> Option<String> {
        let port = self.socks_port.load(Ordering::SeqCst);
        if port == 0 {
            None
        } else {
            Some(format!("127.0.0.1:{port}"))
        }
    }

    fn store_connection_error(&self, msg: String) {
        if let Ok(mut e) = self.last_connection_error.lock() {
            *e = Some(msg);
        }
    }

    /// Take (consume) the last stored connection error, clearing it.
    pub(crate) fn take_connection_error(&self) -> Option<String> {
        self.last_connection_error.lock().ok()?.take()
    }

    fn start(&self) -> Result<()> {
        if self.running.load(Ordering::SeqCst) {
            return Ok(());
        }

        let data_dir = self
            .data_dir
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        *self.shutdown_tx.lock().unwrap_or_else(|e| e.into_inner()) = Some(shutdown_tx);

        std::thread::spawn(move || {
            let rt = match tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
            {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("[Tor] Failed to build runtime: {e}");
                    return;
                }
            };
            rt.block_on(run_tor_relay(data_dir, shutdown_rx));
        });

        Ok(())
    }

    fn stop(&self) {
        if let Some(tx) = self
            .shutdown_tx
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
        {
            let _ = tx.send(());
        }
        self.socks_port.store(0, Ordering::SeqCst);
        self.running.store(false, Ordering::SeqCst);
    }
}

// ---------------------------------------------------------------------------
// Tor bootstrap + SOCKS5 relay loop
// ---------------------------------------------------------------------------

async fn run_tor_relay(data_dir: PathBuf, shutdown_rx: tokio::sync::oneshot::Receiver<()>) {
    if let Err(e) = std::fs::create_dir_all(&data_dir) {
        eprintln!("[Tor] Cannot create data dir: {e}");
        return;
    }

    let mut builder =
        arti_client::config::TorClientConfigBuilder::from_directories(&data_dir, &data_dir);
    // Mobile networks can be slow: raise circuit and all stream timeouts.
    // Defaults are 10 s — too short for Android + exit nodes on clearnet.
    // resolve_timeout covers DNS lookup at the exit (clearnet only); if that
    // expires the client sees "timed out at exit" before TCP even starts.
    builder
        .circuit_timing()
        .request_timeout(std::time::Duration::from_secs(120));
    builder
        .stream_timeouts()
        .connect_timeout(std::time::Duration::from_secs(120));
    builder
        .stream_timeouts()
        .resolve_timeout(std::time::Duration::from_secs(60));
    let config = match builder.build() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[Tor] Config build failed: {e}");
            return;
        }
    };

    let client = match arti_client::TorClient::builder()
        .config(config)
        .create_unbootstrapped()
    {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[Tor] Client creation failed: {e}");
            return;
        }
    };

    // Track bootstrap progress in a parallel task so the UI can poll it.
    let mut events = client.bootstrap_events();
    tokio::spawn(async move {
        use futures::StreamExt;
        while let Some(status) = events.next().await {
            let frac = status.as_frac();
            let label = status.to_string();
            eprintln!("[Tor] Bootstrap {:.0}%: {label}", frac * 100.0);
            TOR_MANAGER.update_bootstrap(frac, label);
        }
    });

    if let Err(e) = client.bootstrap().await {
        eprintln!("[Tor] Bootstrap failed: {e}");
        TOR_MANAGER.update_bootstrap(0.0, format!("Bootstrap failed: {e}"));
        return;
    }

    let listener = match tokio::net::TcpListener::bind("127.0.0.1:0").await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[Tor] Failed to bind SOCKS5 listener: {e}");
            return;
        }
    };

    let port = match listener.local_addr() {
        Ok(addr) => addr.port(),
        Err(e) => {
            eprintln!("[Tor] Failed to get SOCKS5 listener address: {e}");
            return;
        }
    };
    TOR_MANAGER.socks_port.store(port, Ordering::SeqCst);
    TOR_MANAGER.running.store(true, Ordering::SeqCst);

    let mut shutdown_rx = shutdown_rx;

    loop {
        tokio::select! {
            _ = &mut shutdown_rx => break,
            result = listener.accept() => {
                let Ok((stream, _)) = result else { break };
                let tor_client = client.isolated_client();
                tokio::spawn(async move {
                    if let Err(e) = handle_socks5_connection(stream, tor_client).await {
                        eprintln!("[Tor] SOCKS5 error: {e}");
                    }
                });
            }
        }
    }

    TOR_MANAGER.running.store(false, Ordering::SeqCst);
    TOR_MANAGER.socks_port.store(0, Ordering::SeqCst);
}

/// Minimal SOCKS5 CONNECT relay: handshake → target address → Tor stream → bidirectional copy.
async fn handle_socks5_connection(
    mut stream: tokio::net::TcpStream,
    client: arti_client::TorClient<tor_rtcompat::PreferredRuntime>,
) -> Result<()> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    // --- Auth negotiation ---
    let mut buf2 = [0u8; 2];
    stream.read_exact(&mut buf2).await?;
    anyhow::ensure!(buf2[0] == 0x05, "Not a SOCKS5 client");
    let n = buf2[1] as usize;
    let mut methods = vec![0u8; n];
    stream.read_exact(&mut methods).await?;
    stream.write_all(&[0x05, 0x00]).await?; // accept: no auth

    // --- CONNECT request ---
    let mut req = [0u8; 4];
    stream.read_exact(&mut req).await?;
    anyhow::ensure!(req[1] == 0x01, "Only CONNECT command supported");

    let (host, port) = match req[3] {
        0x01 => {
            let mut addr = [0u8; 4];
            stream.read_exact(&mut addr).await?;
            let mut p = [0u8; 2];
            stream.read_exact(&mut p).await?;
            (
                std::net::IpAddr::V4(std::net::Ipv4Addr::from(addr)).to_string(),
                u16::from_be_bytes(p),
            )
        }
        0x03 => {
            let mut len = [0u8; 1];
            stream.read_exact(&mut len).await?;
            let mut domain = vec![0u8; len[0] as usize];
            stream.read_exact(&mut domain).await?;
            let mut p = [0u8; 2];
            stream.read_exact(&mut p).await?;
            (String::from_utf8(domain)?, u16::from_be_bytes(p))
        }
        0x04 => {
            let mut addr = [0u8; 16];
            stream.read_exact(&mut addr).await?;
            let mut p = [0u8; 2];
            stream.read_exact(&mut p).await?;
            (
                std::net::IpAddr::V6(std::net::Ipv6Addr::from(addr)).to_string(),
                u16::from_be_bytes(p),
            )
        }
        t => anyhow::bail!("Unsupported SOCKS5 address type: {t}"),
    };

    // --- Connect through Tor ---
    // Enable onion-service connections explicitly so .onion addresses work.
    let mut prefs = arti_client::StreamPrefs::new();
    prefs.connect_to_onion_services(arti_client::config::BoolOrAuto::Explicit(true));
    let tor_stream = match client
        .connect_with_prefs((host.as_str(), port), &prefs)
        .await
    {
        Ok(s) => s,
        Err(e) => {
            // 1. Store the real Tor error so create_raw_electrum_client can surface it.
            TOR_MANAGER.store_connection_error(e.to_string());
            // 2. Send a SOCKS5 "host unreachable" response so the client gets a
            //    proper protocol error instead of a raw EOF (fixes timing: store
            //    happens before socket close, so the error is always available
            //    by the time the caller catches the electrum_client error).
            let _ = stream
                .write_all(&[0x05, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
                .await;
            return Err(e.into());
        }
    };

    // --- Success response (BND.ADDR = 0.0.0.0:0) ---
    stream
        .write_all(&[0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        .await?;

    // --- Bidirectional relay ---
    let (mut tor_r, mut tor_w) = tokio::io::split(tor_stream);
    let (mut cl_r, mut cl_w) = tokio::io::split(stream);
    tokio::select! {
        _ = tokio::io::copy(&mut cl_r, &mut tor_w) => {}
        _ = tokio::io::copy(&mut tor_r, &mut cl_w) => {}
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Public API (called by api/tor.rs and wallet/mod.rs)
// ---------------------------------------------------------------------------

pub fn start_tor() -> Result<()> {
    TOR_MANAGER.start()
}

pub fn stop_tor() {
    TOR_MANAGER.stop()
}

pub fn is_tor_running() -> bool {
    TOR_MANAGER.is_running()
}

pub fn set_tor_data_dir(path: &str) {
    TOR_MANAGER.set_data_dir(path);
}

pub fn set_tor_enabled(enabled: bool) {
    TOR_ENABLED.store(enabled, Ordering::SeqCst);
}

pub fn is_tor_enabled() -> bool {
    TOR_ENABLED.load(Ordering::SeqCst)
}

pub fn tor_socks_addr() -> Option<String> {
    TOR_MANAGER.socks_addr()
}

pub fn take_tor_connection_error() -> Option<String> {
    TOR_MANAGER.take_connection_error()
}

/// Returns (fraction 0.0–1.0, human-readable status line).
pub fn tor_bootstrap_progress() -> (f32, String) {
    TOR_MANAGER.bootstrap_progress()
}
