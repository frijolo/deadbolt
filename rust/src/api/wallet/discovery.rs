use super::*;

// ───────────────────────────────────────────────────────────────────────────
// Account discovery
// ───────────────────────────────────────────────────────────────────────────

/// Scan a mnemonic's BIP44-family accounts and return those with on-chain activity.
///
/// Iterates accounts starting at index 0. Stops after `account_gap_limit`
/// consecutive accounts with no transactions and no balance. For each
/// account it checks the first `address_gap_limit` receive addresses (chain 0)
/// using Electrum batch queries.
///
/// Only singlesig wallet types are supported. Passing `P2WSH` or `P2SH_WSH`
/// returns an error.
#[allow(clippy::too_many_arguments)]
pub async fn discover_accounts(
    mnemonic: String,
    passphrase: Option<String>,
    wallet_type: crate::api::model::APIWalletType,
    network: crate::api::model::APINetwork,
    electrum_url: String,
    account_gap_limit: u32,
    address_gap_limit: u32,
    non_standard_paths: bool,
) -> Result<crate::api::model::APIDiscoveredAccounts> {
    use crate::api::model::{APIAccountInfo, APIDiscoveredAccounts, APIWalletType};
    use crate::core::seed::{mnemonic_to_root_xprv, root_xprv_to_mfp};
    use bdk_electrum::electrum_client::ElectrumApi;
    use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpub};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use bdk_wallet::bitcoin::{Address, CompressedPublicKey, Network};
    use std::str::FromStr;

    // Reject multisig types.
    match wallet_type {
        APIWalletType::P2WSH | APIWalletType::P2SH_WSH => {
            return Err(anyhow::anyhow!("Multisig account discovery not supported"));
        }
        _ => {}
    }

    let passphrase = passphrase.unwrap_or_default();
    let net: Network = network.into();
    let secp = Secp256k1::new();

    let root = mnemonic_to_root_xprv(&mnemonic, &passphrase, net)?;
    let mfp = root_xprv_to_mfp(&root, &secp);

    let client = super::create_raw_electrum_client(&electrum_url)?;

    let coin = match net {
        Network::Bitcoin => "0",
        _ => "1",
    };

    let standard_purpose = match wallet_type {
        APIWalletType::P2PKH => "44",
        APIWalletType::P2WPKH => "84",
        APIWalletType::P2SH | APIWalletType::P2SH_WPKH => "49",
        APIWalletType::P2TR => "86",
        // already rejected above
        _ => {
            return Err(anyhow::anyhow!(
                "Unsupported wallet type for account discovery"
            ))
        }
    };

    // non_standard_paths covers wallets created with a purpose that does not
    // match the script type (e.g. Taproot keys stored under purpose 44).
    let purposes: Vec<&str> = if non_standard_paths {
        vec!["44", "49", "84", "86"]
    } else {
        vec![standard_purpose]
    };

    let mut all_accounts: Vec<APIAccountInfo> = Vec::new();
    let mut total_scanned: u32 = 0;

    for purpose in purposes {
        let mut consecutive_empty: u32 = 0;
        let mut account_index: u32 = 0;

        loop {
            if consecutive_empty >= account_gap_limit {
                break;
            }

            let path_str = format!("m/{purpose}'/{coin}'/{account_index}'");
            let path = DerivationPath::from_str(&path_str)
                .map_err(|e| anyhow::anyhow!("Invalid path '{}': {}", path_str, e))?;

            let account_xprv = root
                .derive_priv(&secp, &path)
                .map_err(|e| anyhow::anyhow!("Derivation failed: {}", e))?;
            let account_xpub = Xpub::from_priv(&secp, &account_xprv);

            let mut scripts: Vec<_> = Vec::new();
            for child_index in 0..address_gap_limit {
                for role in 0u32..=1 {
                    let path_str = format!("m/{role}/{child_index}");
                    let child_path = DerivationPath::from_str(&path_str)
                        .map_err(|e| anyhow::anyhow!("invalid child path '{path_str}': {e}"))?;
                    let child_xpub = account_xpub
                        .derive_pub(&secp, &child_path)
                        .map_err(|e| anyhow::anyhow!("child key derivation failed: {e}"))?;
                    let compressed = CompressedPublicKey(child_xpub.public_key);
                    let script = match wallet_type {
                        APIWalletType::P2PKH => {
                            use bdk_wallet::bitcoin::PublicKey;
                            Address::p2pkh(PublicKey::new(child_xpub.public_key), net)
                                .script_pubkey()
                        }
                        APIWalletType::P2WPKH => Address::p2wpkh(&compressed, net).script_pubkey(),
                        APIWalletType::P2SH | APIWalletType::P2SH_WPKH => {
                            Address::p2shwpkh(&compressed, net).script_pubkey()
                        }
                        APIWalletType::P2TR => {
                            use bdk_wallet::bitcoin::key::UntweakedPublicKey;
                            let internal = UntweakedPublicKey::from(child_xpub.public_key);
                            Address::p2tr(&secp, internal, None, net).script_pubkey()
                        }
                        _ => {
                            return Err(anyhow::anyhow!(
                                "unsupported wallet type for account discovery"
                            ))
                        }
                    };
                    scripts.push(script);
                }
            }

            let script_refs: Vec<&bdk_wallet::bitcoin::Script> =
                scripts.iter().map(|s| s.as_script()).collect();

            let histories = client
                .batch_script_get_history(script_refs.iter().copied())
                .unwrap_or_default();

            let tx_count: u32 = histories.iter().map(|h| h.len() as u32).sum();

            let balance_sat: u64 = if tx_count > 0 {
                client
                    .batch_script_get_balance(script_refs.iter().copied())
                    .unwrap_or_default()
                    .iter()
                    .map(|b| b.confirmed + b.unconfirmed.max(0) as u64)
                    .sum()
            } else {
                0
            };

            if tx_count > 0 || balance_sat > 0 {
                let display_path = path_str.trim_start_matches("m/").to_string();
                let keyspec = format!("[{mfp}/{display_path}]{account_xpub}");
                let first_address = Address::from_script(scripts[0].as_script(), net)
                    .map(|a| a.to_string())
                    .unwrap_or_default();
                all_accounts.push(APIAccountInfo {
                    account_index,
                    derivation_path: display_path,
                    keyspec,
                    wallet_type,
                    first_address,
                    tx_count,
                    balance_sat,
                });
                consecutive_empty = 0;
            } else {
                consecutive_empty += 1;
            }

            account_index += 1;
        }

        total_scanned += account_index;
    }

    Ok(APIDiscoveredAccounts {
        accounts: all_accounts,
        scanned_count: total_scanned,
    })
}

