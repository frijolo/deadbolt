#!/usr/bin/env python3
"""
Regression test 20: Settings screen — min fee rate, fiat toggle, Electrum URL.

Verifies that settings changes are persisted to SharedPreferences by reading
the JSON file directly after each UI interaction, not just trusting the UI.

Phases are ordered so scrolling is always downward (no scroll-back needed):
  1.  Navigate to Settings.
  2.  Change min fee rate to 2.5 → press Return
                      → file: flutter.minFeeRate == 2.5
  3.  Restore min fee rate to 0.1 → press Return
                      → file: flutter.minFeeRate == 0.1
  4.  Fiat toggle ON  → UI shows "Price provider" row
                      → file: flutter.fiatEnabled == True
  5.  Fiat toggle OFF → "Price provider" row disappears
                      → file: flutter.fiatEnabled == False
  6.  Expand "Electrum Servers" (scroll down).
  7.  Set Testnet Electrum to a custom URL → press Return
                      → file: flutter.electrumTestnet == custom_url
  8.  Clear Testnet Electrum → press Return → "Restore defaults" button appears.
      Click restore   → "Restore defaults" disappears
                      → file: flutter.electrumTestnet == default_testnet_url

Notes:
  - "Testnet Electrum" is used (not Signet) because after the section expands
    only the first three network fields are in the viewport; Signet and Regtest
    carry the isHidden flag and clicks would miss.

Gaps covered:
  - Settings: Min fee rate field edit (first automation)
  - Settings: Fiat toggle enable/disable (first automation)
  - Settings: Electrum URL edit + restore via button (first automation)
  - All verified against SharedPreferences JSON, not just UI

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_20_settings.py
"""

import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    navigate_settings,
    click_label, click_tooltip, fill_field,
    run_regression,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PREFS_FILE = Path(
    "/tmp/deadbolt_test_sandbox/data/com.deadbolt.deadbolt/shared_preferences.json"
)

CUSTOM_TESTNET_URL   = "ssl://test-node.example.com:50002"
DEFAULT_TESTNET_URL  = "ssl://electrum.blockstream.info:60002"
MIN_FEE_LABEL        = "Minimum fee rate (sat/vB)"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_prefs() -> dict:
    """Read the current SharedPreferences JSON from the sandbox."""
    try:
        return json.loads(PREFS_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def assert_pref(key: str, expected, label: str = ""):
    """Assert a flutter.* key has the expected value in SharedPreferences."""
    prefs = read_prefs()
    full_key = f"flutter.{key}"
    actual = prefs.get(full_key)
    tag = f" ({label})" if label else ""
    if actual != expected:
        raise AssertionError(
            f"Pref '{full_key}'{tag}: expected {expected!r}, got {actual!r}\n"
            f"  full prefs: {prefs}"
        )
    print(f"    [pref] flutter.{key} == {expected!r}  ✓")


# ---------------------------------------------------------------------------
# Phase 1: Navigate to Settings
# ---------------------------------------------------------------------------

async def phase_navigate(d: UIDriver) -> None:
    print("\n  [phase 1] navigate to Settings")
    await navigate_settings(d)
    await wait_for(d, '"Settings"', "Settings AppBar visible")


# ---------------------------------------------------------------------------
# Phase 2: Min fee rate
# ---------------------------------------------------------------------------

async def phase_min_fee_rate(d: UIDriver) -> None:
    print("\n  [phase 2] min fee rate edit + restore")

    await fill_field(d, MIN_FEE_LABEL, "2.5")
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("minFeeRate", 2.5, "fee rate set to 2.5")

    await fill_field(d, MIN_FEE_LABEL, "0.1")
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("minFeeRate", 0.1, "fee rate restored to 0.1")


# ---------------------------------------------------------------------------
# Phase 3: Fiat toggle
# ---------------------------------------------------------------------------

async def phase_fiat_toggle(d: UIDriver) -> None:
    print("\n  [phase 3] fiat toggle ON/OFF")

    # Sandbox starts clean — fiat is off by default.
    flat = await d.cs_flat_text()
    if "Price provider" in flat:
        raise AssertionError("Expected fiat OFF at start, but 'Price provider' is visible")
    print("    [ok] fiat initially OFF (no 'Price provider' row)")

    # Toggle ON.
    await click_label(d, "Fiat Values")
    await wait_for(d, "Price provider", "provider row appeared", retries=10, delay=0.4)
    await asyncio.sleep(0.4)
    assert_pref("fiatEnabled", True, "after toggle ON")

    # Toggle OFF.
    await click_label(d, "Fiat Values")
    await wait_absent(d, "Price provider", "provider row gone", retries=10, delay=0.4)
    await asyncio.sleep(0.4)
    assert_pref("fiatEnabled", False, "after toggle OFF")


# ---------------------------------------------------------------------------
# Phase 4: Electrum Testnet URL  (scroll down — always last)
# ---------------------------------------------------------------------------

async def phase_electrum_url(d: UIDriver) -> None:
    print("\n  [phase 4] Electrum Testnet URL edit + restore")

    # Expand the Electrum Servers ExpansionTile (click_label auto-scrolls).
    await click_label(d, "Electrum Servers")
    await wait_for(d, "Testnet Electrum", "Electrum section expanded",
                   retries=10, delay=0.5)
    print("    [ok] Electrum Servers expanded")

    # Set a custom URL.
    await fill_field(d, "Testnet Electrum", CUSTOM_TESTNET_URL)
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("electrumTestnet", CUSTOM_TESTNET_URL, "custom URL saved")

    # Clear the URL — the "Restore defaults" button should appear.
    await fill_field(d, "Testnet Electrum", "")
    d.key("Return")
    await wait_for(d, "Restore defaults", "restore button visible",
                   retries=10, delay=0.4)
    await asyncio.sleep(0.4)
    assert_pref("electrumTestnet", "", "empty URL saved")

    # Click restore → field goes back to the default URL.
    await click_tooltip(d, "Restore defaults")
    await wait_absent(d, "Restore defaults", "restore button gone",
                      retries=10, delay=0.4)
    await asyncio.sleep(0.5)
    assert_pref("electrumTestnet", DEFAULT_TESTNET_URL, "default URL restored")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_settings(d: UIDriver) -> None:
    print("\n--- reg20: Settings (min fee rate + fiat toggle + electrum URL) ---")

    await phase_navigate(d)
    await phase_min_fee_rate(d)
    await phase_fiat_toggle(d)
    await phase_electrum_url(d)

    print("\n    [PASS] reg20 Settings")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_settings, "reg20"))
