use super::*;

#[test]
fn test_absolute_blocks_roundtrip() {
    let original = APIAbsoluteTimelock {
        timelock_type: APIAbsoluteTimelockType::Blocks,
        value: 800_000,
    };
    let consensus = original.to_consensus().unwrap();
    let decoded = APIAbsoluteTimelock::from_consensus(consensus);
    assert_eq!(decoded, original);
}

#[test]
fn test_absolute_timestamp_roundtrip() {
    let original = APIAbsoluteTimelock {
        timelock_type: APIAbsoluteTimelockType::Timestamp,
        value: 1704067200,
    };
    let consensus = original.to_consensus().unwrap();
    let decoded = APIAbsoluteTimelock::from_consensus(consensus);
    assert_eq!(decoded, original);
}

#[test]
fn test_relative_blocks_roundtrip() {
    let original = APIRelativeTimelock {
        timelock_type: APIRelativeTimelockType::Blocks,
        value: 144,
    };
    let consensus = original.to_consensus().unwrap();
    let decoded = APIRelativeTimelock::from_consensus(consensus);
    assert_eq!(decoded, original);
}

#[test]
fn test_relative_time_roundtrip() {
    let original = APIRelativeTimelock {
        timelock_type: APIRelativeTimelockType::Time,
        value: 86400, // 1 day
    };
    let consensus = original.to_consensus().unwrap();
    let decoded = APIRelativeTimelock::from_consensus(consensus);
    // May differ slightly due to 512-second granularity
    assert!((decoded.value as i32 - original.value as i32).abs() < 512);
}

#[test]
fn test_absolute_blocks_validation() {
    let invalid = APIAbsoluteTimelock {
        timelock_type: APIAbsoluteTimelockType::Blocks,
        value: 500_000_000,
    };
    assert!(invalid.to_consensus().is_err());
}

#[test]
fn test_absolute_timestamp_validation() {
    let invalid = APIAbsoluteTimelock {
        timelock_type: APIAbsoluteTimelockType::Timestamp,
        value: 499_999_999,
    };
    assert!(invalid.to_consensus().is_err());
}
