#!/usr/bin/env python3
"""
Regression test 08: Wallet labels + password-protected backup export (signet).

Loads the canonical signet watch-only wallet, syncs it, then:
  - adds a label to an address
  - adds a label to a transaction  (skipped gracefully if wallet has no txs)
  - adds a label to a UTXO         (skipped gracefully if wallet has no UTXOs)
  - exports a password-protected wallet backup
      protection=UserPassword, level=High, password='deadbolt'

The backup file is saved to test_data/reg08_backup.deadbolt (gitignored) so
that other regression tests can verify import/restore flows.

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_08_labels_backup.py
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
    click_popup_item,
    fill_field,
    dismiss_startup_dialogs,
    create_project,
    create_wallet_from_project, run_regression,
)


# ---------------------------------------------------------------------------
# Test constants
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg08-Signet-Project"
WALLET_NAME  = "Reg08-Labels-Wallet"

# wpkh signet watch-only wallet
# mnemonic: piece blue stadium control fiction kick group mimic hollow dog mask interest
DESCRIPTOR = (
    "wpkh([ff81be5d/84h/1h/0h]"
    "tpubDDjVt7cey7cxQ1nXzxpXuNT5vJecpvtMhmZywA9U9ChWDk8z6HSGPJ7YS6pyd8ZXQyfCeUCXrkyEqNeTFUmpdXT9r3TD1DAYoY52UEyy1Yf"
    "/<0;1>/*)"
)

BACKUP_DIR  = PROJECT_ROOT / "test_data"
BACKUP_FILE = BACKUP_DIR / "reg08_backup.deadbolt"

EXPORT_PASSWORD = "deadbolt"

# BIP-329 labels written by this test
ADDRESS_LABEL = "reg08-receive-addr"
TX_LABEL      = "reg08-tx"
UTXO_LABEL    = "reg08-utxo"


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def _xdo(*args):
    """Run an xdotool command, silently ignoring errors."""
    env = {**os.environ, "DISPLAY": DISPLAY}
    subprocess.run(["xdotool", *args], env=env,
                   stderr=subprocess.DEVNULL, check=False)


async def _paste(text: str):
    """Copy `text` to the X clipboard and paste it into the focused widget."""
    env = {**os.environ, "DISPLAY": DISPLAY}
    subprocess.run(
        ["xclip", "-selection", "clipboard"],
        input=text.encode(), env=env, check=True,
    )
    await asyncio.sleep(0.1)
    _xdo("key", "ctrl+v")
    await asyncio.sleep(0.2)


async def _type_in_label_dialog(d: UIDriver, label_text: str):
    """
    Type `label_text` into the open _LabelDialog TextField (autofocused)
    and click Save.
    """
    await asyncio.sleep(0.3)
    _xdo("key", "ctrl+a")       # clear any existing text
    await asyncio.sleep(0.1)
    await _paste(label_text)
    await click_label(d, "Save", delay=0.5)
    print(f"    [ok] label saved: '{label_text}'")


def _list_visible_windows() -> set[str]:
    """Return the set of visible X11 window IDs via xdotool."""
    env = {**os.environ, "DISPLAY": DISPLAY}
    try:
        out = subprocess.check_output(
            ["xdotool", "search", "--onlyvisible", "--name", "."],
            env=env, stderr=subprocess.DEVNULL, text=True,
        ).strip()
        return set(out.split()) if out else set()
    except subprocess.CalledProcessError:
        return set()


async def _handle_gtk_save_dialog(
    save_path: Path,
    pre_wins: set[str],
    timeout: float = 25.0,
):
    """
    Wait for the native GTK file-save dialog to appear (detected as a new X11
    window), then interact with it:  Ctrl+L → full path → Enter.

    `pre_wins` must be captured *before* the Argon2id export is triggered so
    that the new window can be reliably detected even if it takes >10 s.
    """
    save_path.parent.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "DISPLAY": DISPLAY}

    deadline = asyncio.get_event_loop().time() + timeout
    win_id = None
    while asyncio.get_event_loop().time() < deadline:
        cur_wins = _list_visible_windows()
        new_wins = cur_wins - pre_wins
        if new_wins:
            win_id = list(new_wins)[0]
            print(f"    [gtk] new window detected: {win_id}")
            break
        await asyncio.sleep(0.3)

    if win_id is None:
        raise AssertionError(
            f"GTK save dialog did not appear within {timeout}s"
        )

    subprocess.run(["xdotool", "windowraise", win_id], env=env,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["xdotool", "windowfocus", "--sync", win_id], env=env,
                   stderr=subprocess.DEVNULL)
    await asyncio.sleep(0.5)

    # Ctrl+L opens the location/path entry in GTK file choosers
    _xdo("key", "--clearmodifiers", "ctrl+l")
    await asyncio.sleep(0.4)

    # The GTK file chooser with allowedExtensions=['deadbolt'] automatically
    # appends ".deadbolt" to whatever filename is typed.  Strip the extension
    # from the path so GTK adds it once, producing the correct filename.
    typed_path = save_path.with_suffix("") if save_path.suffix == ".deadbolt" else save_path
    subprocess.run(
        ["xdotool", "type", "--clearmodifiers", "--delay=20",
         "--", str(typed_path.resolve())],
        env=env, stderr=subprocess.DEVNULL,
    )
    await asyncio.sleep(0.3)
    _xdo("key", "Return")
    await asyncio.sleep(1.5)
    _xdo("key", "Return")   # accept "overwrite?" prompt if shown
    await asyncio.sleep(1.0)
    print(f"    [gtk] path submitted: {typed_path.resolve()} (GTK will add .deadbolt)")


# ---------------------------------------------------------------------------
# Phase helpers
# ---------------------------------------------------------------------------

async def _label_first_address(d: UIDriver):
    """Navigate to the Addresses tab, reveal addresses, label address #0."""
    print("\n  [phase] address label")
    await click_label(d, "Addresses", delay=1.5)

    # Wait for address loading spinner to clear
    sem = await d.cs_flat_text()
    if '"Loading addresses' in sem:
        await wait_for(
            d, '"Addresses"', "address loading complete",
            retries=15, delay=0.8,
        )

    await asyncio.sleep(0.8)
    sem = await d.cs_flat_text()

    # Reveal addresses if the list is empty
    if '"Reveal 20 more addresses"' in sem:
        print("    [step] revealing first 20 addresses")
        await click_label(d, "Reveal 20 more addresses", delay=1.5)

    # Find the first address tile by its semantic label 'receive_address_0'.
    await wait_for(d, 'receive_address_0', "address #0 visible", retries=10, delay=0.6)
    rect = await d.cs_find_by_label_part("receive_address_0")
    if rect is None:
        raise AssertionError("Could not find address tile #0 in semantics tree")

    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    print(f"    [step] tapping address #0 at flutter ({cx},{cy})")
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)

    await wait_for(d, '"Address details"', "address detail dialog",
                   retries=8, delay=0.5)
    await click_tooltip(d, "Edit", delay=0.5)
    await wait_for(d, '"Address label"', "label dialog", retries=6, delay=0.5)
    await _type_in_label_dialog(d, ADDRESS_LABEL)
    await click_tooltip(d, "Close", delay=0.5)
    print("    [ok] address label set")


