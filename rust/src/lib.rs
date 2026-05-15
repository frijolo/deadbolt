pub mod api;
pub mod core;
mod frb_generated;

/// Shared test fixtures for wallet tests.
///
/// Exposed as `#[cfg(test)]` so it's only compiled during testing.
/// Test files import via `crate::test_support::{MAINNET_DESC, KEY_HEX, ...}`.
#[cfg(test)]
pub mod test_support;
