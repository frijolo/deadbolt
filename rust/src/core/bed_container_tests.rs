use super::*;

// ── Armor tests ─────────────────────────────────────────────────────

#[test]
fn test_encode_decode_armored_roundtrip() {
    let raw: Vec<u8> = (0..=255).collect(); // all byte values
    let armored = encode_armored(&raw);

    assert!(armored.starts_with(ARMOR_BEGIN));
    assert!(armored.trim_end().ends_with(ARMOR_END));

    let decoded = decode_armored(&armored).expect("decode armored");
    assert_eq!(decoded, raw, "decoded bytes must match original");
}

#[test]
fn test_armor_line_wrapping() {
    let large_payload: Vec<u8> = vec![0xAB; 200];
    let armored = encode_armored(&large_payload);

    let lines: Vec<&str> = armored
        .lines()
        .filter(|l| !l.starts_with("-----") && !l.trim().is_empty())
        .collect();

    // Each base64 line must be <= 64 chars
    for line in lines {
        assert!(
            line.len() <= LINE_WIDTH,
            "armor line {} exceeds {} chars (len={})",
            line,
            LINE_WIDTH,
            line.len()
        );
    }

    // Decode and verify
    let decoded = decode_armored(&armored).expect("decode armored");
    assert_eq!(decoded, large_payload);
}

#[test]
fn test_armor_with_bom() {
    let raw = b"hello bed backup";
    let armored = encode_armored(raw);
    let with_bom = format!("\u{FEFF}{}", armored);

    let decoded = decode_armored(&with_bom).expect("decode armored with BOM");
    assert_eq!(decoded, raw);
}

#[test]
fn test_armor_wrong_header_fails() {
    let bad = "-----BEGIN WRONG HEADER-----\ndata\n-----END WRONG HEADER-----\n";
    assert!(matches!(
        decode_armored(bad),
        Err(ArmoredError::WrongHeader)
    ));
}

#[test]
fn test_armor_wrong_footer_fails() {
    let bad = format!("{}\ndata\n-----END WRONG FOOTER-----", ARMOR_BEGIN);
    assert!(matches!(
        decode_armored(&bad),
        Err(ArmoredError::WrongFooter)
    ));
}

#[test]
fn test_armor_no_payload_fails() {
    let empty = format!("{}\n-----END BITCOIN ENCRYPTED BACKUP-----", ARMOR_BEGIN);
    assert!(matches!(
        decode_armored(&empty),
        Err(ArmoredError::EmptyPayload)
    ));
}

#[test]
fn test_armor_invalid_base64_fails() {
    let bad = format!(
        "{}\n!!!invalid!!!\n-----END BITCOIN ENCRYPTED BACKUP-----",
        ARMOR_BEGIN
    );
    assert!(matches!(
        decode_armored(&bad),
        Err(ArmoredError::InvalidBase64)
    ));
}

// ── Sniffing tests ──────────────────────────────────────────────────

#[test]
fn test_sniff_binary() {
    let data = vec![0x42, 0x45, 0x42, 0x01, 0xDE, 0xAD, 0xBE, 0xEF];
    assert!(is_bed_binary(&data));
    assert_eq!(sniff_bed(&data), Ok(BedFormat::Binary));
}

#[test]
fn test_sniff_armored() {
    let data = b"-----BEGIN BITCOIN ENCRYPTED BACKUP-----\ndGVzdA==\n-----END BITCOIN ENCRYPTED BACKUP-----\n";
    assert!(!is_bed_binary(data));
    assert_eq!(sniff_bed(data), Ok(BedFormat::Armored));
}

#[test]
fn test_sniff_not_bed() {
    let not_bed = b"just some random text";
    assert!(!is_bed_binary(not_bed));
    assert!(matches!(sniff_bed(not_bed), Err(SniffError::NotBed)));
}

#[test]
fn test_sniff_too_short() {
    let short = b"BEB";
    assert!(!is_bed_binary(short));
    assert!(matches!(sniff_bed(short), Err(SniffError::NotBed)));
}

#[test]
fn test_sniff_bad_magic() {
    let bad_magic = b"XYZ\x01something";
    assert!(!is_bed_binary(bad_magic));
    assert!(matches!(sniff_bed(bad_magic), Err(SniffError::NotBed)));
}

// ── Integration with real BED bytes ─────────────────────────────────

#[test]
fn test_armor_real_bed_roundtrip() {
    // Use a real BED blob (first 16 bytes of the wallet.bed fixture)
    let header_bytes = b"BEB\x01\x01\x04\x80\x00\x00\x30\x80\x00\x00\x00\x80\x00";
    let armored = encode_armored(header_bytes);
    let decoded = decode_armored(&armored).expect("decode armored");
    assert_eq!(decoded, header_bytes);
}

#[test]
fn test_armor_empty_input() {
    let armored = encode_armored(&[]);
    assert!(armored.starts_with(ARMOR_BEGIN));
    assert!(armored.trim_end().ends_with(ARMOR_END));
    // Empty payload produces no base64 lines → decode returns EmptyPayload
    assert!(matches!(
        decode_armored(&armored),
        Err(ArmoredError::EmptyPayload)
    ));
}

#[test]
fn test_sniff_armor_with_whitespace() {
    // Armor with extra whitespace around headers
    let data = format!("  {}  \ndata\n\n  {}  ", ARMOR_BEGIN, ARMOR_END);
    assert_eq!(sniff_bed(data.as_bytes()), Ok(BedFormat::Armored));
}