/// Derives account-level xpubs for all standard derivation paths without any
/// on-chain queries.  Used to search Nostr for descriptor backups independently
/// of whether any funds are present.
///
/// Covers:
/// - BIP44-style single-sig (depth 3): purposes 44 / 49 / 84 / 86 × 0..account_count
/// - BIP48 multisig (depth 4): purpose 48 × 0..account_count × script_types 1 / 2 / 3 / 4 / 9
///   (script_type 1 = P2SH-P2WSH, 2 = P2WSH native, 3 = P2TR / Tapscript,
///   4 = P2WSH-P2SH nested, 9 = Miniscript / Liana)
pub fn derive_xpubs_for_nostr(
    mnemonic: String,
    passphrase: Option<String>,
    network: crate::api::model::APINetwork,
    account_count: u32,
) -> Result<Vec<String>> {
    use crate::core::seed::mnemonic_to_root_xprv;
    use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpub};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use bdk_wallet::bitcoin::Network;
    use std::str::FromStr;

    let passphrase = passphrase.unwrap_or_default();
    let net: Network = network.into();
    let secp = Secp256k1::new();
    let root = mnemonic_to_root_xprv(&mnemonic, &passphrase, net)?;

    let coin = match net {
        Network::Bitcoin => "0",
        _ => "1",
    };

    let mut xpubs: Vec<String> = Vec::new();

    // BIP44-style single-sig: m/{purpose}'/{coin}'/{account}'
    for purpose in ["44", "49", "84", "86"] {
        for account_index in 0..account_count {
            let path_str = format!("m/{purpose}'/{coin}'/{account_index}'");
            let path = DerivationPath::from_str(&path_str)
                .map_err(|e| anyhow::anyhow!("Invalid path '{}': {}", path_str, e))?;
            let account_xprv = root
                .derive_priv(&secp, &path)
                .map_err(|e| anyhow::anyhow!("Derivation failed: {}", e))?;
            xpubs.push(Xpub::from_priv(&secp, &account_xprv).to_string());
        }
    }

    // BIP48 multisig: m/48'/{coin}'/{account}'/{script_type}'
    // script_type: 1 = P2SH-P2WSH, 2 = P2WSH (native), 3 = P2TR / Tapscript
    //           4 = P2WSH-P2SH (nested segwit), 9 = Miniscript / Liana
    for account_index in 0..account_count {
        for script_type in ["1", "2", "3", "4", "9"] {
            let path_str = format!("m/48'/{coin}'/{account_index}'/{script_type}'");
            let path = DerivationPath::from_str(&path_str)
                .map_err(|e| anyhow::anyhow!("Invalid path '{}': {}", path_str, e))?;
            let account_xprv = root
                .derive_priv(&secp, &path)
                .map_err(|e| anyhow::anyhow!("Derivation failed: {}", e))?;
            xpubs.push(Xpub::from_priv(&secp, &account_xprv).to_string());
        }
    }

    Ok(xpubs)
}

