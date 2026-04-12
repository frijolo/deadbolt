#!/usr/bin/env python3
"""
QR camera scan test — Compact SeedQR via Seed recovery flow.

Path: Wallets → New → Recover Wallet → Seed tab → Scan QR code button.
Success: the mnemonic field is populated (word counter shows "N / 24" with N ≥ 12).

NOT fully automated — requires a physical Compact SeedQR in front of the camera.

Exit code: 0 = 24 words detected and confirmed in the mnemonic field, 1 = failure.

Run:
  bash scripts/prepare_test_build.sh   # once per code change
  DISPLAY=:0 python3 scripts/test_qr_camera.py
"""

import asyncio
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                    # noqa: E402
from regression_helpers import (                 # noqa: E402
    wait_for, wait_absent,
    dismiss_startup_dialogs,
    navigate_wallets,
    click_label,
    click_tooltip,
)

SCAN_TIMEOUT = 90   # seconds to wait for a QR detection
MIN_WORDS    = 12   # accept any valid BIP-39 word count


async def main() -> int:
    d = UIDriver(sandbox=True)
    try:
        await d.launch()
        await dismiss_startup_dialogs(d)

        # ── 1. Wallets → New → Recover Wallet ──────────────────────────────
        await navigate_wallets(d)
        await click_tooltip(d, "New")
        await wait_for(d, "Recover Wallet", "Bottom sheet opened")
        await click_label(d, "Recover Wallet", delay=0.5)
        await wait_for(d, '"Recover Wallet"', "Recover Wallet screen opened")
        print("    [ok] Recover Wallet screen open")

        # ── 2. Seed tab ─────────────────────────────────────────────────────
        await click_label(d, "Seed", delay=0.5)
        await wait_for(d, "Seed phrase", "Seed tab active")
        print("    [ok] Seed tab active")

        # ── 3. Open QR scanner ──────────────────────────────────────────────
        await click_tooltip(d, "Scan QR code")
        await wait_for(d, '"Scan QR code"', "QR scanner screen opened",
                       retries=12, delay=0.5)
        print("    [ok] QR scanner screen open")

        # ── 4. Wait for the scanner to auto-close (happens when QR is decoded) ─
        print()
        print("  *** POINT THE SEED QR AT THE CAMERA ***")
        print(f"  The scanner will close automatically when a QR is decoded.")
        print(f"  Timeout: {SCAN_TIMEOUT}s")
        print()

        deadline = time.monotonic() + SCAN_TIMEOUT

        while time.monotonic() < deadline:
            await asyncio.sleep(0.5)

            # Check whether the scanner screen is still open.
            sem = await d.semantics_tree()
            if '"Scan QR code"' not in sem:
                print("    [ok] Scanner closed (QR detected)")
                break
        else:
            print(f"\n  FAIL — Scanner still open after {SCAN_TIMEOUT}s")
            print("  (No QR detected or camera not accessible)")
            return 1

        # ── 6. Verify word count in mnemonic field ──────────────────────────
        # The MnemonicEntryField shows "$wordCount / $targetCount" in bold.
        # For 24-word compact SeedQR this becomes "24 / 24".
        # We accept any complete BIP-39 word count (12, 15, 18, 21, 24).
        await asyncio.sleep(0.5)
        sem = await d.semantics_tree()

        found_count = None
        for n in (24, 12, 15, 18, 21):
            if f"{n} / {n}" in sem:
                found_count = n
                break

        if found_count is not None:
            print(f"\n  PASS — mnemonic field populated: {found_count} / {found_count} words")
            return 0

        # If word count label not found, check that the field has some content
        # by looking for the Scan button still present on the seed tab.
        # Dump a snippet for diagnosis.
        labels = [ln.strip() for ln in sem.splitlines()
                  if "label:" in ln or "value:" in ln]
        print("\n  FAIL — scanner closed but word count not found in semantics")
        print("  Visible labels/values:", labels[:30])
        return 1

    except Exception as exc:
        print(f"\n[ERROR] {exc}")
        raise
    finally:
        await d.close()


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
