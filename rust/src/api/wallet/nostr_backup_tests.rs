use super::*;

#[test]
fn test_derive_nostr_keypair_deterministic() {
    let xpub = "xpub6C5sJJ3iZxbkUDa4zMBGEPfUuQScT6eEJPZGUBJvFrLwS7T6cjvzGTjK9h8hmz";
    let k1 = derive_nostr_keypair(xpub).unwrap();
    let k2 = derive_nostr_keypair(xpub).unwrap();
    assert_eq!(k1.public_key(), k2.public_key());
}

#[test]
fn test_derive_nostr_keypair_different_xpubs() {
    let k1 = derive_nostr_keypair("xpubAAA").unwrap();
    let k2 = derive_nostr_keypair("xpubBBB").unwrap();
    assert_ne!(k1.public_key(), k2.public_key());
}

/// fetch_nostr_backup strips [mfp/path] from the credential before deriving
/// the Nostr pubkey, matching how publish_nostr_backup uses the bare xpub
/// extracted from the descriptor.
#[test]
fn test_keyspec_stripped_same_pubkey_as_bare_xpub() {
    let bare = "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K";
    let keyspec = "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K";

    let (_, stripped) = parse_xpub_credential(keyspec);
    assert_eq!(stripped, bare, "keyspec stripping should yield bare xpub");

    let k_bare = derive_nostr_keypair(bare).unwrap();
    let k_from_keyspec = derive_nostr_keypair(stripped).unwrap();
    assert_eq!(
        k_bare.public_key(),
        k_from_keyspec.public_key(),
        "Nostr keypair from bare xpub must match keypair from stripped keyspec"
    );
}

/// The most recent event (by timestamp) determines backup status.
/// A deletion event (empty content, newer ts) must override an old backup
/// even when a non-NIP-33-compliant relay returns both events.
#[test]
fn test_deletion_event_wins_over_older_backup() {
    // Simulate ws_fetch_backup logic with two events: backup at t=1000,
    // deletion (empty content) at t=2000.
    let events: Vec<(i64, &str)> = vec![
        (1000, "aGVsbG8="), // base64("hello") — old backup
        (2000, ""),         // empty — deletion marker, newer
    ];

    let mut best_ts: Option<i64> = None;
    let mut best_content = String::new();
    for (ts, content) in &events {
        if best_ts.is_none_or(|prev| *ts > prev) {
            best_ts = Some(*ts);
            best_content = content.to_string();
        }
    }
    assert!(
        best_content.is_empty(),
        "deletion event at t=2000 must override backup at t=1000"
    );

    // Reverse: re-published backup (t=3000) after deletion (t=2000) → visible.
    let events2: Vec<(i64, &str)> = vec![
        (1000, "aGVsbG8="),
        (2000, ""),
        (3000, "aGVsbG8="), // re-published
    ];

    let mut best_ts2: Option<i64> = None;
    let mut best_content2 = String::new();
    for (ts, content) in &events2 {
        if best_ts2.is_none_or(|prev| *ts > prev) {
            best_ts2 = Some(*ts);
            best_content2 = content.to_string();
        }
    }
    assert!(
        !best_content2.is_empty(),
        "re-published backup at t=3000 must be visible after deletion at t=2000"
    );
}

#[test]
fn test_descriptor_d_tag_format() {
    let desc = "wpkh([deadbeef/84'/0'/0']xpub6C5s.../<0;1>/*)";
    let tag = descriptor_d_tag(desc);
    assert!(tag.starts_with("deadbolt-backup-"), "tag: {tag}");
    // fingerprint is 8 lowercase hex chars
    let fingerprint = tag.strip_prefix("deadbolt-backup-").unwrap();
    assert_eq!(fingerprint.len(), 8);
    assert!(fingerprint.chars().all(|c| c.is_ascii_hexdigit()));
}

#[test]
fn test_descriptor_d_tag_different_descriptors() {
    let t1 = descriptor_d_tag("wpkh([aabb/84'/0'/0']xpub6Aaa.../<0;1>/*)");
    let t2 = descriptor_d_tag("wpkh([aabb/84'/0'/1']xpub6Aaa.../<0;1>/*)");
    assert_ne!(t1, t2, "different descriptors must yield different d-tags");
}

#[test]
fn test_descriptor_d_tag_same_descriptor_deterministic() {
    let desc = "wpkh([deadbeef/84'/0'/0']xpub6C5s.../<0;1>/*)";
    assert_eq!(descriptor_d_tag(desc), descriptor_d_tag(desc));
}

#[test]
fn test_payload_roundtrip() {
    let descriptor = "wpkh([deadbeef/84'/0'/0']xpub6C5sJJ3iZxbkUDa4zMBGEPfUuQScT6eEJPZGUBJvFrLwS7T6cjvzGTjK9h8hmzXmqVbHD5sS9Kf2hHimLMjMiUZFrCHn5qGVmCNBHHxr1/<0;1>/*)";
    let xpub = "xpub6C5sJJ3iZxbkUDa4zMBGEPfUuQScT6eEJPZGUBJvFrLwS7T6cjvzGTjK9h8hmzXmqVbHD5sS9Kf2hHimLMjMiUZFrCHn5qGVmCNBHHxr1";
    let mfp = "deadbeef";
    let payload_bytes =
        build_payload_for_xpub(descriptor, "Test Wallet", "bitcoin", mfp, xpub, 0, None).unwrap();

    // Verify structure
    let payload: serde_json::Value = serde_json::from_slice(&payload_bytes).unwrap();
    assert_eq!(payload["version"], 1);
    assert_eq!(payload["wallet_name"], "Test Wallet");
    assert_eq!(payload["network"], "bitcoin");
    assert_eq!(payload["protection"]["type"], 2);
    assert!(payload["protection"]["slots"].as_array().unwrap().len() == 1);

    // Verify decryptable with the xpub
    let slots: Vec<XpubSlot> = payload["protection"]["slots"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| serde_json::from_value(s.clone()).unwrap())
        .collect();
    let export_key = resolve_xpub_data_key(xpub, &slots).unwrap();

    let data_b64 = payload["data"].as_str().unwrap();
    let encrypted = general_purpose::STANDARD.decode(data_b64).unwrap();
    let inner_bytes = decrypt_bytes(&export_key, &encrypted).unwrap();
    let inner: serde_json::Value = serde_json::from_slice(&inner_bytes).unwrap();
    assert_eq!(inner["descriptor"].as_str().unwrap(), descriptor);
}
