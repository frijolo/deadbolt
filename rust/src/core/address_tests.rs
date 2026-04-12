use super::*;

#[test]
fn test_p2pkh_mainnet() {
    // P2PKH address, script len 25 → WU = 4*(8+1+25) = 136
    let wu = address_output_wu("1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs").unwrap();
    assert_eq!(wu, 136);
}

#[test]
fn test_p2sh_mainnet() {
    // P2SH address, script len 23 → WU = 4*(8+1+23) = 128
    let wu = address_output_wu("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy").unwrap();
    assert_eq!(wu, 128);
}

#[test]
fn test_p2wpkh_mainnet() {
    // Native P2WPKH (bc1q...), script len 22 → WU = 4*(8+1+22) = 124
    let wu = address_output_wu("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4").unwrap();
    assert_eq!(wu, 124);
}

#[test]
fn test_p2wsh_mainnet() {
    // Native P2WSH (bc1q... 62 chars), script len 34 → WU = 4*(8+1+34) = 172
    let wu = address_output_wu("bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3")
        .unwrap();
    assert_eq!(wu, 172);
}

#[test]
fn test_p2tr_mainnet() {
    // P2TR (bc1p...), script len 34 → WU = 4*(8+1+34) = 172
    let wu = address_output_wu("bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297")
        .unwrap();
    assert_eq!(wu, 172);
}

#[test]
fn test_testnet_address_accepted() {
    // Testnet P2WPKH — network validation is skipped, should succeed
    let wu = address_output_wu("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx").unwrap();
    assert_eq!(wu, 124);
}

#[test]
fn test_invalid_address_returns_error() {
    let result = address_output_wu("not_a_bitcoin_address");
    assert!(matches!(result, Err(WalletError::InvalidAddress(_))));
}
