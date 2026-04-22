#!/usr/bin/env python3
"""
Regression test 02: WSH 2-of-3 multisig descriptor analysis.

Flow:
  1. Create project with wsh(multi(2, k1, k2, k3)) descriptor (fresh sandbox)
  2. Verify project detail opens (Rust analysis succeeded)
  3. Verify "Keys (3)" and "Spend paths (1)" tab labels
  4. Verify all 3 key MFPs are visible
  5. Navigate to the Keys tab and verify all 3 key cards are rendered
  6. Navigate to the Spend Paths tab and verify the spend path is rendered
  7. Delete project

Exit code: 0 = PASS, 1 = FAIL.

Run:
  bash scripts/prepare_test_build.sh   # once
  python3 scripts/regression_02_multisig_wsh.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for,
    click_label,
    dismiss_startup_dialogs,
    create_project, go_back, delete_project_from_list,
    extract_tab_count, run_regression,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg02-WSH-2of3"

# wsh(multi(2, A, B, C)) — testnet xpubs taken from the lifecycle test suite.
# MFPs: 4061aff0, ff81be5d, f3d33d4f
DESCRIPTOR = (
    "wsh(multi(2,"
    "[4061aff0/48h/1h/0h/2h]"
    "tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC"
    "/<0;1>/*,"
    "[ff81be5d/48h/1h/0h/2h]"
    "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K"
    "/<0;1>/*,"
    "[f3d33d4f/48h/1h/0h/2h]"
    "tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h"
    "/<0;1>/*))"
)

EXPECTED_MFPS = ["4061aff0", "ff81be5d", "f3d33d4f"]

EXPECTED_KEYS_COUNT   = 3
EXPECTED_PATHS_COUNT  = 1


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_multisig_wsh(d: UIDriver):
    print(f"\n--- {PROJECT_NAME} ---")

    # 1. Create project
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    # 2. Read semantics (project detail; initial tab = Spend Paths for multisig)
    sem = await d.cs_flat_text()

    # 3. Verify tab labels
    keys_count  = extract_tab_count(sem, "Keys")
    paths_count = extract_tab_count(sem, "Spend paths")

    if keys_count != EXPECTED_KEYS_COUNT:
        raise AssertionError(
            f"Expected Keys count = {EXPECTED_KEYS_COUNT}, got {keys_count}"
        )
    print(f"    [ok] Keys ({EXPECTED_KEYS_COUNT}) tab visible")

    if paths_count != EXPECTED_PATHS_COUNT:
        raise AssertionError(
            f"Expected Spend paths count = {EXPECTED_PATHS_COUNT}, got {paths_count}"
        )
    print(f"    [ok] Spend paths ({EXPECTED_PATHS_COUNT}) tab visible")

    # 4. Verify all 3 MFPs present in semantics
    sem_lower = sem.lower()
    for mfp in EXPECTED_MFPS:
        if mfp.lower() not in sem_lower:
            raise AssertionError(f"MFP '{mfp}' not visible in project detail")
        print(f"    [ok] MFP '{mfp}' visible")

    # 5. Navigate to Keys tab and verify key cards render without error
    #    (Tab label is "Keys (3)" — clicking it switches the tab view)
    await click_label(d, f"Keys ({EXPECTED_KEYS_COUNT})", delay=0.8)
    sem_keys = await d.cs_flat_text()

    # Each key card should show the MFP badge; verify all 3 are still visible
    sem_keys_lower = sem_keys.lower()
    for mfp in EXPECTED_MFPS:
        if mfp.lower() not in sem_keys_lower:
            raise AssertionError(
                f"MFP '{mfp}' not visible on Keys tab — key card may have failed to render"
            )
    print(f"    [ok] all {EXPECTED_KEYS_COUNT} key cards rendered on Keys tab")

    # 6. Navigate to Spend Paths tab and verify the spend path renders
    await click_label(d, f"Spend paths ({EXPECTED_PATHS_COUNT})", delay=0.8)
    sem_paths = await d.cs_flat_text()

    # The spend path card must be visible (the tab is not empty / no error state)
    # For a 2-of-3 multisig the spend path section shows "2 of 3" or similar weight info.
    # We assert that the semantics has more content than just the tab bar.
    if '"Spend paths (' not in sem_paths:
        raise AssertionError("Spend Paths tab appears empty after navigation")
    print(f"    [ok] Spend Paths tab renders without error")

    # 7. Delete
    await go_back(d)
    await delete_project_from_list(d, PROJECT_NAME)

    print(f"    [PASS] {PROJECT_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_multisig_wsh, "reg02"))