/// Returns the first external receive address (index 0) for a stored wallet
/// descriptor. Used to match discovered accounts against wallets already on
/// the device without relying on fragile descriptor string comparisons.
pub fn first_address_from_descriptor(
    descriptor: String,
    network: crate::api::model::APINetwork,
) -> Result<String> {
    use bdk_wallet::{KeychainKind, Wallet};

    // Hint may disagree with descriptor (e.g. mainnet descriptor on testnet UI).
    let detected = crate::core::descriptor::DescriptorAnalyzer::analyze(&descriptor)
        .ok()
        .map(|a| a.network());
    let net: bdk_wallet::bitcoin::Network = detected.unwrap_or_else(|| network.into());

    let wallet = Wallet::create_from_two_path_descriptor(descriptor)
        .network(net)
        .create_wallet_no_persist()?;
    Ok(wallet
        .peek_address(KeychainKind::External, 0)
        .address
        .to_string())
}

/// Returns the wallet type derived from a descriptor.
/// This parses the descriptor to determine if it's P2PKH, P2WPKH, P2SH, P2WSH, or P2TR.
pub fn wallet_type_from_descriptor(descriptor: &str) -> crate::api::model::APIWalletType {
    use crate::api::model::APIWalletType;
    let descriptor_lower = descriptor.to_lowercase();

    // Check for Taproot (P2TR) - contains "tr("
    if descriptor_lower.contains("tr(") {
        return APIWalletType::P2TR;
    }
    // Check for P2WSH - contains "wpkh(" inside wsh()
    if descriptor_lower.contains("wsh(") && descriptor_lower.contains("wpkh(") {
        return APIWalletType::P2WSH;
    }
    // Check for P2SH-WPKH - contains "wpkh(" inside sh()
    if descriptor_lower.contains("sh(") && descriptor_lower.contains("wpkh(") {
        return APIWalletType::P2SH_WPKH;
    }
    // Check for P2SH-P2WSH (nested segwit) - contains "wpkh(" or "wsh(" inside sh()
    if descriptor_lower.contains("sh(") && descriptor_lower.contains("wsh(") {
        return APIWalletType::P2SH_WSH;
    }
    // Check for P2WPKH - contains "wpkh(" directly
    if descriptor_lower.contains("wpkh(") {
        return APIWalletType::P2WPKH;
    }
    // Check for P2PKH - contains "pkh(" directly
    if descriptor_lower.contains("pkh(") {
        return APIWalletType::P2PKH;
    }
    // Check for P2SH - contains "sh(" directly
    if descriptor_lower.contains("sh(") {
        return APIWalletType::P2SH;
    }

    APIWalletType::Unknown
}

