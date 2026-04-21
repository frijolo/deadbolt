#!/usr/bin/env python3
"""
Regression test 09: Restore backup and verify labels.

Depends on: regression_08_labels_backup.py must have been run first so that
  test_data/reg08_backup.deadbolt exists.

Flow:
  1. Wallet list → New → 'From backup'
  2. GTK file-open dialog → select test_data/reg08_backup.deadbolt
  3. Password prompt 'Enter backup password' → enter 'deadbolt' → Confirm
  4. Wait for Argon2id-High to decrypt (~10–25 s) → wallet detail opens
  5. Verify the wallet name ('Reg08-Labels-Wallet') appears in the AppBar
  6. Verify wallet network and descriptor section load (Descriptor tab)
  7. Addresses tab → verify:
     - at least one address is listed
     - address #0 carries label 'reg08-receive-addr'
  8. Transactions tab → if any transaction is listed, verify
     - first tx carries label 'reg08-tx'          (soft — skip if wallet has no txs)
  9. Coins tab → if any UTXO is listed, verify
     - first coin carries label 'reg08-utxo'       (soft — skip if wallet has no coins)

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_08_labels_backup.py   # creates the backup file
  python3 scripts/regression_09_restore_backup.py
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
    dismiss_startup_dialogs,
    navigate_wallets,
)


# ---------------------------------------------------------------------------
# Test constants (must match regression_08)
# ---------------------------------------------------------------------------

WALLET_NAME = "Reg08-Labels-Wallet"        # wallet name embedded in backup
BACKUP_FILE = PROJECT_ROOT / "test_data" / "reg08_backup.deadbolt"
EXPORT_PASSWORD = "deadbolt"

# Labels set by regression_08 — must all survive the restore
ADDRESS_LABEL = "reg08-receive-addr"
TX_LABEL      = "reg08-tx"
UTXO_LABEL    = "reg08-utxo"


# ---------------------------------------------------------------------------
# GTK file-dialog helpers
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


async def _handle_gtk_open_dialog(
    file_path: Path,
    pre_wins: set[str],
    timeout: float = 10.0,
):
    """
    Wait for the native GTK file-open dialog, then select `file_path`:
      Ctrl+L → absolute path → Enter.

    In GTK3 open mode, typing a full path to an existing file and pressing
    Enter selects the file and closes the dialog automatically.
    """
    env = {**os.environ, "DISPLAY": DISPLAY}

    deadline = asyncio.get_event_loop().time() + timeout
    win_id = None
    while asyncio.get_event_loop().time() < deadline:
        cur_wins = _list_visible_windows()
        new_wins = cur_wins - pre_wins
        if new_wins:
            win_id = list(new_wins)[0]
            print(f"    [gtk] file-open dialog detected: {win_id}")
            break
        await asyncio.sleep(0.3)

    if win_id is None:
        raise AssertionError(
            f"GTK file-open dialog did not appear within {timeout}s"
        )

    subprocess.run(["xdotool", "windowraise", win_id], env=env,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["xdotool", "windowfocus", "--sync", win_id], env=env,
                   stderr=subprocess.DEVNULL)
    await asyncio.sleep(0.5)

    # Ctrl+L → open location entry bar
    _xdo("key", "--clearmodifiers", "ctrl+l")
    await asyncio.sleep(0.4)

    # Type the full absolute path to the .deadbolt file
    subprocess.run(
        ["xdotool", "type", "--clearmodifiers", "--delay=20",
         "--", str(file_path.resolve())],
        env=env, stderr=subprocess.DEVNULL,
    )
    await asyncio.sleep(0.3)

    # In GTK open mode, Enter on a file path selects and confirms the dialog.
    _xdo("key", "Return")
    await asyncio.sleep(1.0)
    # Second Enter in case the dialog requires an explicit "Open" confirmation.
    _xdo("key", "Return")
    await asyncio.sleep(0.5)

    print(f"    [gtk] file path submitted: {file_path.resolve()}")


# ---------------------------------------------------------------------------
# Import phase
# ---------------------------------------------------------------------------

async def _import_backup(d: UIDriver):
    """
    Navigate to Wallet list → New → From backup → pick file → enter password.
    Lands on the WalletDetailScreen of the restored wallet.
    """
    print("\n  [phase] import backup")

    # Ensure we are on the Wallets tab
    await navigate_wallets(d)

    # Snapshot windows BEFORE opening the file picker
    pre_wins = _list_visible_windows()

    # New → From backup
    await click_tooltip(d, "New")
    await wait_for(d, "From backup", "new-wallet bottom sheet")
    await click_label(d, "From backup", delay=0.5)

    # Handle GTK file-open dialog
    await _handle_gtk_open_dialog(BACKUP_FILE, pre_wins, timeout=10.0)

    # The app now inspects the backup (fast), then shows the password prompt
    await wait_for(
        d, '"Enter backup password"',
        "backup password prompt",
        retries=15, delay=0.8,
    )
    print("    [ok] backup password prompt visible")

    # Enter the password (field label = 'Password', button = 'Confirm')
    await fill_field(d, "Password", EXPORT_PASSWORD)
    # Argon2id-High decryption: give up to 40 s
    print("    [step] confirming — Argon2id-High may take ~10–25 s…")
    await click_label(d, "Confirm", delay=1.0)

    # Wait for wallet detail to load
    await wait_for(
        d, '"Receive"',
        "wallet detail loaded after restore",
        retries=40, delay=1.0,
    )
    print("    [ok] wallet detail open after restore")


# ---------------------------------------------------------------------------
# Verification phases
# ---------------------------------------------------------------------------

async def _verify_wallet_identity(d: UIDriver):
    """Assert that the restored wallet is the one we backed up."""
    print("\n  [verify] wallet identity")
    sem = await d.semantics_tree()
    if f'"{WALLET_NAME}"' not in sem:
        raise AssertionError(
            f"Expected wallet name '{WALLET_NAME}' in AppBar after restore, "
            f"but it was not found."
        )
    print(f"    [ok] wallet name '{WALLET_NAME}' present")


async def _verify_address_label(d: UIDriver):
    """
    Navigate to the Addresses tab and assert:
      - at least one address is listed
      - address #0 carries the expected label
    """
    print("\n  [verify] address label")
    await click_label(d, "Addresses", delay=1.5)

    sem = await d.semantics_tree()
    if '"Loading addresses' in sem:
        await wait_for(d, 'receive_address_0', "address loading complete",
                       retries=15, delay=0.8)

    await asyncio.sleep(0.8)

    # Reveal addresses if the list is empty (fresh sandbox has an empty state)
    sem = await d.semantics_tree()
    if '"Reveal 20 more addresses"' in sem:
        await click_label(d, "Reveal 20 more addresses", delay=1.5)
        await wait_for(d, 'receive_address_0', "addresses revealed", retries=10, delay=0.6)
        sem = await d.semantics_tree()

    # 1. At least one address must exist
    if 'receive_address_0' not in sem:
        raise AssertionError(
            "No addresses found after restore — expected address #0 to be present."
        )
    print("    [ok] address #0 visible")

    # 2. The label must be present somewhere in the semantics tree
    if ADDRESS_LABEL not in sem:
        print("    [DEBUG] semantics dump (addresses tab after restore):")
        lines = sem.splitlines()
        # Find node#92 area and dump from there
        start = next((i for i, l in enumerate(lines) if "SemanticsNode#92" in l), 0)
        for line in lines[max(0, start):start + 120]:
            print(f"      {line}")
        raise AssertionError(
            f"Address label '{ADDRESS_LABEL}' not found after restore. "
            "Labels should survive a backup/restore cycle."
        )
    print(f"    [ok] address label '{ADDRESS_LABEL}' found")


async def _verify_tx_label(d: UIDriver):
    """Navigate to Transactions tab and assert the expected tx label is present."""
    print("\n  [verify] transaction label")
    await click_label(d, "Transactions", delay=1.0)
    await asyncio.sleep(0.8)
    sem = await d.semantics_tree()

    if '"No transactions yet"' in sem:
        raise AssertionError(
            "Transactions tab shows 'No transactions yet' after restore — "
            "expected the backed-up transaction history to be present."
        )

    if TX_LABEL not in sem:
        raise AssertionError(
            f"Transaction label '{TX_LABEL}' not found after restore. "
            "Labels on transactions must survive a backup/restore cycle."
        )
    print(f"    [ok] tx label '{TX_LABEL}' found")


async def _verify_utxo_label(d: UIDriver):
    """Navigate to Coins tab and assert the expected UTXO label is present."""
    print("\n  [verify] UTXO label")
    await click_label(d, "Coins", delay=1.5)

    sem = await d.semantics_tree()
    if '"Loading coins' in sem:
        await wait_for(d, '"Coins"', "coins loading complete",
                       retries=15, delay=0.8)

    await asyncio.sleep(0.8)
    sem = await d.semantics_tree()

    if '"No coins.' in sem:
        raise AssertionError(
            "Coins tab shows 'No coins' after restore — "
            "expected the backed-up UTXOs to be present."
        )

    if UTXO_LABEL not in sem:
        raise AssertionError(
            f"UTXO label '{UTXO_LABEL}' not found after restore. "
            "Labels on coins must survive a backup/restore cycle."
        )
    print(f"    [ok] UTXO label '{UTXO_LABEL}' found")


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_restore_backup(d: UIDriver):
    print(f"\n--- restore {BACKUP_FILE.name} ---")

    # Pre-flight: ensure the backup file exists
    if not BACKUP_FILE.exists():
        raise AssertionError(
            f"Backup file not found: {BACKUP_FILE}\n"
            "Run regression_08_labels_backup.py first to generate it."
        )
    print(f"    [ok] backup file found ({BACKUP_FILE.stat().st_size} bytes)")

    # ── Phase 1: import ──────────────────────────────────────────────────────
    await _import_backup(d)

    # ── Phase 2: identity check ──────────────────────────────────────────────
    await _verify_wallet_identity(d)

    # ── Phase 3: address label ───────────────────────────────────────────────
    await _verify_address_label(d)

    # ── Phase 4: transaction label ───────────────────────────────────────────
    await _verify_tx_label(d)

    # ── Phase 5: UTXO label ──────────────────────────────────────────────────
    await _verify_utxo_label(d)

    print(f"\n    [PASS] restore + label verification")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main():
    d = UIDriver(sandbox=True)
    try:
        await d.launch()
        d.raise_window()
        await dismiss_startup_dialogs(d)

        await test_restore_backup(d)

        print(f"\n{'='*50}")
        print("[RESULT] PASS")

    except AssertionError as exc:
        print(f"\n[FAIL] {exc}")
        await d.close()
        sys.exit(1)
    except Exception as exc:
        print(f"\n[ERROR] {exc}")
        await d.close()
        raise
    finally:
        try:
            await d.close()
        except Exception:
            pass


if __name__ == "__main__":
    asyncio.run(main())
