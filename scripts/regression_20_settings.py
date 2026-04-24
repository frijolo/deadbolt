#!/usr/bin/env python3
"""
Regression test 20: Settings screen — all automatable preferences.

Verifies every preference that can be tested without hardware or camera:
  • Theme dropdown       (Appearance)      : System default → Dark → System default
  • Language dropdown    (Appearance)      : English → Español → English
  • Active Network       (Defaults)        : Testnet → Signet → Testnet
  • Inheritance timelock (Defaults)        : 144 → 288 → 144  blocks
  • Min fee rate         (Transactions)    : 0.1 → 2.5 → 0.1  sat/vB
  • Fiat toggle          (Transactions)    : OFF → ON → OFF
  • Tor toggle           (Connectivity)    : OFF → ON → OFF
  • Electrum Testnet URL (Connectivity)    : default → custom → empty → restore
  • Explorer Testnet URL (Connectivity)    : default → custom → empty → restore

Each change is verified against the SharedPreferences JSON file directly,
not just through the UI.

Phase order follows the visual top-to-bottom layout of Settings so scrolling
is always downward.  Language is restored to English immediately after the
Español switch so that all subsequent phases find English labels.

Gaps covered:
  - Settings: Theme dropdown
  - Settings: Language dropdown
  - Settings: Active Network dropdown via Settings screen
  - Settings: Inheritance timelock threshold edit + restore
  - Settings: Min fee rate edit + restore
  - Settings: Fiat toggle enable/disable
  - Settings: Tor toggle enable/disable
  - Settings: Electrum URL edit + restore via button
  - Settings: Block Explorer URL edit + restore via button
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

CUSTOM_TESTNET_ELECTRUM  = "ssl://test-node.example.com:50002"
DEFAULT_TESTNET_ELECTRUM = "ssl://electrum.blockstream.info:60002"

CUSTOM_TESTNET_EXPLORER  = "https://custom-explorer.example.com/testnet"
DEFAULT_TESTNET_EXPLORER = "https://mempool.space/testnet"

MIN_FEE_LABEL            = "Minimum fee rate (sat/vB)"
TIMELOCK_LABEL           = "Inheritance timelock threshold"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_prefs() -> dict:
    try:
        return json.loads(PREFS_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def assert_pref(key: str, expected, label: str = ""):
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
# Phase 2: Theme dropdown  (Appearance section — top of screen)
# ---------------------------------------------------------------------------

async def phase_theme(d: UIDriver) -> None:
    print("\n  [phase 2] theme: System default → Dark → System default")

    await click_label(d, "System default", delay=0.4)
    await wait_for(d, '"Dark"', "theme dropdown opened", retries=10, delay=0.4)
    await click_label(d, "Dark", delay=0.3)
    await asyncio.sleep(0.5)
    assert_pref("appTheme", "dark", "after selecting Dark")
    print("    [ok] theme set to Dark")

    await click_label(d, "Dark", delay=0.4)
    await wait_for(d, '"System default"', "theme dropdown opened for restore",
                   retries=10, delay=0.4)
    await click_label(d, "System default", delay=0.3)
    await asyncio.sleep(0.5)
    assert_pref("appTheme", "system", "after restoring to System default")
    print("    [ok] theme restored to System default")


# ---------------------------------------------------------------------------
# Phase 3: Language dropdown  (Appearance section)
# ---------------------------------------------------------------------------

async def phase_language(d: UIDriver) -> None:
    print("\n  [phase 3] language: English → Español → English")

    await click_label(d, "English", delay=0.4)
    await wait_for(d, '"Español"', "language dropdown opened", retries=10, delay=0.4)
    await click_label(d, "Español", delay=0.3)
    await asyncio.sleep(0.8)
    assert_pref("locale", "es", "after selecting Español")
    print("    [ok] locale set to es — restoring immediately")

    await click_label(d, "Español", delay=0.4)
    await wait_for(d, '"English"', "language dropdown opened for restore",
                   retries=10, delay=0.4)
    await click_label(d, "English", delay=0.3)
    await asyncio.sleep(0.8)
    assert_pref("locale", "en", "after restoring to English")

    # Wait for full English rebuild before any subsequent phase uses English labels.
    await wait_for(d, '"Active Network"', "English UI fully restored",
                   retries=12, delay=0.5)
    print("    [ok] English UI restored")


# ---------------------------------------------------------------------------
# Phase 4: Active Network dropdown  (Defaults section)
# ---------------------------------------------------------------------------

async def phase_active_network(d: UIDriver) -> None:
    print("\n  [phase 4] active network: Testnet → Signet → Testnet")

    await click_label(d, "Testnet", delay=0.4)
    await wait_for(d, '"Signet"', "network dropdown opened", retries=10, delay=0.4)
    await click_label(d, "Signet", delay=0.3)
    await asyncio.sleep(0.5)
    assert_pref("defaultNetwork", "signet", "after selecting Signet")
    print("    [ok] Active Network set to Signet")

    await click_label(d, "Signet", delay=0.4)
    await wait_for(d, '"Testnet"', "network dropdown opened for restore",
                   retries=10, delay=0.4)
    await click_label(d, "Testnet", delay=0.3)
    await asyncio.sleep(0.5)
    assert_pref("defaultNetwork", "testnet", "after restoring to Testnet")
    print("    [ok] Active Network restored to Testnet")


# ---------------------------------------------------------------------------
# Phase 5: Inheritance timelock threshold  (Defaults section)
# ---------------------------------------------------------------------------

async def phase_inheritance_timelock(d: UIDriver) -> None:
    print("\n  [phase 5] inheritance timelock: 144 → 288 → 144 blocks")

    # Wait for any lingering dropdown overlay from phase 4 to fully close.
    await wait_for(d, TIMELOCK_LABEL, "timelock field visible",
                   retries=10, delay=0.4)

    await fill_field(d, TIMELOCK_LABEL, "288")
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("inheritanceMinTimelock", 288, "timelock set to 288")
    print("    [ok] timelock set to 288 blocks")

    await fill_field(d, TIMELOCK_LABEL, "144")
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("inheritanceMinTimelock", 144, "timelock restored to 144")
    print("    [ok] timelock restored to 144 blocks")


# ---------------------------------------------------------------------------
# Phase 6: Min fee rate  (Transactions section)
# ---------------------------------------------------------------------------

async def phase_min_fee_rate(d: UIDriver) -> None:
    print("\n  [phase 6] min fee rate: 0.1 → 2.5 → 0.1 sat/vB")

    await fill_field(d, MIN_FEE_LABEL, "2.5")
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("minFeeRate", 2.5, "fee rate set to 2.5")
    print("    [ok] fee rate set to 2.5")

    await fill_field(d, MIN_FEE_LABEL, "0.1")
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("minFeeRate", 0.1, "fee rate restored to 0.1")
    print("    [ok] fee rate restored to 0.1")


# ---------------------------------------------------------------------------
# Phase 7: Fiat toggle  (Transactions section)
# ---------------------------------------------------------------------------

async def phase_fiat_toggle(d: UIDriver) -> None:
    print("\n  [phase 7] fiat toggle: OFF → ON → OFF")

    flat = await d.cs_flat_text()
    if "Price provider" in flat:
        raise AssertionError("Expected fiat OFF at start, but 'Price provider' is visible")
    print("    [ok] fiat initially OFF")

    await click_label(d, "Fiat Values")
    await wait_for(d, "Price provider", "provider row appeared", retries=10, delay=0.4)
    await asyncio.sleep(0.4)
    assert_pref("fiatEnabled", True, "after toggle ON")
    print("    [ok] fiat toggled ON")

    await click_label(d, "Fiat Values")
    await wait_absent(d, "Price provider", "provider row gone", retries=10, delay=0.4)
    await asyncio.sleep(0.4)
    assert_pref("fiatEnabled", False, "after toggle OFF")
    print("    [ok] fiat toggled OFF")


# ---------------------------------------------------------------------------
# Phase 8: Tor toggle  (Connectivity section)
# ---------------------------------------------------------------------------

async def phase_tor_toggle(d: UIDriver) -> None:
    print("\n  [phase 8] tor toggle: OFF → ON → OFF")

    await click_label(d, "Use Tor")
    await asyncio.sleep(0.5)
    assert_pref("torEnabled", True, "after toggle ON")
    print("    [ok] Tor toggled ON")

    await click_label(d, "Use Tor")
    await asyncio.sleep(0.5)
    assert_pref("torEnabled", False, "after toggle OFF")
    print("    [ok] Tor toggled OFF")


# ---------------------------------------------------------------------------
# Phase 9: Electrum Testnet URL  (Connectivity section)
# ---------------------------------------------------------------------------

async def phase_electrum_url(d: UIDriver) -> None:
    print("\n  [phase 9] Electrum Testnet URL: default → custom → empty → restore")

    await click_label(d, "Electrum Servers")
    await wait_for(d, "Testnet Electrum", "Electrum section expanded",
                   retries=10, delay=0.5)
    print("    [ok] Electrum Servers expanded")

    await fill_field(d, "Testnet Electrum", CUSTOM_TESTNET_ELECTRUM)
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("electrumTestnet", CUSTOM_TESTNET_ELECTRUM, "custom URL saved")

    await fill_field(d, "Testnet Electrum", "")
    d.key("Return")
    await wait_for(d, "Restore defaults", "restore button visible",
                   retries=10, delay=0.4)
    await asyncio.sleep(0.4)
    assert_pref("electrumTestnet", "", "empty URL saved")

    await click_tooltip(d, "Restore defaults")
    await wait_absent(d, "Restore defaults", "restore button gone",
                      retries=10, delay=0.4)
    await asyncio.sleep(0.5)
    assert_pref("electrumTestnet", DEFAULT_TESTNET_ELECTRUM, "default URL restored")
    print("    [ok] Electrum Testnet URL restored to default")


# ---------------------------------------------------------------------------
# Phase 10: Explorer Testnet URL  (Connectivity section)
# ---------------------------------------------------------------------------

async def phase_explorer_url(d: UIDriver) -> None:
    print("\n  [phase 10] Explorer Testnet URL: default → custom → empty → restore")

    await click_label(d, "Block Explorer")
    await wait_for(d, "Testnet Explorer", "Explorer section expanded",
                   retries=10, delay=0.5)
    print("    [ok] Block Explorer expanded")

    await fill_field(d, "Testnet Explorer", CUSTOM_TESTNET_EXPLORER)
    d.key("Return")
    await asyncio.sleep(0.5)
    assert_pref("explorerTestnet", CUSTOM_TESTNET_EXPLORER, "custom URL saved")

    await fill_field(d, "Testnet Explorer", "")
    d.key("Return")
    await wait_for(d, "Restore defaults", "restore button visible",
                   retries=10, delay=0.4)
    await asyncio.sleep(0.4)
    assert_pref("explorerTestnet", "", "empty URL saved")

    await click_tooltip(d, "Restore defaults")
    await wait_absent(d, "Restore defaults", "restore button gone",
                      retries=10, delay=0.4)
    await asyncio.sleep(0.5)
    assert_pref("explorerTestnet", DEFAULT_TESTNET_EXPLORER, "default URL restored")
    print("    [ok] Explorer Testnet URL restored to default")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_settings(d: UIDriver) -> None:
    print("\n--- reg20: Settings (all automatable preferences) ---")

    await phase_navigate(d)
    await phase_theme(d)
    await phase_language(d)
    await phase_active_network(d)
    await phase_inheritance_timelock(d)
    await phase_min_fee_rate(d)
    await phase_fiat_toggle(d)
    await phase_tor_toggle(d)
    await phase_electrum_url(d)
    await phase_explorer_url(d)

    print("\n    [PASS] reg20 Settings")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_settings, "reg20"))
