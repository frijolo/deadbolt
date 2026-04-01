use flutter_rust_bridge::frb;

/// Start Tor in the background. Returns immediately; use [isTorRunning] to
/// poll bootstrap completion.
#[frb(sync)]
pub fn start_tor() -> Result<(), String> {
    crate::core::tor_manager::start_tor().map_err(|e| e.to_string())
}

/// Stop Tor and close all circuits.
#[frb(sync)]
pub fn stop_tor() {
    crate::core::tor_manager::stop_tor();
}

/// True once Tor has fully bootstrapped and the local SOCKS5 listener is ready.
#[frb(sync)]
pub fn is_tor_running() -> bool {
    crate::core::tor_manager::is_tor_running()
}

/// Persist the enabled flag in Rust so wallet operations can enforce it.
/// Call before [startTor] / [stopTor].
#[frb(sync)]
pub fn set_tor_enabled(enabled: bool) {
    crate::core::tor_manager::set_tor_enabled(enabled);
}

/// True if the user has enabled Tor (may be true while still bootstrapping).
#[frb(sync)]
pub fn is_tor_enabled() -> bool {
    crate::core::tor_manager::is_tor_enabled()
}

/// Set the directory used for Tor state / cache (call before [startTor]).
/// Pass the app's persistent support directory so guard info survives restarts.
#[frb(sync)]
pub fn set_tor_data_dir(path: String) {
    crate::core::tor_manager::set_tor_data_dir(&path);
}

/// Bootstrap progress: fraction 0.0–1.0 and a human-readable status line.
/// Poll this while [isTorRunning] is false to show detailed progress to the user.
#[frb(sync)]
pub fn tor_bootstrap_progress() -> (f32, String) {
    crate::core::tor_manager::tor_bootstrap_progress()
}

/// Returns the local SOCKS5 address (e.g. "127.0.0.1:51234") when Tor is
/// running and the listener is ready, or None otherwise.
#[frb(sync)]
pub fn tor_socks_addr() -> Option<String> {
    crate::core::tor_manager::tor_socks_addr()
}
