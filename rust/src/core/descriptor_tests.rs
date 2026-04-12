use super::*;

#[test]
fn test_analyze_p2pkh_testnet() -> Result<()> {
    let descriptor = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";

    let analyzer = DescriptorAnalyzer::analyze(descriptor)?;

    assert_eq!(analyzer.network(), Network::Testnet);
    assert_eq!(analyzer.wallet_type(), WalletType::P2PKH);

    let keys = analyzer.public_keys()?;
    assert_eq!(keys.len(), 1);

    let spend_paths = analyzer.spend_paths()?;
    assert_eq!(spend_paths.len(), 1);
    assert_eq!(spend_paths[0].threshold, 1);

    Ok(())
}

#[test]
fn test_analyze_p2wpkh_testnet() -> Result<()> {
    let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)#uxw7vpfc";

    let analyzer = DescriptorAnalyzer::analyze(descriptor)?;

    assert_eq!(analyzer.network(), Network::Testnet);
    assert_eq!(analyzer.wallet_type(), WalletType::P2WPKH);

    let keys = analyzer.public_keys()?;
    assert_eq!(keys.len(), 1);

    let spend_paths = analyzer.spend_paths()?;
    assert_eq!(spend_paths.len(), 1);

    Ok(())
}

#[test]
fn test_analyze_p2wsh_multisig_mainnet() -> Result<()> {
    let descriptor = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";

    let analyzer = DescriptorAnalyzer::analyze(descriptor)?;

    assert_eq!(analyzer.network(), Network::Bitcoin);
    assert_eq!(analyzer.wallet_type(), WalletType::P2WSH);

    let keys = analyzer.public_keys()?;
    assert_eq!(keys.len(), 2);

    let spend_paths = analyzer.spend_paths()?;
    assert_eq!(spend_paths.len(), 1);
    assert_eq!(spend_paths[0].threshold, 2);

    Ok(())
}
