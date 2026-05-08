#!/usr/bin/env python3
"""
Regression test 01: singlesig descriptor types (pkh, wpkh, sh(wpkh)).

For each descriptor type:
  1. Create project from a fresh sandbox
  2. Verify project detail opens (Rust analysis succeeded)
  3. Verify tab labels show exactly "Keys (1)" and "Spend paths (1)"
  4. Verify the key's MFP is visible in the detail
  5. Go back to the project list and delete the project

Exit code: 0 = all PASS, 1 = one or more FAIL.

Run:
  bash scripts/prepare_test_build.sh   # once, before first test run
  python3 scripts/regression_01_singlesig.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for,
    dismiss_startup_dialogs,
    create_project, go_back, delete_project_from_list,
    extract_tab_count,
    run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

# Each entry: (project_name, expected_mfp_substr, descriptor)
CASES = [
    (
        "Reg01-PKH",
        "73c5da0a",
        (
            "pkh([73c5da0a/44h/1h/0h]"
            "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
            "/<0;1>/*)#0x5u8d5c"
        ),
    ),
    (
        "Reg01-WPKH",
        "5436d724",
        (
            "wpkh([5436d724/84h/1h/0h]"
            "tpubDCWivZp6qaqCALCt8MyLqAb3awnWm4hfbBPjdZqirYFXYeZ5YsfbWVaPacULZTGtK1RPBSZ92UWNjnhL4fB9UVrF2FjgW8cgmBjxPBmB4iB"
            "/<0;1>/*)"
        ),
    ),
    (
        "Reg01-SH-WPKH",
        "73c5da0a",
        (
            "sh(wpkh([73c5da0a/49h/1h/0h]"
            "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
            "/<0;1>/*))"
        ),
    ),
]


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_singlesig(d: UIDriver):
    """Run all singlesig sub-tests. Raises on first failure."""
    total = len(CASES)
    failed: list[str] = []

    for name, mfp, desc in CASES:
        print(f"\n--- {name} ---")

        # 1. Create project (navigates to project detail on success)
        await create_project(d, name, desc)

        # 2. Read semantics once (project detail is now open)
        sem = await d.cs_flat_text()

        # 3. Verify tab labels — both must show count = 1
        keys_count = extract_tab_count(sem, "Keys")
        paths_count = extract_tab_count(sem, "Spend paths")

        if keys_count is None:
            raise AssertionError(f"'Keys (N)' tab label not found for {name}")
        if keys_count != 1:
            raise AssertionError(
                f"Expected Keys count = 1, got {keys_count} for {name}"
            )
        print(f"    [ok] Keys (1) tab visible")

        if paths_count is None:
            raise AssertionError(f"'Spend paths (N)' tab label not found for {name}")
        if paths_count != 1:
            raise AssertionError(
                f"Expected Spend paths count = 1, got {paths_count} for {name}"
            )
        print(f"    [ok] Spend paths (1) tab visible")

        # 4. Verify MFP visible (appears in key card as uppercase or lowercase)
        sem_lower = sem.lower()
        if mfp.lower() not in sem_lower:
            raise AssertionError(
                f"MFP '{mfp}' not visible in project detail for {name}"
            )
        print(f"    [ok] MFP '{mfp}' visible")

        # 5. Delete (go back → project list → delete via card menu)
        await go_back(d)
        await delete_project_from_list(d, name)

        print(f"    [PASS] {name}")

    if failed:
        raise AssertionError(f"{len(failed)}/{total} sub-tests failed: {failed}")
    print(f"\n{'='*50}")
    print(f"[RESULT] PASS — all {total} singlesig descriptor types OK")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_singlesig, "reg01"))
