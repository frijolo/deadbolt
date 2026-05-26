#!/usr/bin/env python3
"""
Regression test 38: On-chain descriptor backup — HW signing path.

Creates a **1-of-2 WSH multisig** wallet **exactly as reg34** (mismo xpubs,
mismo orden, mismo threshold), syncs, y ejerce el flujo de backup on-chain
con firma HW sin llegar a broadcast.

Mismo wallet que reg34:
  - WSH(sortedmulti(1, HW, watch-only))
  - HW key: m/48'/1'/0'/2' (BitBox02, MFP 4061aff0)
  - Cosigner: MFP ff81be5d, path 48'/1'/0'/2', xpub tpubDDxjvu...
  - Threshold: 1-of-2

Exit code: 0 = PASS or SKIP, 1 = FAIL.
"""

import asyncio
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver  # noqa: E402
from regression_helpers import (  # noqa: E402
    wait_for,
    navigate_wallets, click_label, click_tooltip, fill_field,
    set_active_network_signet, go_back_to_wallet_list,
    delete_wallet_from_list, wait_for_tooltip, run_regression,
    open_watch_only_manual_entry, fill_manual_keyspec,
    open_watch_only_hardware_wallet,
)
from hw_helpers import (  # noqa: E402
    connect_hw_in_open_sheet, wait_for_user,
    extract_first_receive_address, fail_no_funds,
    verify_first_receive_address_on_hw,
)

WALLET_NAME = "Reg34-HW-Sign-WSH-1of2"
HW_DERIVATION_PATH = "m/48'/1'/0'/2'"
COSIGNER_MFP = "ff81be5d"
COSIGNER_PATH = "48'/1'/0'/2'"
COSIGNER_XPUB = (
    "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL"
    "7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K"
)
HIGH_FEE_RATE = "1"


async def _add_cosigner_watchonly(d: UIDriver):
    """Add watch-only cosigner (exact flow from reg34)."""
    print("\n  [phase 2b] add watch-only cosigner")
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_manual_entry(d)
    await fill_manual_keyspec(d, mfp=COSIGNER_MFP, path=COSIGNER_PATH,
                              xpub=COSIGNER_XPUB, compact=True)
    await wait_for(d, COSIGNER_MFP.lower(), "watch-only key card visible",
                   retries=15, delay=0.5)
    print("    [ok] cosigner added")


async def _create_wallet(d: UIDriver):
    """Create 1-of-2 WSH multisig wallet (exact flow from reg34)."""
    print("\n  [phase 2a] create WSH(1-of-2) wallet from HW xpub")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened", retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "guided creation screen opened", retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)
    await wait_for(d, "Singlesig", "wallet type segments visible", retries=10, delay=0.5)
    await click_label(d, "Multisig", delay=0.5)
    await click_label(d, "SegWit", delay=0.4)

    print("\n  [phase 2b] add HW key")
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_hardware_wallet(d)
    await fill_field(d, "Derivation path", HW_DERIVATION_PATH)
    await click_label(d, "Confirm", delay=0.6)

    mfp = await connect_hw_in_open_sheet(d, op_label="export xpub")
    await click_label(d, "Export xpub", delay=0.5)
    await wait_for(d, mfp, f"key card with MFP {mfp} visible", retries=30, delay=1.0)

    await _add_cosigner_watchonly(d)
    await wait_for(d, "Create wallet", "Create wallet button visible", retries=10, delay=0.5)
    await click_label(d, "Create wallet", delay=0.5)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=60, delay=1.0)
    return mfp


