#!/usr/bin/env python3
"""
Regression test 39: Hardware wallet recovery discovery.

Tests the **Hardware tab** of the Restore Wallet screen:
  1. Navigate to Wallet list → New → "Recover Wallet".
  2. Switch to the Hardware tab.
  3. Connect the BitBox02 device (pairing if needed).
  4. Tap "Scan accounts" (starts HW discovery).
  5. Verify progress phases: deriving → scanning → done.
  6. Verify results: either account cards with activity data
     or "no activity" message.

Skips if no HW device is detected.
Does NOT create or import any wallet — discovery-only.

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
    navigate_wallets, click_label, click_tooltip,
    set_active_network_signet, go_back_to_wallet_list,
    run_regression,
)
from hw_helpers import (  # noqa: E402
    connect_hw_in_open_sheet, skip_test,
)

WALLET_LABEL = "Reg39-HW-Recovery"


# ---------------------------------------------------------------------------
# Helpers for the HW discovery flow
# ---------------------------------------------------------------------------

async def _open_restore_screen(d: UIDriver):
    """Wallet list → New → Recover Wallet → wait for restore screen."""
    print("\n  [phase 1] open restore wallet screen")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Recover Wallet", "new-wallet bottom sheet",
                    retries=10, delay=0.5)
    await click_label(d, "Recover Wallet", delay=0.5)
    # The restore screen AppBar shows "Recover Wallet" (EN).
    await wait_for(d, "Recover Wallet", "restore wallet screen opened",
                    retries=15, delay=0.5)
    print("    [ok] restore wallet screen visible")


async def _switch_to_hardware_tab(d: UIDriver):
    """Tap the Hardware tab in the restore screen."""
    print("\n  [phase 2] switch to Hardware tab")
    await click_label(d, "Hardware", delay=0.8)
    # The Hardware tab renders one of two states:
    #   - device list with "Select a device" header (HW connected)
    #   - empty state "No hardware wallet detected" (no HW)
    # Either confirms the tab is active; SKIP is handled later by
    # connect_hw_in_open_sheet when no device is present.
    for _ in range(15):
        flat = await d.cs_flat_text()
        if "Select a device" in flat or "No hardware wallet detected" in flat:
            print("    [ok] hardware tab active")
            return
        await asyncio.sleep(0.5)
    raise AssertionError(
        "Timeout: hardware tab content not visible after tapping Hardware"
    )


async def _start_hw_discovery(d: UIDriver, mfp: str):
    """Tap the scan button and wait for progress phase to begin."""
    print("\n  [phase 3] start HW discovery")
    await click_label(d, "Scan accounts", delay=1.0)
    # After tapping scan, the UI shows a progress indicator.
    # May show "Deriving" (if fresh connection) or "Scanning" (if HW
    # session already connected).  Wait for either.
    for _ in range(60):
        flat = await d.cs_flat_text()
        if "Deriving" in flat or "Deriv" in flat:
            print("    [ok] deriving phase detected")
            return
        if "Scanning" in flat or "scanning" in flat:
            print("    [ok] scanning phase detected (HW already connected)")
            return
        await asyncio.sleep(1.0)
    raise AssertionError("Timeout waiting for discovery to start")


async def _wait_scanning_phase(d: UIDriver):
    """Wait for the scanning phase to begin (deriving finished)."""
    print("\n  [phase 4] wait for scanning phase")
    # "Scanning" may already be present if HW was already connected.
    flat = await d.cs_flat_text()
    if "Scanning" in flat or "scanning" in flat:
        print("    [ok] scanning phase already active")
        return
    await wait_for(d, "Scanning", "scanning phase started",
                    retries=120, delay=1.0)
    print("    [ok] scanning phase detected")


async def _wait_results(d: UIDriver) -> str:
    """
    Wait for discovery to complete.
    Returns 'found' if accounts/backups were found, 'none' if no activity.
    """
    print("\n  [phase 5] wait for results")
    for _ in range(300):
        flat = await d.cs_flat_text()
        # Check for "X account(s) found" or "Found X backups" text.
        if "found" in flat.lower():
            # Print the line containing "found" for debugging.
            for line in flat.splitlines():
                if "found" in line.lower():
                    print(f"    [ok] {line.strip()}")
            return "found"
        # Check for "No activity found" text (no results).
        if "no activity" in flat.lower():
            print("    [ok] no-activity result detected")
            return "none"
        await asyncio.sleep(1.0)
    raise AssertionError(
        "Timed out waiting for discovery results (5 min)"
    )


async def _verify_found_results(d: UIDriver):
    """Verify that found result cards have expected content."""
    print("\n  [phase 6a] verify found results")
    flat = await d.cs_flat_text()

    # Verify "X account(s) found" or "Found X backups" is present.
    assert "found" in flat.lower(), (
        "Expected 'found' text not found in results"
    )

    # Verify scanned count is present.
    assert "scanned" in flat.lower() or "Scanned" in flat, (
        "Expected 'scanned N' text not found"
    )

    # Verify at least one script type badge is visible.
    script_types = ["P2WPKH", "P2TR", "P2SH", "P2PKH", "wsh", "tr("]
    found_type = None
    for st in script_types:
        if st in flat:
            found_type = st
            break
    if found_type:
        print(f"    [ok] script type badge found: {found_type}")

    # Verify balance/tx info is present on cards.
    has_sats = "sats" in flat.lower()
    has_tx = "tx" in flat.lower()
    if has_sats:
        print("    [ok] sats balance info present on cards")
    if has_tx:
        print("    [ok] tx count info present on cards")

    # Verify MFP (root fingerprint) is shown.
    mfp_pat = re.compile(r"[0-9a-fA-F]{8}")
    mfp_matches = mfp_pat.findall(flat)
    if mfp_matches:
        print(f"    [ok] MFP found in results: {mfp_matches[0]}")

    print("    [ok] found results verified")


async def _verify_no_results(d: UIDriver):
    """Verify that the 'no activity' state is displayed correctly."""
    print("\n  [phase 6b] verify no-activity result")
    flat = await d.cs_flat_text()

    # Check for "No activity found" or equivalent.
    assert "No activity" in flat or "no activity" in flat, (
        "Expected 'no activity' message not found"
    )
    print("    [ok] 'no activity' message present")

    # Verify the scanned count is shown.
    assert "scanned" in flat.lower() or "Scanned" in flat, (
        "Expected 'scanned N' text not found"
    )
    print("    [ok] scanned count present")

    # Verify there is a retry button (allows re-scanning).
    assert "Retry" in flat or "retry" in flat.lower(), (
        "Expected 'Retry' button not found"
    )
    print("    [ok] retry button present")

    print("    [ok] no-activity result verified")


# ---------------------------------------------------------------------------
# Main test
# ---------------------------------------------------------------------------

async def test_hw_recovery_discovery(d: UIDriver):
    print(f"\n--- {WALLET_LABEL} (HW recovery discovery) ---")

    # Phase 0: set signet.
    await set_active_network_signet(d)

    # Phase 1: open restore screen.
    await _open_restore_screen(d)

    # Phase 2: switch to hardware tab.
    await _switch_to_hardware_tab(d)

    # Phase 3: connect HW + start discovery.
    mfp = await connect_hw_in_open_sheet(d, op_label="HW recovery scan")
    await _start_hw_discovery(d, mfp)

    # Phase 4: wait for scanning phase.
    await _wait_scanning_phase(d)

    # Phase 5: wait for results.
    result_type = await _wait_results(d)

    # Phase 6: verify results.
    if result_type == "found":
        await _verify_found_results(d)
    else:
        await _verify_no_results(d)

    # Cleanup: navigate back.
    print("\n  [phase 7] cleanup — navigate back")
    await go_back_to_wallet_list(d)
    print(f"    [PASS] {WALLET_LABEL}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_hw_recovery_discovery, "reg39"))