// ───────────────────────────────────────────────────────────────────────────
// Hardware-wallet account discovery
// ───────────────────────────────────────────────────────────────────────────

/// Wallet-type + BIP-32 paths to request from a connected hardware wallet.
pub struct APIWalletTypePaths {
    pub wallet_type: crate::api::model::APIWalletType,
    /// Paths to pass to `hw_get_xpub`, e.g. `["m/84'/0'/0'", "m/84'/0'/1'", …]`.
    pub paths: Vec<String>,
}

/// Wallet-type + account-level keyspecs already fetched from a hardware wallet.
pub struct APIWalletTypeKeyspecs {
    pub wallet_type: crate::api::model::APIWalletType,
    /// `"[mfp/84'/0'/0']xpub…"` strings — one per account index, in order.
    pub keyspecs: Vec<String>,
}

/// Returns every BIP-32 derivation path needed for hardware-wallet-based
/// account discovery, grouped by wallet type.
///
/// The caller iterates over the returned list and calls `hw_get_xpub` for
/// every path (no screen confirmation required for xpub export).  The resulting
/// keyspecs are passed to `discover_accounts_from_keyspecs` for on-chain
/// scanning, and the bare xpubs are used for Nostr backup lookups.
///
/// Covers:
/// - Singlesig BIP44-style: purposes 44 / 49 / 84 / 86
/// - Multisig BIP48: script types 1 (P2SH-P2WSH) and 2 (P2WSH native)
///
/// `account_gap_limit` accounts are generated per wallet type (use the same
/// value that will later be passed to the on-chain scanner; default 20).
///
/// When `skip_legacy` is `true`, the purpose-44 (P2PKH / legacy) paths are
/// omitted.  The BitBox02 treats these as unusual and prompts for explicit
/// device confirmation on every xpub export, so skipping them avoids
/// unnecessary taps for users who have never used legacy addresses.
pub fn hw_derivation_paths_for_discovery(
    account_gap_limit: u32,
    network: crate::api::model::APINetwork,
    skip_legacy: bool,
) -> Vec<APIWalletTypePaths> {
    use crate::api::model::APIWalletType;
    use bdk_wallet::bitcoin::Network;

    let net: Network = network.into();
    let coin = match net {
        Network::Bitcoin => "0",
        _ => "1",
    };

    let mut result: Vec<APIWalletTypePaths> = Vec::new();

    for (purpose, wallet_type) in [
        ("44", APIWalletType::P2PKH),
        ("49", APIWalletType::P2SH_WPKH),
        ("84", APIWalletType::P2WPKH),
        ("86", APIWalletType::P2TR),
    ] {
        if skip_legacy && purpose == "44" {
            continue;
        }
        let paths: Vec<String> = (0..account_gap_limit)
            .map(|i| format!("m/{purpose}'/{coin}'/{i}'"))
            .collect();
        result.push(APIWalletTypePaths { wallet_type, paths });
    }

    // BIP48 multisig paths — used for Nostr lookup only (on-chain scan skipped).
    for (script_type, wallet_type) in [("1", APIWalletType::P2SH_WSH), ("2", APIWalletType::P2WSH)]
    {
        let paths: Vec<String> = (0..account_gap_limit)
            .map(|i| format!("m/48'/{coin}'/{i}'/{script_type}'"))
            .collect();
        result.push(APIWalletTypePaths { wallet_type, paths });
    }

    result
}