async def _sync_and_check_funds(d: UIDriver):
    """Sync the wallet and skip if no UTXOs."""
    print("\n  [phase 3] sync wallet — wait for UTXOs")
    await wait_for_tooltip(d, "Sync wallet", "sync button available")
    await click_label(d, "Coins", delay=1.0)
    for _ in range(120):
        sem = await d.cs_flat_text()
        if "sats" in sem or "No coins" in sem:
            break
        await asyncio.sleep(1.5)
    if "No coins" in sem or "sats" not in sem:
        await click_label(d, "Addresses", delay=0.8)
        await wait_for(d, "receive_address_0", "first receive address visible",
                       retries=15, delay=1.0)
        addr = await extract_first_receive_address(d)
        fail_no_funds(addr, WALLET_NAME)
    print("    [ok] sync complete — confirmed UTXO present")


# ---------------------------------------------------------------------------
# Backup screen helpers
# ---------------------------------------------------------------------------

async def _open_publish_backup_sheet(d):
    """Wallet detail → More options → Export → Publish Backup → On-chain."""
    await click_tooltip(d, "More options", delay=0.6)
    await click_label(d, "Export", delay=0.6)
    await wait_for(d, "Publish Backup", "Export choice sheet open")
    await click_label(d, "Publish Backup", delay=0.6)
    flat = await d.cs_flat_text()
    if "Backup not recommended" in flat:
        try:
            await click_label(d, "I understand, show options anyway", delay=0.4)
        except AssertionError:
            pass
    await wait_for(d, '"On-chain"', "Publish backup options visible")
    await click_label(d, "On-chain", delay=1.0)


async def _wait_backup_screen_phase(d, retries=40, delay=1.0):
    """Return 'exists' | 'utxo' | 'failed'."""
    for _ in range(retries):
        flat = await d.cs_flat_text()
        if "Backup already exists" in flat:
            return "exists"
        if "Build TX_COMMIT" in flat:
            return "utxo"
        if "Retry" in flat and "Backup already exists" not in flat:
            return "failed"
        await asyncio.sleep(delay)
    raise AssertionError("Timeout waiting for on-chain backup screen to settle")


