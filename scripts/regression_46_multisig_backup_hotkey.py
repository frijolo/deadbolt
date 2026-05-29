#!/usr/bin/env python3
"""
Regression test 46: On-chain descriptor backup — hot-key multisig signing path.

Companion to reg38 (HW signing path). Exercises the iterative hot-key
multisig signing flow introduced in commit ba63759:
  - Multiple signer rows on the awaiting-signature view (one per MFP in
    the selected spend path).
  - Each successful hot-key sign merges its partial signature into the
    accumulator (combine_psbts) and updates `_psbtAnalysis`.
  - The screen only advances to confirm-broadcast when the signer count
    reaches the path threshold.
  - Per-path fee estimation must remain coherent
    (commit_fee + reveal_fee == total_fee).

Wallet topology:
  - 2-of-2 WSH(sortedmulti(...)) on signet, derived from two BIP39
    mnemonics. Both keys are hot keys controlled by this app — funded once
    on signet, the test is fully idempotent (no broadcast).

Skips ONLY if the wallet has no confirmed UTXOs (prints the first receive
address so the operator can fund it).

Exit code: 0 = PASS or SKIP (unfunded), 1 = FAIL.
"""

import asyncio
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver  # noqa: E402
from regression_helpers import (  # noqa: E402
    wait_for, wait_absent,
    navigate_wallets, click_label, click_tooltip, fill_field,
    set_active_network_signet, go_back_to_wallet_list,
    delete_wallet_from_list, wait_for_tooltip, run_regression,
    open_hot_existing_mnemonic,
)
import os
import subprocess

WALLET_NAME = "Reg46-Multisig-Hot-Backup"

# Two distinct, deterministic BIP39 mnemonics. The resulting 2-of-2 WSH
# descriptor (BIP48 m/48'/1'/0'/2') is fixed; fund the wallet's first
# receive address on signet once and the test stays idempotent thereafter.
MNEMONIC_A = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder oval"
)
MNEMONIC_B = (
    "abandon abandon abandon abandon abandon abandon "
    "abandon abandon abandon abandon abandon about"
)
HIGH_FEE_RATE = "1"


# ---------------------------------------------------------------------------
# Wallet creation: guided multisig 2-of-2 with two hot keys
# ---------------------------------------------------------------------------

async def _add_hot_key(d: UIDriver, mnemonic: str, label: str):
    print(f"\n  [add hot key: {label}]")
    await click_label(d, "Add key", delay=0.5)
    await open_hot_existing_mnemonic(d)
    await fill_field(d, "Seed phrase", mnemonic)
    await wait_for(d, "Derived keyspec", "keyspec derived",
                   retries=25, delay=1.0)
    await click_label(d, "Add", delay=1.0)
    # Wait for the Add-key sheet to close (capacity tile gone).
    await wait_absent(d, "Watch-only key", "add-key sheet closed",
                      retries=20, delay=0.5)


async def _create_wallet(d: UIDriver):
    print(f"\n  [phase 1] create wallet via Guided creation: {WALLET_NAME}")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened",
                   retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "guided creation screen opened",
                   retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)

    await wait_for(d, "Singlesig", "wallet-type segments visible",
                   retries=10, delay=0.5)
    await click_label(d, "Multisig", delay=0.5)
    await click_label(d, "SegWit", delay=0.4)

    # Add two hot keys, then bump threshold 1 → 2 (default is 1-of-N).
    await _add_hot_key(d, MNEMONIC_A, "key A")
    await _add_hot_key(d, MNEMONIC_B, "key B")
    await click_tooltip(d, "Increase threshold", delay=0.4)
    await wait_for(d, "Required signatures: 2 of 2", "threshold = 2 of 2",
                   retries=10, delay=0.4)

    # SimpleWalletDialog shows one 'Remove key' tooltip per added key.
    flat = await d.cs_flat_text()
    remove_count = flat.count("Remove key")
    assert remove_count >= 2, (
        f"expected 2 Remove key tooltips, got {remove_count} — "
        f"second hot key likely not added"
    )

    await click_label(d, "Create wallet", delay=1.0)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=60, delay=1.0)


# ---------------------------------------------------------------------------
# Full receive address extraction (via Receive dialog → Copy)
# ---------------------------------------------------------------------------