async def _label_first_transaction(d: UIDriver):
    """Navigate to Transactions tab and label the first transaction."""
    print("\n  [phase] transaction label")
    await click_label(d, "Transactions", delay=1.0)
    await asyncio.sleep(0.8)

    sem = await d.cs_flat_text()
    if '"No transactions yet"' in sem:
        raise AssertionError(
            "Transactions tab shows 'No transactions yet' — "
            "expected this wallet to have on-chain transactions."
        )

    # Transaction tiles show a type label: Received / Sent / Self-transfer.
    # Labels are multi-line in the semantics dump — search for opening quote prefix.
    for candidate in ("Received", "Sent", "Self-transfer"):
        if f'"{candidate}' in sem:
            rect = await d.cs_find_by_label_part(candidate)
            if rect is None:
                continue
            d.flutter_click((rect[0] + rect[2]) // 2,
                            (rect[1] + rect[3]) // 2)
            await asyncio.sleep(1.0)
            await wait_for(d, '"Transaction details"', "tx detail dialog",
                           retries=8, delay=0.5)
            await click_tooltip(d, "Edit", delay=0.5)
            await wait_for(d, '"Label"', "tx label dialog", retries=6, delay=0.5)
            await _type_in_label_dialog(d, TX_LABEL)
            await click_tooltip(d, "Close", delay=0.5)
            print("    [ok] transaction label set")
            return

    raise AssertionError(
        "No transaction tile found in semantics — "
        "expected Received/Sent/Self-transfer to be visible after sync."
    )


async def _label_first_utxo(d: UIDriver):
    """Navigate to the Coins tab and label the first UTXO."""
    print("\n  [phase] UTXO label")
    await click_label(d, "Coins", delay=1.5)

    # Wait for UTXOs to load
    sem = await d.cs_flat_text()
    if '"Loading coins' in sem:
        await wait_for(d, '"Coins"', "coins loading complete",
                       retries=15, delay=0.8)

    await asyncio.sleep(0.8)
    sem = await d.cs_flat_text()

    if '"No coins.' in sem:
        raise AssertionError(
            "Coins tab shows 'No coins' — "
            "expected this wallet to have UTXOs after sync."
        )

    rect = await d.cs_find_by_label_part_containing("tb1q")
    if rect is None:
        raise AssertionError(
            "Could not locate a coin tile in semantics — "
            "expected at least one UTXO to be visible."
        )

    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    print(f"    [step] tapping coin at flutter ({cx},{cy})")
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)

    await wait_for(d, '"Coin details"', "utxo detail dialog",
                   retries=8, delay=0.5)
    await click_tooltip(d, "Edit", delay=0.5)
    await wait_for(d, '"Label"', "utxo label dialog", retries=6, delay=0.5)
    await _type_in_label_dialog(d, UTXO_LABEL)
    # Coin details dialog uses "Cancel" to dismiss (unlike address/tx which use "Close")
    await click_tooltip(d, "Cancel", delay=0.5)
    print("    [ok] UTXO label set")


