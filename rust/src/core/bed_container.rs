// ---------------------------------------------------------------------------
// BED (Bitcoin Encrypted Descriptor) container utilities
// ---------------------------------------------------------------------------
// Formats:
//   - Raw binary: 4-byte magic "BEB\x01" + encrypted payload
//   - ASCII armor: PEM-style wrapper (like GPG armored data)
//
// Sniffing detects both formats automatically.
// ---------------------------------------------------------------------------

use base64::{engine::general_purpose::STANDARD, Engine as _};
use std::fmt;

// ── Constants ───────────────────────────────────────────────────────────────

/// Magic bytes identifying a BED file.
pub const BED_MAGIC: &[u8; 4] = b"BEB\x01";

/// PEM header line.
pub const ARMOR_BEGIN: &str = "-----BEGIN BITCOIN ENCRYPTED BACKUP-----";

/// PEM footer line.
pub const ARMOR_END: &str = "-----END BITCOIN ENCRYPTED BACKUP-----";

/// Line width for base64 wrapping in armored format.
const LINE_WIDTH: usize = 64;

// ── Errors ──────────────────────────────────────────────────────────────────

/// Errors from decoding armored BED data.
#[derive(Debug)]
pub enum ArmoredError {
    /// Missing or incorrect BEGIN header.
    WrongHeader,
    /// Missing or incorrect END footer.
    WrongFooter,
    /// No payload lines found between headers.
    EmptyPayload,
    /// Invalid base64 in payload.
    InvalidBase64,
}

impl fmt::Display for ArmoredError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ArmoredError::WrongHeader => write!(f, "missing or wrong BEGIN header"),
            ArmoredError::WrongFooter => write!(f, "missing or wrong END footer"),
            ArmoredError::EmptyPayload => write!(f, "empty payload between headers"),
            ArmoredError::InvalidBase64 => write!(f, "invalid base64 payload"),
        }
    }
}

impl std::error::Error for ArmoredError {}

/// Errors from sniffing a BED file.
#[derive(Debug, PartialEq, Eq)]
pub enum SniffError {
    /// File too short to contain a magic header.
    TooShort,
    /// Binary data does not start with BED magic.
    BadMagic,
    /// Not a valid BED format (neither binary nor armored).
    NotBed,
}

impl fmt::Display for SniffError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SniffError::TooShort => write!(f, "file too short for BED magic"),
            SniffError::BadMagic => write!(f, "does not start with BED magic header"),
            SniffError::NotBed => write!(f, "not a recognized BED format"),
        }
    }
}

impl std::error::Error for SniffError {}

// ── Armor encoding / decoding ───────────────────────────────────────────────

/// Encode raw BED bytes into PEM-style armored text.
///
/// Produces a string like:
/// ```text
/// -----BEGIN BITCOIN ENCRYPTED BACKUP-----
/// <base64 line 1>
/// <base64 line 2>
/// ...
/// -----END BITCOIN ENCRYPTED BACKUP-----
/// ```
pub fn encode_armored(bed_bytes: &[u8]) -> String {
    let b64 = STANDARD.encode(bed_bytes);
    let mut out = String::with_capacity(b64.len() + ARMOR_BEGIN.len() + ARMOR_END.len() + 256);
    out.push_str(ARMOR_BEGIN);
    out.push('\n');
    for chunk in b64.as_bytes().chunks(LINE_WIDTH) {
        let s = std::str::from_utf8(chunk).unwrap_or("");
        out.push_str(s);
        out.push('\n');
    }
    out.push_str(ARMOR_END);
    out.push('\n');
    out
}

/// Decode armored BED text back to raw bytes.
///
/// Handles BOM, blank lines, and whitespace around header/footer lines.
pub fn decode_armored(input: &str) -> Result<Vec<u8>, ArmoredError> {
    // Strip UTF-8 BOM if present
    let s = input.strip_prefix('\u{FEFF}').unwrap_or(input);

    let mut payload_lines: Vec<&str> = Vec::new();
    let mut in_block = false;

    for raw_line in s.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        if line.starts_with("-----BEGIN") {
            if line == ARMOR_BEGIN {
                in_block = true;
                continue;
            }
            return Err(ArmoredError::WrongHeader);
        }

        if line.starts_with("-----END") {
            if line == ARMOR_END {
                break;
            }
            return Err(ArmoredError::WrongFooter);
        }

        if in_block {
            payload_lines.push(line);
        }
    }

    if payload_lines.is_empty() {
        return Err(ArmoredError::EmptyPayload);
    }

    let joined: String = payload_lines.concat();
    STANDARD
        .decode(joined.as_bytes())
        .map_err(|_| ArmoredError::InvalidBase64)
}

// ── Sniffing ────────────────────────────────────────────────────────────────

/// Detect whether a byte slice is a BED file.
///
/// Returns `true` if the data starts with `BEB\x01` magic or contains
/// the PEM armor header.
pub fn is_bed_binary(data: &[u8]) -> bool {
    data.len() >= 4 && data[0..4] == *BED_MAGIC
}

/// Detect whether a string is BED-formatted (armor or binary magic).
///
/// Returns `Ok(BedFormat)` with the detected format, or `Err(SniffError)`
/// if neither format matches.
pub fn sniff_bed(input: &[u8]) -> Result<BedFormat, SniffError> {
    // Fast path: check for binary magic
    if input.len() >= 4 && input[0..4] == *BED_MAGIC {
        return Ok(BedFormat::Binary);
    }

    // Slow path: check for armor header
    let text = std::str::from_utf8(input).unwrap_or("");
    if text.lines().any(|l| l.trim() == ARMOR_BEGIN) {
        return Ok(BedFormat::Armored);
    }

    Err(SniffError::NotBed)
}

/// Format of a BED file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BedFormat {
    /// Raw binary with `BEB\x01` magic prefix.
    Binary,
    /// PEM-style armored text.
    Armored,
}

impl fmt::Display for BedFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BedFormat::Binary => write!(f, "binary"),
            BedFormat::Armored => write!(f, "armored"),
        }
    }
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
#[path = "bed_container_tests.rs"]
mod tests;