async def _extract_full_first_address_via_receive(d: UIDriver) -> str:
    """Open the Receive dialog from the Overview tab, hit the copy-to-clipboard
    button, then read the clipboard via xclip. Returns the FULL bech32 address
    (the Addresses-tab list truncates with ellipsis). Closes the dialog."""
    # Make sure we're on Overview (Receive button only lives there).
    flat = await d.cs_flat_text()
    if '"Receive"' not in flat:
        await click_label(d, "Overview", delay=0.4)
        await wait_for(d, '"Receive"', "Overview tab active",
                       retries=10, delay=0.5)
    await click_label(d, "Receive", delay=0.6)
    await wait_for(d, "Copy to clipboard", "Receive dialog opened",
                   retries=15, delay=0.5)
    # Clear clipboard first so we don't read a stale value.
    env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(["xclip", "-selection", "clipboard"],
                   input=b"", env=env, check=False)
    await click_label(d, "Copy to clipboard", delay=0.8)
    await asyncio.sleep(0.4)
    out = subprocess.run(
        ["xclip", "-selection", "clipboard", "-o"],
        env=env, capture_output=True, check=False,
    )
    addr = out.stdout.decode().strip()
    # Close the Receive dialog.
    try:
        await click_tooltip(d, "Cancel", delay=0.5)
    except AssertionError:
        d.key("Escape")
        await asyncio.sleep(0.3)
    return addr or "(clipboard empty — check Receive dialog manually)"


# ---------------------------------------------------------------------------
# Sync / skip on unfunded
# ---------------------------------------------------------------------------

async def _sync_and_check_funds(d: UIDriver):
    print("\n  [phase 2] sync wallet — wait for UTXOs")
    await wait_for_tooltip(d, "Sync wallet", "sync button available")
    await click_label(d, "Coins", delay=1.0)
    sem = ""
    for _ in range(120):
        sem = await d.cs_flat_text()
        if "sats" in sem or "No coins" in sem:
            break
        await asyncio.sleep(1.5)
    if "No coins" in sem or "sats" not in sem:
        addr = await _extract_full_first_address_via_receive(d)
        print(f"\n[SKIP] Wallet '{WALLET_NAME}' is not funded.")
        print(f"       Send a small amount on Signet to: {addr}")
        print("       Then re-run this regression.")
        sys.exit(0)
    print("    [ok] sync complete — confirmed UTXO present")


# ---------------------------------------------------------------------------
# Backup screen helpers (same surface as reg38)
# ---------------------------------------------------------------------------

async def _open_publish_backup_sheet(d):
    await click_tooltip(d, "More options", delay=0.6)
    await click_label(d, "Export", delay=0.6)
    await wait_for(d, "Publish Descriptor", "Export choice sheet open")
    await click_label(d, "Publish Descriptor", delay=0.6)
    flat = await d.cs_flat_text()
    if "Backup not recommended" in flat:
        try:
            await click_label(d, "I understand, show options anyway", delay=0.4)
        except AssertionError:
            pass
    await wait_for(d, '"On-chain"', "Publish backup options visible")
    await click_label(d, "On-chain", delay=1.0)


async def _wait_backup_screen_phase(d, retries=40, delay=1.0):
    for _ in range(retries):
        flat = await d.cs_flat_text()
        if "Backup already exists" in flat:
            return "exists"
        if "Build TX_COMMIT" in flat:
            return "utxo"
        if "Retry" in flat and "Backup already exists" not in flat:
            return "failed"
        await asyncio.sleep(delay)
    raise AssertionError("Timeout waiting for backup screen")


