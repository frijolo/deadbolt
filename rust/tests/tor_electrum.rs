/// Integration test: Tor bootstrap + Electrum connectivity through onion service.
///
/// Run with:
///   ELECTRUM_ONION_URL=tcp://... cargo test tor_onion -- --nocapture --ignored
///
/// The URL is intentionally read from the environment so it never appears in git.
use bdk_electrum::electrum_client::{Client, ConfigBuilder, ElectrumApi, Socks5Config};
use rust_lib_deadbolt::core::tor_manager;

#[test]
#[ignore]
fn tor_onion_electrum_ping() {
    let url = std::env::var("ELECTRUM_ONION_URL")
        .expect("Set ELECTRUM_ONION_URL=tcp://<onion>:<port> before running");

    // Set a temp data dir so the test doesn't pollute the app state.
    let data_dir = std::env::temp_dir().join("deadbolt_tor_test");
    tor_manager::set_tor_data_dir(data_dir.to_str().unwrap());

    println!("Starting Tor bootstrap...");
    tor_manager::start_tor().expect("start_tor failed");

    // Wait up to 120 s for bootstrap.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(120);
    loop {
        if tor_manager::is_tor_running() {
            break;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "Tor bootstrap timed out after 120 s"
        );
        std::thread::sleep(std::time::Duration::from_secs(2));
        print!(".");
    }

    let socks_addr = tor_manager::tor_socks_addr().expect("SOCKS5 addr missing after bootstrap");
    println!("\nTor ready — SOCKS5 at {socks_addr}");
    println!("Connecting to {url} via Tor...");

    let config = ConfigBuilder::new()
        .socks5(Some(Socks5Config::new(&socks_addr)))
        .build();

    let client =
        Client::from_config(&url, config).expect("Failed to create electrum_client::Client");

    let features = client
        .server_features()
        .expect("server_features() failed — server unreachable or not an Electrum server");

    println!("server_features: {features:?}");

    // Also verify a ping roundtrip.
    client.ping().expect("ping() failed");
    println!("ping OK");
}