async def _verify_labels_pre_backup(d: UIDriver):
    """
    Verify that all three labels are visible in the semantics tree before
    exporting the backup.  This confirms the labels were persisted to the
    DB so that a failing restore can be distinguished from a failing write.
    """
    print("\n  [phase] verify labels visible pre-backup")

    # ── address label ────────────────────────────────────────────────────────
    await click_label(d, "Addresses", delay=1.0)
    await asyncio.sleep(0.8)
    sem = await d.cs_flat_text()
    if ADDRESS_LABEL not in sem:
        raise AssertionError(
            f"[pre-backup] Address label '{ADDRESS_LABEL}' not visible in "
            "Addresses tab after labelling — expected it to appear in the tile."
        )
    print(f"    [ok] address label '{ADDRESS_LABEL}' visible pre-backup")

    # ── transaction label ────────────────────────────────────────────────────
    await click_label(d, "Transactions", delay=1.0)
    await asyncio.sleep(0.8)
    sem = await d.cs_flat_text()
    if TX_LABEL not in sem:
        raise AssertionError(
            f"[pre-backup] Transaction label '{TX_LABEL}' not visible in "
            "Transactions tab after labelling."
        )
    print(f"    [ok] tx label '{TX_LABEL}' visible pre-backup")

    # ── UTXO label ───────────────────────────────────────────────────────────
    await click_label(d, "Coins", delay=1.0)
    await asyncio.sleep(0.8)
    sem = await d.cs_flat_text()
    if UTXO_LABEL not in sem:
        raise AssertionError(
            f"[pre-backup] UTXO label '{UTXO_LABEL}' not visible in "
            "Coins tab after labelling."
        )
    print(f"    [ok] UTXO label '{UTXO_LABEL}' visible pre-backup")


async def _export_wallet_backup(d: UIDriver):
    """
    Export a wallet backup via More options → Export → Wallet with:
      protection = UserPassword, level = High, password = 'deadbolt'.

    The GTK native save dialog is handled by detecting the new X11 window.
    The backup is written to BACKUP_FILE.
    """
    print("\n  [phase] export wallet backup")

    # Snapshot existing windows BEFORE triggering any dialogs — needed to
    # detect the GTK file-save dialog that appears after Argon2id completes.
    pre_wins = _list_visible_windows()

    # More options → Export (l10n.exportBip329Button = "Export")
    await click_popup_item(d, "More options", 0, "Export")
    await wait_for(d, '"Labels (BIP-329)"', "export choice dialog",
                   retries=8, delay=0.5)

    # Sub-dialog: choose Wallet backup
    await click_label(d, "Wallet", delay=0.5)
    await wait_for(d, '"Export backup"', "export backup dialog",
                   retries=8, delay=0.5)

    # Security level: High
    await click_label(d, "High", delay=0.5)

    # Password fields (protection=Password is already selected by default)
    await fill_field(d, "Backup password", EXPORT_PASSWORD)
    await fill_field(d, "Confirm password", EXPORT_PASSWORD)

    # Click Export — may first show a "Backup Signatures" warning when the
    # wallet has unsigned keys.  If so, click "Export backup" to proceed.
    # After that, Argon2id-High runs (~10–25 s) then the GTK dialog opens.
    print("    [step] clicking Export (Argon2id-High may take ~10–25 s)…")
    await click_label(d, "Export", delay=0.5)

    await asyncio.sleep(1.0)
    sem = await d.cs_flat_text()
    if '"Backup Signatures"' in sem:
        print("    [info] Backup Signatures warning shown — clicking 'Export backup' to proceed")
        await click_label(d, "Export backup", delay=0.5)

    # Wait for the GTK dialog to open (with generous timeout for Argon2id)
    await _handle_gtk_save_dialog(BACKUP_FILE, pre_wins, timeout=40.0)

    # Verify "Backup saved" toast
    await wait_for(d, '"Backup saved"', "Backup saved toast",
                   retries=15, delay=1.0)

    # Verify the file exists on disk with a reasonable size
    if not BACKUP_FILE.exists():
        raise AssertionError(
            f"Backup file not found after export: {BACKUP_FILE}"
        )
    size = BACKUP_FILE.stat().st_size
    if size < 100:
        raise AssertionError(
            f"Backup file is suspiciously small ({size} bytes): {BACKUP_FILE}"
        )
    print(f"    [ok] backup saved: {BACKUP_FILE} ({size} bytes)")