/// Discover on-chain accounts using keyspecs already fetched from a hardware
/// wallet, without access to the mnemonic.
///
/// Each entry in `keyspecs_by_type` maps a wallet type to a list of
/// `"[mfp/path]xpub…"` strings (one per account index starting at 0).
///
/// Multisig types (`P2WSH`, `P2SH_WSH`) are silently skipped — on-chain
/// address derivation requires all co-signer xpubs, which are unknown here.
/// Use Nostr backup lookups to recover multisig wallets.
///
/// Returns the same `APIDiscoveredAccounts` type as `discover_accounts`, so
/// the Flutter result screen can be shared.
pub async fn discover_accounts_from_keyspecs(
    keyspecs_by_type: Vec<APIWalletTypeKeyspecs>,
    network: crate::api::model::APINetwork,
    electrum_url: String,
    address_gap_limit: u32,
) -> Result<crate::api::model::APIDiscoveredAccounts> {
    use crate::api::model::{APIAccountInfo, APIDiscoveredAccounts, APIWalletType};
    use bdk_electrum::electrum_client::ElectrumApi;
    use bdk_wallet::bitcoin::bip32::{DerivationPath, Xpub};
    use bdk_wallet::bitcoin::secp256k1::Secp256k1;
    use bdk_wallet::bitcoin::{Address, CompressedPublicKey, Network};
    use std::str::FromStr;

    let net: Network = network.into();
    let secp = Secp256k1::new();
    let client = super::create_raw_electrum_client(&electrum_url)?;

    let mut all_accounts: Vec<APIAccountInfo> = Vec::new();
    let mut total_scanned: u32 = 0;

    for type_entry in keyspecs_by_type {
        let wallet_type = type_entry.wallet_type;

        // Skip multisig — cannot derive addresses from a single account xpub.
        match wallet_type {
            APIWalletType::P2WSH | APIWalletType::P2SH_WSH => continue,
            _ => {}
        }

        for (account_index, keyspec) in type_entry.keyspecs.iter().enumerate() {
            total_scanned += 1;

            let (_mfp, path, xpub_str) = split_keyspec(keyspec)?;
            let account_xpub = Xpub::from_str(&xpub_str)
                .map_err(|e| anyhow::anyhow!("Invalid xpub in keyspec '{}': {}", keyspec, e))?;

            let mut scripts: Vec<bdk_wallet::bitcoin::ScriptBuf> = Vec::new();
            for child_index in 0..address_gap_limit {
                for role in 0u32..=1 {
                    let child_path = DerivationPath::from_str(&format!("m/{role}/{child_index}"))
                        .map_err(|e| anyhow::anyhow!("invalid child path: {e}"))?;
                    let child_xpub = account_xpub
                        .derive_pub(&secp, &child_path)
                        .map_err(|e| anyhow::anyhow!("child key derivation failed: {e}"))?;
                    let compressed = CompressedPublicKey(child_xpub.public_key);
                    let script = match wallet_type {
                        APIWalletType::P2PKH => {
                            use bdk_wallet::bitcoin::PublicKey;
                            Address::p2pkh(PublicKey::new(child_xpub.public_key), net)
                                .script_pubkey()
                        }
                        APIWalletType::P2WPKH => Address::p2wpkh(&compressed, net).script_pubkey(),
                        APIWalletType::P2SH | APIWalletType::P2SH_WPKH => {
                            Address::p2shwpkh(&compressed, net).script_pubkey()
                        }
                        APIWalletType::P2TR => {
                            use bdk_wallet::bitcoin::key::UntweakedPublicKey;
                            let internal = UntweakedPublicKey::from(child_xpub.public_key);
                            Address::p2tr(&secp, internal, None, net).script_pubkey()
                        }
                        _ => {
                            return Err(anyhow::anyhow!(
                                "unsupported wallet type for account discovery"
                            ))
                        }
                    };
                    scripts.push(script);
                }
            }

            let script_refs: Vec<&bdk_wallet::bitcoin::Script> =
                scripts.iter().map(|s| s.as_script()).collect();

            let histories = client
                .batch_script_get_history(script_refs.iter().copied())
                .unwrap_or_default();

            let tx_count: u32 = histories.iter().map(|h| h.len() as u32).sum();

            let balance_sat: u64 = if tx_count > 0 {
                client
                    .batch_script_get_balance(script_refs.iter().copied())
                    .unwrap_or_default()
                    .iter()
                    .map(|b| b.confirmed + b.unconfirmed.max(0) as u64)
                    .sum()
            } else {
                0
            };

            if tx_count > 0 || balance_sat > 0 {
                let first_address = Address::from_script(scripts[0].as_script(), net)
                    .map(|a| a.to_string())
                    .unwrap_or_default();
                all_accounts.push(APIAccountInfo {
                    account_index: account_index as u32,
                    derivation_path: path.clone(),
                    keyspec: keyspec.clone(),
                    wallet_type,
                    first_address,
                    tx_count,
                    balance_sat,
                });
            }
        }
    }

    Ok(APIDiscoveredAccounts {
        accounts: all_accounts,
        scanned_count: total_scanned,
    })
}

