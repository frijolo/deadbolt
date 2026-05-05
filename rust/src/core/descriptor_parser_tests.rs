use super::*;

#[test]
fn test_parse_p2pkh_testnet() -> Result<()> {
    let descriptor = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";
    let parser = DescriptorParser::parse(descriptor)?;

    assert_eq!(parser.wallet_type(), WalletType::P2PKH);
    assert_eq!(parser.detect_network()?, Network::Testnet);
    Ok(())
}

#[test]
fn test_parse_p2wpkh_testnet() -> Result<()> {
    let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)#uxw7vpfc";
    let parser = DescriptorParser::parse(descriptor)?;

    assert_eq!(parser.wallet_type(), WalletType::P2WPKH);
    assert_eq!(parser.detect_network()?, Network::Testnet);
    Ok(())
}

#[test]
fn test_parse_p2wsh_multisig_mainnet() -> Result<()> {
    let descriptor = "wsh(sortedmulti(2,[c449c5c5/48h/0h/0h/2h]xpub6Dtni7dearhzvCuQ3aZYC5VkDEnpjJjoCSJRxs2m6D63r1KzvgvAvQKypzqFpSZ2uaYfNx8HSgi63jcK4ZFgFCTVph1MTMZxP55L1am1Csn/<0;1>/*,[c61af686/48h/0h/0h/2h]xpub6EDTxSWtzPTBiQtxScLWm1sJ6By9QPrG6J5RvA3ZuKYHP1mfvyeyTG2Gy3CgnQ2ps5p6cgGTvuULfxuqQtSAvkVp9VyASus6pMFoe8mztCj/<0;1>/*))#0wct5td0";
    let parser = DescriptorParser::parse(descriptor)?;

    assert_eq!(parser.wallet_type(), WalletType::P2WSH);
    assert_eq!(parser.detect_network()?, Network::Bitcoin);
    Ok(())
}

#[test]
fn test_parse_invalid_descriptor() {
    let descriptor = "invalid_descriptor";
    let result = DescriptorParser::parse(descriptor);

    assert!(result.is_err());
}

#[test]
fn test_canonical_descriptor_adds_checksum() -> Result<()> {
    // Descriptor without checksum — BDK adds checksum and normalizes h -> '
    let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)";
    let parser = DescriptorParser::parse(descriptor)?;

    let canonical = parser.canonical_descriptor_str();
    assert_eq!(canonical, "wpkh([089177d9/84'/1'/0']tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)#twnsqqr9");
    Ok(())
}

#[test]
fn test_canonical_descriptor_idempotent() -> Result<()> {
    let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)";
    let parser1 = DescriptorParser::parse(descriptor)?;
    let canonical1 = parser1.canonical_descriptor_str();

    let parser2 = DescriptorParser::parse(&canonical1)?;
    let canonical2 = parser2.canonical_descriptor_str();

    assert_eq!(canonical1, canonical2);
    Ok(())
}

#[test]
fn test_check_network_compatibility_match() -> Result<()> {
    let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)";
    let parser = DescriptorParser::parse(descriptor)?;
    parser.check_network_compatibility(Network::Signet)?;
    parser.check_network_compatibility(Network::Testnet)?;
    Ok(())
}

#[test]
fn test_check_network_compatibility_mismatch_reports_selected() -> Result<()> {
    let descriptor = "wpkh([089177d9/84h/1h/0h]tpubDChwdeVd7pBThLN5uKs5m83Eqv6ozCiLibqpswK3VtMFZcGv8L9ZUq6V56UYMzKfM4Bfsgy2b9HrFhRSoSKp1f3omLp17G74m4CzkUKsicG/<0;1>/*)";
    let parser = DescriptorParser::parse(descriptor)?;
    let err = parser
        .check_network_compatibility(Network::Bitcoin)
        .unwrap_err()
        .to_string();
    assert!(err.contains("testnet keys"), "got: {err}");
    assert!(err.contains("'mainnet' was selected"), "got: {err}");
    Ok(())
}
