#!/usr/bin/env python3
"""Calibrate CSD (client-side decoration) offsets for ui_driver.

Applies the debug mouse overlay, builds the debug binary, launches the app,
clicks at the window center, reads the Flutter-reported coordinates from stdout,
computes the real CSD_X/CSD_Y offsets, saves them to scripts/.calib, then
reverts the overlay.

Run this once after changing GTK theme, monitor setup, or display scaling.
The .calib file is gitignored; normal test runs (demo_singlesig_wallet.py etc.)
load it automatically so they skip live calibration.

Usage:
    python3 scripts/calibrate.py
"""
import asyncio
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SETUP_SCRIPT = Path(__file__).resolve().parent / "debug_overlay_setup.sh"
CALIB_FILE   = Path(__file__).resolve().parent / ".calib"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver  # noqa: E402


async def run():
    # ── 1. Check prerequisites ─────────────────────────────────────────────
    if not SETUP_SCRIPT.exists():
        print("ERROR: scripts/debug_overlay_setup.sh not found.")
        print("  Run: bash scripts/debug_overlay_setup.sh")
        sys.exit(1)

    # ── 2. Apply overlay ───────────────────────────────────────────────────
    print("[calibrate] Applying debug overlay…")
    subprocess.run(["bash", str(SETUP_SCRIPT), "apply"],
                   cwd=PROJECT_ROOT, check=True)

    # ── 3. Build ───────────────────────────────────────────────────────────
    print("[calibrate] Building debug binary…")
    result = subprocess.run(
        ["flutter", "build", "linux", "--debug"],
        cwd=PROJECT_ROOT, capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(result.stderr)
        subprocess.run(["bash", str(SETUP_SCRIPT), "revert"], cwd=PROJECT_ROOT)
        sys.exit(1)

    # ── 4. Launch, calibrate, save ─────────────────────────────────────────
    d = UIDriver(sandbox=False, debug_mouse=False)
    try:
        await d.launch()       # loads defaults since .calib may not exist yet
        await d.calibrate()    # clicks window center, reads [mouse] DOWN, sets csd_x/csd_y
        CALIB_FILE.write_text(f"CSD_X={d.csd_x}\nCSD_Y={d.csd_y}\n")
        print(f"[calibrate] Saved → {CALIB_FILE}")
        print(f"[calibrate] CSD_X={d.csd_x}  CSD_Y={d.csd_y}")
    finally:
        await d.close()

    # ── 5. Revert overlay ──────────────────────────────────────────────────
    subprocess.run(["bash", str(SETUP_SCRIPT), "revert"], cwd=PROJECT_ROOT)
    print("[calibrate] Overlay reverted. Done.")


asyncio.run(run())