def _inspect_backup_labels(backup_path: Path, password: str):
    """
    Decrypt the .deadbolt backup and query label tables from the embedded
    SQLCipher database.  Prints what was found so we can verify that labels
    survive the export step.
    """
    import json, base64, tempfile, os
    from argon2.low_level import hash_secret_raw, Type
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    import sqlcipher3

    print("\n  [phase] inspect backup labels (decrypt + query DB)")

    with open(backup_path, "rb") as f:
        backup = json.load(f)

    version = backup.get("version", 0)
    if version not in (1, 2):
        print(f"    [warn] unknown backup version {version}, skipping inspect")
        return

    def aes_gcm_decrypt(key: bytes, data: bytes) -> bytes:
        nonce, ct = data[:12], data[12:]
        return AESGCM(key).decrypt(nonce, ct, None)

    def argon2id_derive(password: str, salt: bytes, m_cost: int, t_cost: int, p_cost: int) -> bytes:
        return hash_secret_raw(
            secret=password.encode(),
            salt=salt,
            time_cost=t_cost,
            memory_cost=m_cost,
            parallelism=p_cost,
            hash_len=32,
            type=Type.ID,
        )

    # ── Key derivation hierarchy ────────────────────────────────────────────
    # v1: Argon2id(password) → export_data_key  (direct)
    # v2: Argon2id(password) → wrapping_key → unwrap slot.wrapped_key → export_data_key
    #     export_data_key → unwrap data_key_wrapped → wallet_data_key
    #     export_data_key → decrypt "data" → raw SQLCipher DB bytes

    if version == 1:
        prot = backup["protection"]
        salt_bytes = bytes.fromhex(prot["salt"])
        m_cost = int(prot.get("m_cost", 65536))
        t_cost = int(prot.get("t_cost", 3))
        p_cost = int(prot.get("p_cost", 1))
        export_data_key = argon2id_derive(password, salt_bytes, m_cost, t_cost, p_cost)
    else:  # version == 2
        slot = backup["protection"]["slots"][0]
        salt_bytes = bytes.fromhex(slot["salt"])
        m_cost = int(slot.get("m_cost", 65536))
        t_cost = int(slot.get("t_cost", 3))
        p_cost = int(slot.get("p_cost", 1))
        # Step 1: derive wrapping_key from password
        wrapping_key = argon2id_derive(password, salt_bytes, m_cost, t_cost, p_cost)
        # Step 2: unwrap slot → export_data_key
        export_data_key = aes_gcm_decrypt(wrapping_key, bytes.fromhex(slot["wrapped_key"]))

    print(f"    [ok] export_data_key derived ({len(export_data_key)} bytes)")

    # ── Decrypt wallet data_key ─────────────────────────────────────────────
    wrapped_raw = bytes.fromhex(backup["data_key_wrapped"])
    wallet_data_key_bytes = aes_gcm_decrypt(export_data_key, wrapped_raw)
    wallet_data_key_hex = wallet_data_key_bytes.hex()
    print(f"    [ok] wallet_data_key decrypted ({len(wallet_data_key_bytes)} bytes)")

    # ── Decrypt the embedded SQLCipher DB ───────────────────────────────────
    encrypted_db = base64.b64decode(backup["data"])
    db_bytes = aes_gcm_decrypt(export_data_key, encrypted_db)
    print(f"    [ok] DB decrypted ({len(db_bytes)} bytes)")

    # Write to a temp file and open with sqlcipher3
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".db")
    try:
        os.write(tmp_fd, db_bytes)
        os.close(tmp_fd)

        conn = sqlcipher3.connect(tmp_path)
        conn.execute(f'PRAGMA key = "x\'{wallet_data_key_hex}\'"')
        conn.execute("PRAGMA cipher_compatibility = 4")

        # List all tables in the DB
        tables = [r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        ).fetchall()]
        print(f"    [db] tables: {tables}")

        # Query wallet_info for basic sanity check
        if "wallet_info" in tables:
            rows = conn.execute("SELECT name, network FROM wallet_info").fetchall()
            if rows:
                for name, net in rows:
                    print(f"    [db] wallet_info: name='{name}' network='{net}'")
            else:
                print(f"    [db] wallet_info: EMPTY (unexpected!)")
        else:
            print(f"    [db] wallet_info: TABLE NOT FOUND (unexpected!)")

        # Count BDK data rows to check if BDK data is present
        for bdk_table in ["bdk_txs", "bdk_utxos", "bdk_checkpoints"]:
            if bdk_table in tables:
                count = conn.execute(f"SELECT COUNT(*) FROM {bdk_table}").fetchone()[0]
                print(f"    [db] {bdk_table}: {count} row(s)")

        # Query each label table
        for table, key_col in [
            ("address_labels", "address"),
            ("tx_labels", "txid"),
            ("coin_labels", "outpoint"),
        ]:
            if table not in tables:
                print(f"    [db] {table}: TABLE NOT FOUND")
                continue
            rows = conn.execute(
                f"SELECT {key_col}, label FROM {table}"
            ).fetchall()
            if rows:
                for key, lbl in rows:
                    print(f"    [db] {table}: {key[:20]}… → '{lbl}'")
            else:
                print(f"    [db] {table}: EMPTY")

        conn.close()
    finally:
        os.unlink(tmp_path)