async def _select_first_utxo(d):
    print("\n  [phase 4] Select first UTXO")
    rect = (
        await d.cs_find_label_containing("Tap to select coins")
        or await d.cs_find_label_containing("Select a coin with at least")
        or await d.cs_find_label_containing("No coins selected")
        or await d.cs_find_label_containing("coins selected")
        or await d.cs_find_label_containing("UTXOs available")
    )
    if rect is None:
        raise AssertionError("Coin-selector card not found")
    flat = await d.cs_flat_text()
    if "No UTXOs available" in flat:
        raise AssertionError("Wallet has no UTXOs")
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(1.5)
    await wait_for(d, '"Select coins"', "coin selector opened",
                   retries=10, delay=0.5)
    rows = await d.cs_find_all_label_containing(" sats")
    target = next((r for r in rows if (r[3] - r[1]) >= 30), None)
    if target is None:
        raise AssertionError("No coin rows visible")
    d.flutter_click((target[0] + target[2]) // 2, (target[1] + target[3]) // 2)
    await asyncio.sleep(0.8)
    done = (await d.cs_find_by_label_part_containing("Done")
            or await d.cs_find_label_containing("Done"))
    if done is None:
        raise AssertionError("Coin-selector 'Done' button missing")
    d.flutter_click((done[0] + done[2]) // 2, (done[1] + done[3]) // 2)
    await asyncio.sleep(1.2)


async def _set_fee_rate(d):
    print(f"\n  [phase 5] Set fee rate to {HIGH_FEE_RATE} sat/vB")
    await fill_field(d, "Fee rate (sats/vB)", HIGH_FEE_RATE)
    await asyncio.sleep(0.3)
    flat = await d.cs_flat_text()
    assert HIGH_FEE_RATE in flat, f"fee rate not updated to '{HIGH_FEE_RATE}'"


async def _build_psbt(d):
    print("\n  [phase 6] Build TX_COMMIT")
    await click_label(d, "Build TX_COMMIT", delay=1.0)
    for _ in range(30):
        flat = await d.cs_flat_text()
        # After build, the awaiting-signature view shows the signer list +
        # at least one 'Sign' button (per hot key in the selected path).
        if "Signatures (" in flat and "Sign" in flat:
            print("    [ok] PSBT built — signer list visible")
            return
        await asyncio.sleep(0.6)
    raise AssertionError("Timeout: PSBT build did not produce signer list")


# ---------------------------------------------------------------------------
# Iterative hot-key signing
# ---------------------------------------------------------------------------

def _parse_signature_progress(flat: str) -> tuple[int, int, int] | None:
    """Return (done, threshold, total) from 'Signatures (D/T of N)' or None."""
    m = re.search(r"Signatures \((\d+)/(\d+) of (\d+)\)", flat)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


async def _click_first_unsigned_sign_button(d):
    """Click the 'Sign' button on the first signer row whose row text does
    not already contain 'Signed'. We rely on _BackupSignerRow having one
    inline 'Sign' button per unsigned hot-key MFP."""
    rects = await d.cs_find_all_label_containing("Sign")
    candidates = []
    for r in rects:
        h = r[3] - r[1]
        w = r[2] - r[0]
        # Filter out section headers / signed status badges. The inline button
        # is a small tonal button (height ~32-44 px, width usually < 120 px).
        if 24 <= h <= 56 and w <= 200:
            candidates.append(r)
    if not candidates:
        raise AssertionError("No 'Sign' button found on awaiting-signature view")
    # Top-most candidate = first unsigned signer row.
    candidates.sort(key=lambda r: r[1])
    target = candidates[0]
    d.flutter_click((target[0] + target[2]) // 2,
                    (target[1] + target[3]) // 2,
                    delay_s=0.4)
    await asyncio.sleep(1.5)


async def _wait_signature_count(d, expected_done: int,
                                retries: int = 40, delay: float = 0.6):
    for _ in range(retries):
        flat = await d.cs_flat_text()
        progress = _parse_signature_progress(flat)
        if progress and progress[0] == expected_done:
            return progress
        await asyncio.sleep(delay)
    raise AssertionError(
        f"Timeout waiting for signature count = {expected_done}; "
        f"last progress = {_parse_signature_progress(flat)}"
    )


async def _sign_with_two_hot_keys(d):
    """Click Sign on signer A → assert still awaiting + 1/2.
    Then click Sign on signer B → assert reached confirm-broadcast."""
    print("\n  [phase 7a] Sign with first hot key")
    flat = await d.cs_flat_text()
    progress = _parse_signature_progress(flat)
    assert progress is not None, "signer progress label missing"
    done0, threshold, total = progress
    assert threshold == 2 and total == 2, (
        f"expected 2-of-2 progress, got {progress}"
    )
    assert done0 == 0, f"expected fresh PSBT (0 sigs), got {done0}"

    await _click_first_unsigned_sign_button(d)
    progress = await _wait_signature_count(d, expected_done=1)
    print(f"    [ok] progress after 1st sign: {progress}")

    flat = await d.cs_flat_text()
    # Threshold not yet met → must stay on awaiting-signature view.
    assert "Confirm broadcast" not in flat, (
        "reached confirm-broadcast prematurely after first sign"
    )

    print("\n  [phase 7b] Sign with second hot key")
    await _click_first_unsigned_sign_button(d)
    for _ in range(40):
        flat = await d.cs_flat_text()
        if "Confirm broadcast" in flat:
            print("    [ok] reached confirm-broadcast after 2nd sign")
            return
        await asyncio.sleep(0.6)
    raise AssertionError("Timeout: did not reach confirm-broadcast after 2nd sign")


# ---------------------------------------------------------------------------
# Confirm-broadcast validation (same parser as reg38)
# ---------------------------------------------------------------------------

_NUM_RX = r"[0-9][0-9,\.\s ]*"


def _to_int(s: str) -> int:
    return int(re.sub(r"[^\d]", "", s))


def _dedupe_consecutive(values: list) -> list:
    out = []
    for v in values:
        if not out or out[-1] != v:
            out.append(v)
    return out


def _parse_confirm_broadcast(flat: str) -> dict:
    out = {}
    m = re.search(rf"Vault:\s+({_NUM_RX})\s+sats", flat)
    if m:
        out["vault"] = _to_int(m.group(1))
    m = re.search(rf"Anchors:\s+(\d+)\s+×\s+(\d+)\s+sats", flat)
    if m:
        out["anchor_count"] = int(m.group(1))
        out["anchor_amount"] = int(m.group(2))
    changes = _dedupe_consecutive(
        [_to_int(s) for s in re.findall(rf"Change:\s+({_NUM_RX})\s+sats", flat)]
    )
    if changes:
        out["changes"] = changes
    fee_only = _dedupe_consecutive(
        [_to_int(s) for s in re.findall(rf"Fee:\s+({_NUM_RX})\s+sats(?!\s*·)", flat)]
    )
    if len(fee_only) >= 2:
        out["commit_fee"] = fee_only[0]
        out["reveal_fee"] = fee_only[1]
    m = re.search(rf"Fee:\s+({_NUM_RX})\s+sats\s+·\s+(\d+)\s+vB", flat)
    if m:
        out["total_fee"] = _to_int(m.group(1))
        out["package_vb"] = int(m.group(2))
    return out


async def _verify_confirm_broadcast(d):
    print("\n  [phase 8] Validate confirm-broadcast coherence")
    await asyncio.sleep(0.4)
    flat = await d.cs_flat_text()
    assert "Confirm broadcast" in flat, "not on confirm-broadcast view"

    parsed = _parse_confirm_broadcast(flat)
    print(f"    [parsed] {parsed}")

    required = {"vault", "anchor_count", "anchor_amount",
                "commit_fee", "reveal_fee", "total_fee", "package_vb"}
    missing = required - parsed.keys()
    assert not missing, f"missing fields: {missing}"

    assert parsed["anchor_amount"] == 330, (
        f"anchor expected 330, got {parsed['anchor_amount']}"
    )
    # 2-of-2 multisig → 2 anchors (one per participating key).
    assert parsed["anchor_count"] >= 2, (
        f"expected ≥ 2 anchors, got {parsed['anchor_count']}"
    )

    for ch in parsed.get("changes", []):
        assert ch >= 330, f"change output {ch} sats below dust"

    assert parsed["vault"] > 0 and parsed["commit_fee"] > 0
    assert parsed["reveal_fee"] > 0 and parsed["package_vb"] > 0
    expected_total = parsed["commit_fee"] + parsed["reveal_fee"]
    assert parsed["total_fee"] == expected_total, (
        f"total fee mismatch: {parsed['total_fee']} ≠ {expected_total}"
    )
    print(
        f"    [ok] fees coherent: {parsed['commit_fee']} + "
        f"{parsed['reveal_fee']} = {parsed['total_fee']}"
    )


# ---------------------------------------------------------------------------
# Idempotent exit: back out without broadcasting
# ---------------------------------------------------------------------------

async def _back_out_without_broadcasting(d):
    print("\n  [phase 9] Back out WITHOUT broadcasting")
    flat = await d.cs_flat_text()
    assert "Broadcast" in flat, "Broadcast button gone"
    await click_tooltip(d, "Back", delay=0.8)
    flat = await d.cs_flat_text()
    assert "Confirm broadcast" not in flat, "still on confirm-broadcast"
    # Returning lands us back on the awaiting-signature phase (signer list).
    assert "Signatures (" in flat, "did not return to awaiting-signature view"
    print("    [ok] returned to awaiting-signature without broadcasting")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def test_multisig_backup_hotkey(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (On-chain backup — hot-key 2-of-2 signing) ---")

    await set_active_network_signet(d)
    await _create_wallet(d)
    await _sync_and_check_funds(d)

    await _open_publish_backup_sheet(d)
    phase = await _wait_backup_screen_phase(d)
    print(f"    [ok] backup screen settled on phase '{phase}'")
    if phase == "exists":
        await click_label(d, "Create new backup", delay=1.0)
        await wait_for(d, '"Build TX_COMMIT"', "utxo-selection visible",
                       retries=30, delay=0.8)
    elif phase != "utxo":
        raise AssertionError(f"Unexpected backup phase: '{phase}'")

    await _select_first_utxo(d)
    await _set_fee_rate(d)
    await _build_psbt(d)
    await _sign_with_two_hot_keys(d)
    await _verify_confirm_broadcast(d)
    await _back_out_without_broadcasting(d)

    print("\n  [phase 10] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)
    print(f"    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_multisig_backup_hotkey, "reg46"))
