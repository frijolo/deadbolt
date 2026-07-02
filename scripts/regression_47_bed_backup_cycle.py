#!/usr/bin/env python3
"""
Regression test 47: BED backup — full import → verify → export → re-import
→ verify cycle, against a real cross-tool fixture.

`rust/tests/fixtures/bed/wallet.bed` is byte-for-byte identical to the
fixture vendored in semillabitcoin/descriptor-cifrado's own test suite
(verified 2026-07-02) — decrypting it with `xpub.txt` is a genuine
cross-tool interop check, not just a same-crate assumption. This test
exercises that fixture through the real UI (not just `cargo test`) and
makes sure every import in the cycle lands on the *same* wallet by
comparing the first receive and change addresses against values
independently derived from `desc.txt` via `bdk_wallet` (see git history
of this file for the one-off derivation).

Flow:
  1. Set Active Network → Mainnet (the fixture descriptor uses xpub/mainnet
     keys, not tpub).
  2. Wallet list → New → 'From backup' → pick wallet.bed → paste xpub.txt's
     xpub → Unlock. BED files skip the password prompt entirely (decryption
     only needs a public key) and land straight on WalletDetailScreen.
  3. Verify receive_address_0 and change_address_0 match the expected
     values.
  4. Export this wallet again: More options → Export → Descriptor → BED
     backup → save to test_data/reg47_export.bed.
  5. Re-import the freshly exported file (same xpub) into a second wallet.
  6. Verify addresses again — the export/re-import round-trip must
     reproduce the exact same wallet.
  7. Clean up both "Imported BED" wallet cards.

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_47_bed_backup_cycle.py
"""

import asyncio
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver, DISPLAY, PROJECT_ROOT   # noqa: E402
from regression_helpers import (                        # noqa: E402
    wait_for,
    click_label,
    click_tooltip,
    fill_field,
    set_active_network,
    navigate_wallets,
    go_back_to_wallet_list,
    run_regression,
)


# ---------------------------------------------------------------------------
# Test constants
# ---------------------------------------------------------------------------

FIXTURE_DIR = PROJECT_ROOT / "rust" / "tests" / "fixtures" / "bed"
FIXTURE_BED = FIXTURE_DIR / "wallet.bed"
FIXTURE_XPUB = (FIXTURE_DIR / "xpub.txt").read_text().strip()

# wallet_name is not customizable for BED imports (always "Imported BED").
WALLET_NAME = "Imported BED"

EXPORT_FILE = PROJECT_ROOT / "test_data" / "reg47_export.bed"

# Independently derived from desc.txt via bdk_wallet's own descriptor
# derivation (Wallet::create_from_two_path_descriptor, network=Bitcoin,
# peek_address index 0) — the ground truth this test checks the UI against.
EXPECTED_RECEIVE_0 = "bc1ql5upx959k6dws825fxevjfx36ugzm0fluxk7xa597227ce6tevqs8gjf9j"
EXPECTED_CHANGE_0 = "bc1q4ak8s9mvqvk92r8vfd2n9tnnu3z7echaa9jkpwa7d3lhw2976npqwd7pgs"


# ---------------------------------------------------------------------------
# GTK file-dialog helpers (mirrors regression_08/09's pattern)
# ---------------------------------------------------------------------------

def _xdo(*args):
    env = {**os.environ, "DISPLAY": DISPLAY}
    subprocess.run(["xdotool", *args], env=env,
                   stderr=subprocess.DEVNULL, check=False)


def _list_visible_windows() -> set[str]:
    env = {**os.environ, "DISPLAY": DISPLAY}
    try:
        out = subprocess.check_output(
            ["xdotool", "search", "--onlyvisible", "--name", "."],
            env=env, stderr=subprocess.DEVNULL, text=True,
        ).strip()
        return set(out.split()) if out else set()
    except subprocess.CalledProcessError:
        return set()


async def _focus_new_window(pre_wins: set[str], timeout: float, what: str) -> str:
    env = {**os.environ, "DISPLAY": DISPLAY}
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        new_wins = _list_visible_windows() - pre_wins
        if new_wins:
            win_id = list(new_wins)[0]
            print(f"    [gtk] {what} detected: {win_id}")
            subprocess.run(["xdotool", "windowraise", win_id], env=env,
                           stderr=subprocess.DEVNULL)
            subprocess.run(["xdotool", "windowfocus", "--sync", win_id], env=env,
                           stderr=subprocess.DEVNULL)
            await asyncio.sleep(0.5)
            return win_id
        await asyncio.sleep(0.3)
    raise AssertionError(f"{what} did not appear within {timeout}s")