# ---------------------------------------------------------------------------
# Main test function
# ---------------------------------------------------------------------------

async def test_labels_and_backup(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (labels + backup export) ---")

    # ── Phase 1: create project + wallet ────────────────────────────────────
    print("\n  [phase 1] create project + wallet")
    await create_project(d, PROJECT_NAME, DESCRIPTOR)
    await create_wallet_from_project(d, WALLET_NAME, protection="device_key",
                                     network="Signet")
    await wait_for(d, '"Receive"', "wallet detail loaded",
                   retries=20, delay=1.0)
    print("    [ok] wallet detail open")

    # Watch-only wallet: no private key material in the app for any spend path.
    await wait_for(d, "Cold Wallet", "Cold Wallet temperature icon visible",
                   retries=10, delay=0.5)

    # Trigger manual sync and wait for on-chain data to arrive.
    print("    [info] triggering sync and waiting for transactions…")
    await click_tooltip(d, "Sync wallet", delay=1.5)
    # Navigate to Transactions tab so we can detect sync completion.
    await click_label(d, "Transactions", delay=1.0)
    # Wait up to 180 s for at least one transaction tile to appear. Any of the
    # three type labels counts — this wallet's on-chain history may consist of
    # only self-transfers depending on prior test runs that spent its UTXOs.
    sync_ok = False
    for _ in range(120):
        sem = await d.cs_flat_text()
        if any(f'"{t}' in sem for t in ("Received", "Sent", "Self-transfer")):
            sync_ok = True
            break
        await asyncio.sleep(1.5)
    if not sync_ok:
        raise AssertionError(
            "Timeout: no Received/Sent/Self-transfer tile after sync"
        )
    print("    [ok] sync complete — transactions visible")
    print("    [ok] sync complete — transactions present")

    # ── Phase 2: label an address ────────────────────────────────────────────
    await _label_first_address(d)

    # ── Phase 3: label a transaction ────────────────────────────────────────
    await _label_first_transaction(d)

    # ── Phase 4: label a UTXO ────────────────────────────────────────────────
    await _label_first_utxo(d)

    # ── Phase 5: verify labels are visible in the UI before export ──────────
    await _verify_labels_pre_backup(d)

    # ── Phase 6: export wallet backup ───────────────────────────────────────
    await _export_wallet_backup(d)

    # ── Phase 7: decrypt backup and inspect label tables ────────────────────
    _inspect_backup_labels(BACKUP_FILE, EXPORT_PASSWORD)

    print(f"\n    [PASS] {WALLET_NAME}")
    print(f"    backup → {BACKUP_FILE}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_labels_and_backup, "reg08"))