async def _select_first_utxo(d):
    """Open coin selector and pick the first UTXO."""
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
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.5)
    await wait_for(d, '"Select coins"', "coin selector opened", retries=10, delay=0.5)

    rows = await d.cs_find_all_label_containing(" sats")
    target = None
    for r in rows:
        if (r[3] - r[1]) >= 30:
            target = r
            break
    if target is None:
        raise AssertionError("No coin rows visible")
    d.flutter_click((target[0] + target[2]) // 2, (target[1] + target[3]) // 2)
    await asyncio.sleep(0.8)
    done = await d.cs_find_by_label_part_containing("Done") or await d.cs_find_label_containing("Done")
    if done is None:
        raise AssertionError("Coin-selector 'Done' button missing")
    d.flutter_click((done[0] + done[2]) // 2, (done[1] + done[3]) // 2)
    await asyncio.sleep(1.2)
    print("    [ok] one coin selected")


async def _set_fee_rate(d):
    """Set fee rate to HIGH_FEE_RATE sat/vB."""
    print(f"\n  [phase 5] Set fee rate to {HIGH_FEE_RATE} sat/vB")
    await fill_field(d, "Fee rate (sats/vB)", HIGH_FEE_RATE)
    await asyncio.sleep(0.3)
    flat = await d.cs_flat_text()
    assert HIGH_FEE_RATE in flat, f"fee rate not updated to '{HIGH_FEE_RATE}'"
    print(f"    [ok] fee rate confirmed as {HIGH_FEE_RATE} sat/vB")


async def _build_psbt(d):
    """Build TX_COMMIT and wait for signing options."""
    print("\n  [phase 6] Build TX_COMMIT")
    await click_label(d, "Build TX_COMMIT", delay=1.0)
    for _ in range(30):
        flat = await d.cs_flat_text()
        if "Sign with HW" in flat or "Sign with hot key" in flat:
            print("    [ok] PSBT built — awaiting signature")
            return
        if "Build TX_COMMIT" not in flat and "Building PSBT" not in flat:
            await asyncio.sleep(0.5)
        await asyncio.sleep(0.6)
    raise AssertionError("Timeout: PSBT build did not produce signing options")


async def _sign_with_hw(d):
    """Sign the TX_COMMIT PSBT with the BitBox02."""
    print("\n  [phase 7] Sign with BitBox02")
    await click_label(d, "Sign with HW", delay=0.5)
    mfp = await connect_hw_in_open_sheet(d, op_label="sign backup")
    await click_label(d, "Sign transaction", delay=0.5)
    await wait_for_user(
        "Review the on-chain backup commit transaction on the BitBox screen "
        "and confirm the signature."
    )
    for _ in range(40):
        flat = await d.cs_flat_text()
        if "Confirm broadcast" in flat:
            print("    [ok] reached confirm-broadcast view")
            return
        await asyncio.sleep(0.6)
    raise AssertionError("Timeout: signing did not reach confirm-broadcast")


# ---------------------------------------------------------------------------
# Confirm-broadcast validation
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
    """Validate confirm-broadcast view coherence."""
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

    assert parsed["anchor_amount"] == 330, f"anchor expected 330, got {parsed['anchor_amount']}"
    # 1-of-2 multisig → 2 anchors (one per participating key)
    assert parsed["anchor_count"] >= 2, f"expected ≥ 2 anchors, got {parsed['anchor_count']}"
    print(f"    [ok] anchor count = {parsed['anchor_count']} (≥ 2)")

    # All displayed change outputs must be above P2TR dust (330 sats).
    for ch in parsed.get("changes", []):
        assert ch >= 330, f"change output {ch} sats below dust (330)"
    print(f"    [ok] all change outputs ≥ 330 dust threshold")

    assert parsed["vault"] > 0 and parsed["commit_fee"] > 0
    assert parsed["reveal_fee"] > 0 and parsed["package_vb"] > 0

    expected_total = parsed["commit_fee"] + parsed["reveal_fee"]
    assert parsed["total_fee"] == expected_total, (
        f"total fee mismatch: {parsed['total_fee']} ≠ {expected_total}"
    )
    print(f"    [ok] fees coherent: {parsed['commit_fee']} + {parsed['reveal_fee']} = {parsed['total_fee']}")


async def _back_out_without_broadcasting(d):
    """Back out WITHOUT broadcasting."""
    print("\n  [phase 9] Back out WITHOUT broadcasting")
    flat = await d.cs_flat_text()
    assert "Broadcast" in flat, "Broadcast button gone"
    await click_tooltip(d, "Back", delay=0.8)
    flat = await d.cs_flat_text()
    assert "Confirm broadcast" not in flat, "still on confirm-broadcast"
    assert "Sign with HW" in flat or "Sign with hot key" in flat
    print("    [ok] returned to awaiting-signature without broadcasting")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def test_onchain_backup_hw(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (On-chain backup — BitBox02 signing) ---")

    await set_active_network_signet(d)
    await _create_wallet(d)
    await verify_first_receive_address_on_hw(d, op_label="verify WSH multisig address")
    await _sync_and_check_funds(d)

    await _open_publish_backup_sheet(d)
    phase = await _wait_backup_screen_phase(d)
    print(f"    [ok] backup screen settled on phase '{phase}'")
    if phase == "exists":
        flat = await d.cs_flat_text()
        assert "Backup already exists" in flat and "TX_COMMIT" in flat
        print("    [ok] backup-exists view verified")
        await click_label(d, "Create new backup", delay=1.0)
        await wait_for(d, '"Build TX_COMMIT"', "utxo-selection visible", retries=30, delay=0.8)
    elif phase == "utxo":
        pass
    else:
        raise AssertionError(f"Unexpected backup phase: '{phase}'")

    await _select_first_utxo(d)
    await _set_fee_rate(d)
    await _build_psbt(d)
    await _sign_with_hw(d)
    await _verify_confirm_broadcast(d)
    await _back_out_without_broadcasting(d)

    print("\n  [phase 10] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)
    print(f"    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_onchain_backup_hw, "reg38"))