async def _handle_gtk_open_dialog(file_path: Path, pre_wins: set[str], timeout: float = 10.0):
    """GTK open dialog: Ctrl+L → absolute path → Enter selects and closes it."""
    await _focus_new_window(pre_wins, timeout, "file-open dialog")
    _xdo("key", "--clearmodifiers", "ctrl+l")
    await asyncio.sleep(0.4)
    subprocess.run(
        ["xdotool", "type", "--clearmodifiers", "--delay=20", "--", str(file_path.resolve())],
        env={**os.environ, "DISPLAY": DISPLAY}, stderr=subprocess.DEVNULL,
    )
    await asyncio.sleep(0.3)
    _xdo("key", "Return")
    await asyncio.sleep(1.0)
    _xdo("key", "Return")
    await asyncio.sleep(0.5)
    print(f"    [gtk] file path submitted: {file_path.resolve()}")


async def _handle_gtk_save_dialog(save_path: Path, pre_wins: set[str], timeout: float = 15.0):
    """GTK save dialog: Ctrl+L → path without extension → Enter (GTK appends it)."""
    save_path.parent.mkdir(parents=True, exist_ok=True)
    await _focus_new_window(pre_wins, timeout, "file-save dialog")
    _xdo("key", "--clearmodifiers", "ctrl+l")
    await asyncio.sleep(0.4)
    typed_path = save_path.with_suffix("") if save_path.suffix == ".bed" else save_path
    subprocess.run(
        ["xdotool", "type", "--clearmodifiers", "--delay=20", "--", str(typed_path.resolve())],
        env={**os.environ, "DISPLAY": DISPLAY}, stderr=subprocess.DEVNULL,
    )
    await asyncio.sleep(0.3)
    _xdo("key", "Return")
    await asyncio.sleep(1.0)
    _xdo("key", "Return")   # accept "overwrite?" prompt if the file already exists
    await asyncio.sleep(0.5)
    print(f"    [gtk] path submitted: {typed_path.resolve()} (GTK will add .bed)")


# ---------------------------------------------------------------------------
# Import / export phases
# ---------------------------------------------------------------------------

async def _import_bed(d: UIDriver, bed_file: Path):
    """
    Wallet list → New → 'From backup' → pick `bed_file` → paste xpub → Unlock.

    BED files are auto-detected (no password prompt, straight to the xpub
    unlock dialog) — see wallet_list_screen.dart's `_importBackup`.
    """
    print(f"\n  [phase] import {bed_file.name}")
    await navigate_wallets(d)

    pre_wins = _list_visible_windows()
    await click_tooltip(d, "New")
    await wait_for(d, "From backup", "new-wallet bottom sheet")
    await click_label(d, "From backup", delay=0.5)

    await _handle_gtk_open_dialog(bed_file, pre_wins, timeout=10.0)

    await wait_for(
        d, '"Enter xpub to unlock"',
        "xpub unlock dialog visible",
        retries=15, delay=0.8,
    )
    await fill_field(d, "xpub or keyspec", FIXTURE_XPUB)
    await click_label(d, "Unlock", delay=1.0)

    await wait_for(
        d, '"Receive"',
        "wallet detail loaded after BED import",
        retries=30, delay=1.0,
    )
    print("    [ok] wallet detail open after BED import")


async def _verify_addresses(d: UIDriver, phase: str):
    """Check receive_address_0 and change_address_0 against the expected values."""
    print(f"\n  [verify:{phase}] receive + change address #0")
    await click_label(d, "Addresses", delay=1.5)

    sem = await d.cs_flat_text()
    if '"Loading addresses' in sem:
        await wait_for(d, 'receive_address_0', "address loading complete",
                       retries=15, delay=0.8)

    await asyncio.sleep(0.8)
    sem = await d.cs_flat_text()
    if '"Reveal 20 more addresses"' in sem:
        await click_label(d, "Reveal 20 more addresses", delay=1.5)
        await wait_for(d, 'receive_address_0', "addresses revealed", retries=10, delay=0.6)

    await _verify_one_address(d, "receive_address_0", EXPECTED_RECEIVE_0)

    await click_label(d, "Change", delay=1.0)
    sem = await d.cs_flat_text()
    if '"Reveal 20 more addresses"' in sem:
        await click_label(d, "Reveal 20 more addresses", delay=1.5)
        await wait_for(d, 'change_address_0', "change addresses revealed", retries=10, delay=0.6)

    await _verify_one_address(d, "change_address_0", EXPECTED_CHANGE_0)


