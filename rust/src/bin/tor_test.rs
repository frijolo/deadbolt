//! Standalone Tor + Electrum diagnostic binary.
//!
//! Usage:
//!   tor_test [URL]          (default: ssl://mempool.space:60602)
//!
//! Output is written to stdout AND to tor_test.log in the current directory.
//! On Android: push binary, run it, then pull tor_test.log.
//!   adb push tor_test /data/local/tmp/
//!   adb shell "chmod +x /data/local/tmp/tor_test && /data/local/tmp/tor_test > /data/local/tmp/tor_test.log 2>&1"
//!   adb pull /data/local/tmp/tor_test.log

use std::fs::File;
use std::io::Write;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use bdk_electrum::electrum_client::{Client, ConfigBuilder, ElectrumApi, Socks5Config};

use rust_lib_deadbolt::core::tor_manager;

/// Log to both stdout and the shared log file with a timestamp prefix.
fn log(file: &Arc<Mutex<File>>, msg: &str) {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let line = format!("[{ts}] {msg}");
    println!("{line}");
    if let Ok(mut f) = file.lock() {
        let _ = writeln!(f, "{line}");
        let _ = f.flush();
    }
}

fn main() {
    // Open log file early so every line lands there.
    let log_path = "tor_test.log";
    let file = match File::create(log_path) {
        Ok(f) => Arc::new(Mutex::new(f)),
        Err(e) => {
            eprintln!("WARNING: cannot create {log_path}: {e}");
            // Continue without file logging.
            Arc::new(Mutex::new(
                File::create(std::env::temp_dir().join("tor_test.log"))
                    .expect("failed to create fallback log file"),
            ))
        }
    };

    let url = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "ssl://mempool.space:60602".to_string());

    log(&file, "=== Deadbolt Tor diagnostic ===");
    log(&file, &format!("Target URL : {url}"));
    log(&file, &format!("OS         : {}", std::env::consts::OS));
    log(&file, &format!("Arch       : {}", std::env::consts::ARCH));
    log(&file, &format!("Log file   : {log_path}"));
    log(&file, "");

    // ---- Tor data directory ----
    let data_dir = std::env::temp_dir().join("deadbolt_tor_diagnostic");
    log(&file, &format!("Tor data dir: {}", data_dir.display()));
    tor_manager::set_tor_data_dir(data_dir.to_str().unwrap());
    tor_manager::set_tor_enabled(true);

    // ---- Start Tor ----
    log(
        &file,
        "Starting Tor (returns immediately, bootstrap in background)...",
    );
    let t0 = Instant::now();
    if let Err(e) = tor_manager::start_tor() {
        let msg = format!("FATAL: start_tor() failed: {e}");
        log(&file, &msg);
        std::process::exit(1);
    }
    log(&file, "start_tor() returned OK — waiting for bootstrap...");

    // ---- Poll bootstrap ----
    let timeout = Duration::from_secs(300);
    loop {
        let elapsed = t0.elapsed();

        if tor_manager::is_tor_running() {
            log(
                &file,
                &format!("Bootstrap complete after {:.1}s", elapsed.as_secs_f32()),
            );
            break;
        }

        if elapsed > timeout {
            let (frac, status) = tor_manager::tor_bootstrap_progress();
            log(
                &file,
                &format!(
                    "FATAL: timed out after 180 s. Progress: {:.0}% — {status}",
                    frac * 100.0
                ),
            );
            std::process::exit(1);
        }

        let (frac, status) = tor_manager::tor_bootstrap_progress();
        log(
            &file,
            &format!(
                "Bootstrap {:.0}% ({:.0}s elapsed): {}",
                frac * 100.0,
                elapsed.as_secs_f32(),
                if status.is_empty() {
                    "waiting..."
                } else {
                    &status
                }
            ),
        );
        std::thread::sleep(Duration::from_secs(3));
    }

    // ---- SOCKS5 address ----
    let socks_addr = match tor_manager::tor_socks_addr() {
        Some(a) => a,
        None => {
            log(&file, "FATAL: is_tor_running() true but socks_addr is None");
            std::process::exit(1);
        }
    };
    log(&file, &format!("SOCKS5 proxy: {socks_addr}"));
    log(&file, "");

    // ---- Create Electrum client ----
    log(&file, &format!("Connecting to {url} via Tor SOCKS5..."));
    let t1 = Instant::now();

    let config = ConfigBuilder::new()
        .socks5(Some(Socks5Config::new(&socks_addr)))
        .build();

    let client = match Client::from_config(&url, config) {
        Ok(c) => {
            log(
                &file,
                &format!("Client connected in {:.1}s", t1.elapsed().as_secs_f32()),
            );
            c
        }
        Err(e) => {
            let tor_err = tor_manager::take_tor_connection_error();
            log(&file, &format!("ERROR creating client: {e}"));
            if let Some(tor_msg) = tor_err {
                log(&file, &format!("Tor detail: {tor_msg}"));
            }
            std::process::exit(1);
        }
    };

    // ---- server_features ----
    log(&file, "Calling server_features()...");
    let t2 = Instant::now();
    match client.server_features() {
        Ok(f) => {
            log(
                &file,
                &format!("server_features() OK in {:.1}s", t2.elapsed().as_secs_f32()),
            );
            log(&file, &format!("  server_version : {:?}", f.server_version));
            log(&file, &format!("  protocol_min   : {}", f.protocol_min));
            log(&file, &format!("  protocol_max   : {}", f.protocol_max));
            log(
                &file,
                &format!("  genesis_hash   : {}", hex::encode(f.genesis_hash)),
            );
        }
        Err(e) => {
            let tor_err = tor_manager::take_tor_connection_error();
            log(&file, &format!("ERROR server_features: {e}"));
            if let Some(tor_msg) = tor_err {
                log(&file, &format!("Tor detail: {tor_msg}"));
            }
        }
    }

    // ---- ping ----
    log(&file, "Calling ping()...");
    let t3 = Instant::now();
    match client.ping() {
        Ok(_) => log(
            &file,
            &format!("ping() OK in {:.1}s", t3.elapsed().as_secs_f32()),
        ),
        Err(e) => {
            let tor_err = tor_manager::take_tor_connection_error();
            log(&file, &format!("ERROR ping: {e}"));
            if let Some(tor_msg) = tor_err {
                log(&file, &format!("Tor detail: {tor_msg}"));
            }
        }
    }

    log(&file, "");
    log(
        &file,
        &format!("=== Total elapsed: {:.1}s ===", t0.elapsed().as_secs_f32()),
    );
}