/// Split a keyspec `"[mfp/path]xpub"` into `(mfp, derivation_path, xpub_str)`.
/// For a bare `"xpub…"` string, mfp and derivation_path are empty strings.
fn split_keyspec(keyspec: &str) -> anyhow::Result<(String, String, String)> {
    if let Some(rest) = keyspec.strip_prefix('[') {
        let close = rest
            .find(']')
            .ok_or_else(|| anyhow::anyhow!("Malformed keyspec (missing ']'): '{}'", keyspec))?;
        let inner = &rest[..close]; // "mfp/path"
        let xpub_str = rest[close + 1..].to_string();
        if let Some(slash) = inner.find('/') {
            Ok((
                inner[..slash].to_string(),
                inner[slash + 1..].to_string(),
                xpub_str,
            ))
        } else {
            Ok((inner.to_string(), String::new(), xpub_str))
        }
    } else {
        Ok((String::new(), String::new(), keyspec.to_string()))
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Descriptor on-chain scan
// ───────────────────────────────────────────────────────────────────────────

/// On-chain balance and transaction summary for a single descriptor.
pub struct APIDescriptorScanResult {
    pub tx_count: u32,
    pub balance_sat: u64,
}

/// Scan a wallet descriptor against an Electrum server and return the total
/// transaction count and confirmed+unconfirmed balance for the first
/// `address_gap_limit` addresses across both external (receive) and internal
/// (change) keychains.
///
/// This works for any descriptor type — singlesig or multisig — and is used
/// to enrich Nostr-found backups with on-chain data without a full BDK sync.
pub async fn scan_descriptor(
    descriptor: String,
    network: crate::api::model::APINetwork,
    electrum_url: String,
    address_gap_limit: u32,
) -> Result<APIDescriptorScanResult> {
    use bdk_electrum::electrum_client::ElectrumApi;
    use bdk_wallet::{KeychainKind, Wallet};

    let net: bdk_wallet::bitcoin::Network = network.into();
    let wallet = Wallet::create_from_two_path_descriptor(descriptor)
        .network(net)
        .create_wallet_no_persist()
        .map_err(|e| anyhow::anyhow!("Invalid descriptor: {e}"))?;

    // Collect scripts from both external (receive) and internal (change) keychains.
    let mut scripts: Vec<_> = (0..address_gap_limit)
        .map(|i| {
            wallet
                .peek_address(KeychainKind::External, i)
                .address
                .script_pubkey()
        })
        .collect();

    for i in 0..address_gap_limit {
        scripts.push(
            wallet
                .peek_address(KeychainKind::Internal, i)
                .address
                .script_pubkey(),
        );
    }

    let client = super::create_raw_electrum_client(&electrum_url)?;
    let script_refs: Vec<&bdk_wallet::bitcoin::Script> =
        scripts.iter().map(|s| s.as_script()).collect();

    let histories = client
        .batch_script_get_history(script_refs.iter().copied())
        .unwrap_or_default();

    let tx_count: u32 = histories.iter().map(|h| h.len() as u32).sum();

    let balance_sat: u64 = if tx_count > 0 {
        client
            .batch_script_get_balance(script_refs.iter().copied())
            .unwrap_or_default()
            .iter()
            .map(|b| b.confirmed + b.unconfirmed.max(0) as u64)
            .sum()
    } else {
        0
    };

    Ok(APIDescriptorScanResult {
        tx_count,
        balance_sat,
    })
}

/// SHA-256 hex digest of an arbitrary UTF-8 string. Exposed as a sync FRB call so
/// that Dart can hash Bitcoin addresses without pulling in a Dart crypto dependency.
#[flutter_rust_bridge::frb(sync)]
pub fn sha256_hex(input: String) -> String {
    use sha2::{Digest, Sha256};
    hex::encode(Sha256::digest(input.as_bytes()))
}

#[cfg(test)]
#[path = "discovery_tests.rs"]
mod tests;