async def _verify_one_address(d: UIDriver, semantic_label: str, expected: str):
    await wait_for(d, semantic_label, f"{semantic_label} visible", retries=10, delay=0.6)
    rect = await d.cs_find_by_label_part(semantic_label)
    if rect is None:
        raise AssertionError(f"Could not find address tile '{semantic_label}'")
    cx, cy = (rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)

    await wait_for(d, '"Address details"', f"{semantic_label} detail dialog", retries=8, delay=0.5)
    sem = await d.cs_flat_text()
    if expected not in sem:
        raise AssertionError(
            f"{semantic_label}: expected address '{expected}' not found in "
            f"detail dialog — wallet identity mismatch after import."
        )
    print(f"    [ok] {semantic_label} == {expected}")
    await click_tooltip(d, "Close", delay=0.5)


async def _export_bed(d: UIDriver, out_file: Path):
    """
    Wallet detail → More options → Export → Descriptor → BED backup →
    'Before you export' info dialog → Export → save.
    """
    print(f"\n  [phase] export BED to {out_file.name}")
    if out_file.exists():
        out_file.unlink()

    pre_wins = _list_visible_windows()

    await click_tooltip(d, "More options", delay=0.6)
    await click_label(d, "Export", delay=0.6)
    await wait_for(d, '"Descriptor"', "Export choice sheet open")
    await click_label(d, "Descriptor", delay=0.8)

    await wait_for(d, '"BED backup"', "Descriptor export sheet open (BED option present)")
    await click_label(d, "BED backup", delay=0.8)

    # Informational (non-blocking-looking) colocation-warning dialog — must be
    # acknowledged via its 'Export' button before the native save dialog opens.
    await wait_for(d, '"Before you export"', "BED export info dialog visible")
    await click_label(d, "Export", delay=0.8)

    await _handle_gtk_save_dialog(out_file, pre_wins, timeout=15.0)

    for _ in range(20):
        if out_file.exists() and out_file.stat().st_size > 0:
            break
        await asyncio.sleep(0.5)
    else:
        raise AssertionError(f"Exported BED file not found at {out_file}")
    print(f"    [ok] exported {out_file} ({out_file.stat().st_size} bytes)")


async def _delete_all_imported_bed_wallets(d: UIDriver):
    """
    Delete every 'Imported BED' wallet card.

    Both imports in this test create a wallet with the same hardcoded name
    ('Imported BED' — BED import has no name-override param), so the shared
    `delete_wallet_from_list` helper can't be used twice in a row: it asserts
    the name is fully *absent* after each deletion, which is false while a
    second identically-named card is still on screen. Loop instead and only
    assert full absence once both are gone.
    """
    print(f"\n  [cleanup] removing '{WALLET_NAME}' wallet cards")
    for _ in range(3):
        sem = await d.cs_flat_text()
        if WALLET_NAME not in sem:
            break
        rect = await d.cs_find_by_tooltip("More options")
        if rect is None:
            break
        d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2, delay_s=0.5)
        await asyncio.sleep(0.6)
        item_rect = await d.cs_find_by_label("Delete")
        if item_rect is None:
            break
        d.flutter_click((item_rect[0] + item_rect[2]) // 2, (item_rect[1] + item_rect[3]) // 2)
        await asyncio.sleep(0.4)
        await wait_for(d, '"Delete wallet"', "delete confirmation dialog")
        await click_label(d, "Delete", delay=1.0)
        await asyncio.sleep(1.0)

    sem = await d.cs_flat_text()
    if WALLET_NAME in sem:
        raise AssertionError(f"Failed to delete all '{WALLET_NAME}' wallet cards")
    print(f"    [ok] all '{WALLET_NAME}' wallet cards removed")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_bed_backup_cycle(d: UIDriver):
    if not FIXTURE_BED.exists():
        raise AssertionError(f"Fixture not found: {FIXTURE_BED}")
    if not FIXTURE_XPUB:
        raise AssertionError(f"Fixture xpub is empty: {FIXTURE_DIR / 'xpub.txt'}")
    print(f"    [ok] fixture found ({FIXTURE_BED.stat().st_size} bytes)")

    await set_active_network(d, "Mainnet")

    # ── Cycle 1: import the real descriptor-cifrado fixture ────────────────
    await _import_bed(d, FIXTURE_BED)
    await _verify_addresses(d, "first import")

    # ── Export it back out as a fresh BED file ──────────────────────────────
    await _export_bed(d, EXPORT_FILE)

    # ── Cycle 2: re-import our own export and verify again ──────────────────
    await go_back_to_wallet_list(d)
    await _import_bed(d, EXPORT_FILE)
    await _verify_addresses(d, "re-import")

    # ── Cleanup: remove both "Imported BED" wallet cards ────────────────────
    await go_back_to_wallet_list(d)
    await _delete_all_imported_bed_wallets(d)

    print(f"\n    [PASS] BED import → verify → export → re-import → verify cycle")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_bed_backup_cycle, "reg47"))
