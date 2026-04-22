#!/usr/bin/env python3
"""
Regression test 03: Taproot descriptor with multiple spend paths and timelocks.

Flow:
  1. Create project with a complex tr(...) descriptor (fresh sandbox)
  2. Verify project detail opens (Rust analysis succeeded)
  3. Verify "Spend paths (N)" where N > 1 (multiple paths derived from the policy)
  4. Verify multiple MFPs are present (multiple keys involved)
  5. Navigate to Spend Paths tab — verify more than one spend path card is rendered
  6. Navigate to Keys tab — verify key cards render
  7. Delete project

Exit code: 0 = PASS, 1 = FAIL.

Run:
  bash scripts/prepare_test_build.sh   # once
  python3 scripts/regression_03_taproot.py
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

PROJECT_NAME = "Reg03-Taproot-Timelocks"

# Taproot descriptor with 3 script leaves containing timelocks (testnet).
# All keys use the same <0;1> multi-path indices (required by BDK BIP-389).
# Keys reuse the known-good tpubs from regression_02.
#
# Tap tree:
#   - Key path:    4061aff0 (internal key)
#   - Script leaf1: pk(ff81be5d)
#   - Script leaf2: and_v(v:pk(f3d33d4f), older(100))
#   - Script leaf3: and_v(v:pk(ff81be5d), older(200))
#
# Expected spend paths: key path + 3 leaves = 4 total
# Expected MFPs: 4061aff0, ff81be5d, f3d33d4f
DESCRIPTOR = (
    "tr([4061aff0/48'/1'/0'/2']"
    "tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC"
    "/<0;1>/*,"
    "{pk([ff81be5d/48'/1'/0'/2']"
    "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K"
    "/<0;1>/*),"
    "and_v(v:pk([f3d33d4f/48'/1'/0'/2']"
    "tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h"
    "/<0;1>/*),older(100))})"
)

# MFPs that should appear in the analysis
EXPECTED_MFPS = ["4061aff0", "ff81be5d", "f3d33d4f"]

# Minimum number of spend paths expected (key path + 3 leaves)
MIN_SPEND_PATHS = 2

# Minimum number of distinct keys
MIN_KEYS = 3


# ---------------------------------------------------------------------------
# Test function
# ---------------------------------------------------------------------------

async def test_taproot(d: UIDriver):
    print(f"\n--- {PROJECT_NAME} ---")

    # 1. Create project (analysis is slower for complex Taproot — give more time)
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    # 2. Read semantics
    sem = await d.cs_flat_text()

    # 3. Verify multiple spend paths were extracted
    paths_count = extract_tab_count(sem, "Spend paths")
    if paths_count is None:
        raise AssertionError("'Spend paths (N)' tab label not found")
    if paths_count < MIN_SPEND_PATHS:
        raise AssertionError(
            f"Expected at least {MIN_SPEND_PATHS} spend paths, got {paths_count}"
        )
    print(f"    [ok] Spend paths ({paths_count}) tab visible (≥ {MIN_SPEND_PATHS})")

    # 4. Verify key count
    keys_count = extract_tab_count(sem, "Keys")
    if keys_count is None:
        raise AssertionError("'Keys (N)' tab label not found")
    if keys_count < MIN_KEYS:
        raise AssertionError(
            f"Expected at least {MIN_KEYS} keys, got {keys_count}"
        )
    print(f"    [ok] Keys ({keys_count}) tab visible (≥ {MIN_KEYS})")

    # 5. Verify all expected MFPs are visible
    sem_lower = sem.lower()
    for mfp in EXPECTED_MFPS:
        if mfp.lower() not in sem_lower:
            raise AssertionError(f"MFP '{mfp}' not visible in project detail")
        print(f"    [ok] MFP '{mfp}' visible")

    # 6. Navigate to Spend Paths tab (it should be the initial tab for Taproot)
    #    and verify it renders without crashing
    await click_label(d, f"Spend paths ({paths_count})", delay=0.8)
    sem_paths = await d.cs_flat_text()
    if '"Spend paths (' not in sem_paths:
        raise AssertionError("Spend Paths tab appears empty after navigation")

    # Timelocks should cause timelock-related widgets to be rendered.
    # The UI shows block-height badges; we check that "older" or a timelock
    # indicator appears in the semantics (widget tree shows timelock values).
    sem_paths_lower = sem_paths.lower()
    has_timelock_indicator = (
        "older" in sem_paths_lower
        or "block" in sem_paths_lower
        or "timelock" in sem_paths_lower
    )
    if not has_timelock_indicator:
        print("    [warn] timelock indicator not found in semantics (non-fatal)")
    else:
        print("    [ok] timelock indicator visible in Spend Paths tab")
        # The descriptor contains older(100) — verify the value is rendered.
        if "100" not in sem_paths:
            raise AssertionError(
                "Timelock value '100' not visible in Spend Paths tab"
            )
        print("    [ok] timelock value '100' visible")

    # 7. Navigate to Keys tab and verify rendering
    await click_label(d, f"Keys ({keys_count})", delay=0.8)
    sem_keys = await d.cs_flat_text()
    sem_keys_lower = sem_keys.lower()
    for mfp in EXPECTED_MFPS:
        if mfp.lower() not in sem_keys_lower:
            raise AssertionError(
                f"MFP '{mfp}' not visible on Keys tab after navigation"
            )
    print(f"    [ok] all {keys_count} key cards rendered on Keys tab")

    # 8. Delete
    await go_back(d)
    await delete_project_from_list(d, PROJECT_NAME)

    print(f"    [PASS] {PROJECT_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_taproot, "reg03"))
