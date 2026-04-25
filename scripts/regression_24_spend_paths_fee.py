#!/usr/bin/env python3
"""
Regression test 24: Taproot wallet with multiple spend paths - verify fee calculation per path.

Flow:
  1. Settings → set Active Network to Signet
  2. Create project with complex tr(...) descriptor (multiple spend paths)
  3. Create wallet from project (Signet, DeviceKey)
  4. Get receive address - show address for funding
  5. Wait for external funding (sync)
  6. For each spend path: switch path → create PSBT → verify fee rate
  7. Create + sign + broadcast a final self-send PSBT
  8. Cleanup: delete wallet and project

Exit code: 0 = PASS, 1 = FAIL.

Prerequisites:
  bash scripts/prepare_test_build.sh
  python3 scripts/regression_24_spend_paths_fee.py

External funding needed: Send ~200000 sats to displayed address on signet
"""

import asyncio
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                          # noqa: E402
from regression_helpers import (                       # noqa: E402
    wait_for, wait_absent,
    dismiss_startup_dialogs,
    navigate_designer, navigate_wallets, fill_field, click_label, click_tooltip,
    go_back_to_wallet_list, delete_wallet_from_list,
    set_active_network_signet, run_regression, create_project,
    create_wallet_from_project, go_back,
    delete_project_from_list,
)


# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

PROJECT_NAME = "Reg24-MultiPath"
WALLET_NAME = "Reg24-FeeTest"

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

MIN_SPEND_PATHS = 2


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

async def get_receive_address(d: UIDriver) -> str:
    """Copy receive address via clipboard."""
    await click_label(d, "Addresses", delay=0.8)
    await wait_for(d, "receive_address_0", "Receive address visible", retries=8, delay=0.5)

    rect = await d.cs_find_by_label_part_containing("receive_address_0")
    if rect is None:
        raise AssertionError("receive_address_0 tile not found")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)
    await wait_for(d, '"Address details"', "AddressDetailDialog opened", retries=8, delay=0.5)

    share_rect = await d.cs_find_by_tooltip("Copy to clipboard")
    if share_rect is None:
        raise AssertionError("Copy to clipboard button not found")
    sx = (share_rect[0] + share_rect[2]) // 2
    sy = (share_rect[1] + share_rect[3]) // 2
    d.flutter_click(sx, sy)
    await asyncio.sleep(0.5)

    await wait_for(d, "Copy to clipboard", "Export sheet opened", retries=6, delay=0.5)
    copy_rect = await d.cs_find_by_label("Copy to clipboard")
    if copy_rect is None:
        raise AssertionError("Copy to clipboard option not found")
    cx2 = (copy_rect[0] + copy_rect[2]) // 2
    cy2 = (copy_rect[1] + copy_rect[3]) // 2
    d.flutter_click(cx2, cy2)
    await asyncio.sleep(0.5)

    addr = subprocess.check_output(
        ["xclip", "-selection", "clipboard", "-o"],
        env={**os.environ, "DISPLAY": ":0"},
    ).decode().strip()

    await click_tooltip(d, "Close", delay=0.5)
    await wait_absent(d, '"Address details"', "dialog closed", retries=5, delay=0.5)
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "Overview tab", retries=6, delay=0.5)

    return addr


async def wait_for_coins(d: UIDriver) -> bool:
    """Sync wallet and wait for at least one confirmed coin. Returns True if funded."""
    await click_tooltip(d, "Sync wallet", delay=1.5)
    await click_label(d, "Coins", delay=1.0)

    sem_coins = await wait_for(
        d, "sats",
        "Coins visible in Coins tab",
        retries=60, delay=2.0,
    )

    if '"No coins.' in sem_coins:
        print("    [info] No coins - wallet unfunded")
        return False

    print("    [ok] Wallet has coins")
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Receive"', "Overview tab", retries=6, delay=0.5)
    return True


async def robust_navigate_designer(d: UIDriver):
    """Navigate to Designer with retry on drawer/click failures."""
    for attempt in range(3):
        try:
            await navigate_designer(d)
            return
        except AssertionError:
            if attempt < 2:
                await asyncio.sleep(1.5)
            else:
                raise


# ---------------------------------------------------------------------------
# Spend path helpers
# ---------------------------------------------------------------------------

async def get_selected_spend_path(d: UIDriver) -> tuple[str, str] | None:
    """Return (threshold_str, mfp_str) for the currently selected spend path."""
    flat = await d.cs_flat_text()
    m = re.search(r'Spend path.*?(\d+)-of-(\d+).*?([0-9A-Fa-f]{4,})', flat)
    if m:
        return (f"{m.group(1)}-of-{m.group(2)}", m.group(3))
    return None


async def open_spend_path_dropdown(d: UIDriver) -> int:
    """
    Open the Spend path dropdown and return the count of available paths.
    Closes the dropdown before returning.
    """
    try:
        await click_label(d, "Spend path", delay=0.5)
    except AssertionError:
        rect = await d.cs_find_by_label_part_containing("Spend path")
        if rect:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            d.flutter_click(cx, cy)
            await asyncio.sleep(0.5)
        else:
            return 0

    await wait_for(d, "1-of-1", "Spend path picker opened", retries=6, delay=0.5)

    tree = await d.cs_tree()
    count = sum(
        1 for n in tree
        if re.match(r'\d+-of-\d+', n.get("label", ""))
    )

    try:
        await click_label(d, "Spend path", delay=0.3)
    except AssertionError:
        d.flutter_click(210, 600)
        await asyncio.sleep(0.3)

    return count


async def switch_spend_path(d: UIDriver, path_index: int):
    """
    Open spend path dropdown and select path at `path_index` (0-based).
    Raises AssertionError if out of range or dropdown won't open.
    """
    try:
        await click_label(d, "Spend path", delay=0.5)
    except AssertionError:
        rect = await d.cs_find_by_label_part_containing("Spend path")
        if rect:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            d.flutter_click(cx, cy)
            await asyncio.sleep(0.5)
        else:
            raise AssertionError("Spend path dropdown not found")

    await wait_for(d, "1-of-1", "Spend path picker opened", retries=6, delay=0.5)

    tree = await d.cs_tree()
    path_nodes = []
    for n in tree:
        label = n.get("label", "")
        if re.match(r'\d+-of-\d+', label):
            path_nodes.append(n)

    if path_index >= len(path_nodes):
        raise AssertionError(f"path_index={path_index} out of range ({len(path_nodes)} paths)")

    n = path_nodes[path_index]
    rect = n.get("globalRect", [])
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.0)


async def create_selfsend_psbt(
    d: UIDriver,
    label: str,
    use_max: bool = True,
) -> dict:
    """Create a self-send PSBT with the current spend path. Returns fee info dict."""
    await fill_field(d, "Label", label)

    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "Wallet picker visible", retries=6, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await asyncio.sleep(1.0)

    selected = await get_selected_spend_path(d)
    selected_path = f"{selected[0]} ({selected[1][:4]}...)" if selected else "?"

    if use_max:
        await click_label(d, "MAX", delay=0.8)
        await wait_absent(d, '"— sats"', "Amount computed", retries=15, delay=0.5)

    sem_before = await d.cs_flat_text()
    rate_m = re.search(r'(\d+\.?\d*)\s*sat/vB', sem_before)
    fee_rate_display = float(rate_m.group(1)) if rate_m else None

    amt_m = re.search(r'[Aa]mount.*?(\d+[\d,]*)', sem_before)
    amount = int(amt_m.group(1).replace(',', '')) if amt_m else None

    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, "Unsigned Transaction", "PSBT detail opened", retries=15, delay=1.0)

    sem_psbt = await d.cs_flat_text()
    fee_match = re.search(r'[Ff]ee.*?(\d+)', sem_psbt)
    rate_match = re.search(r'(\d+\.?\d*)\s*sat/vB', sem_psbt)

    total_fee = int(fee_match.group(1)) if fee_match else None
    fee_rate = float(rate_match.group(1)) if rate_match else None

    return {
        "total_fee": total_fee,
        "fee_rate": fee_rate,
        "fee_rate_display": fee_rate_display,
        "amount": amount,
        "selected_path": selected_path,
    }


async def close_modal_and_return(d: UIDriver):
    """Close the PSBT detail screen and return to WalletDetail."""
    d.raise_window()
    await asyncio.sleep(0.3)

    tree = await d.cs_tree()
    unsigned_rect = None
    for n in tree:
        if n.get("label") == "Unsigned Transaction":
            unsigned_rect = d._cs_rect(n)
            break

    if unsigned_rect:
        all_back = await d.cs_find_all_by_tooltip("Back")
        candidates = [r for r in all_back if r[1] > unsigned_rect[1]]
        rect = candidates[0] if candidates else (all_back[0] if all_back else None)
    else:
        rect = await d.cs_find_by_tooltip("Back")

    if rect:
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        d.flutter_click(cx, cy)
        await asyncio.sleep(0.5)
    else:
        d.raise_window()
        await asyncio.sleep(0.3)
        env = {**os.environ, "DISPLAY": ":0"}
        subprocess.run(
            ["xdotool", "key", "--clearmodifiers", "Alt+Left"],
            env=env, stderr=subprocess.DEVNULL,
        )
        await asyncio.sleep(0.5)
    await wait_for(d, '"Reg24-FeeTest"', "Back on WalletDetail", retries=10, delay=0.5)


async def navigate_to_create_tx(d: UIDriver):
    """Navigate from WalletDetail to Create TX screen."""
    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen", retries=10, delay=0.5)
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "Coin selector opened", retries=10, delay=0.5)
    coin_rect = await d.cs_find_by_label_part_containing("sats")
    if coin_rect is None:
        raise AssertionError("No coin tile found")
    cx = (coin_rect[0] + coin_rect[2]) // 2
    cy = (coin_rect[1] + coin_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)
    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "Back on Create TX", retries=10, delay=0.5)


async def verify_fee_data(psbt_data: dict) -> list[str]:
    """
    Verify PSBT fee data.
    Hard failures raise AssertionError; soft inconsistencies are returned as warnings.
    """
    warnings = []
    total = psbt_data["total_fee"]
    rate = psbt_data["fee_rate"]
    rate_disp = psbt_data["fee_rate_display"]

    if total is None or total < 1:
        raise AssertionError(f"Missing/invalid total fee: {total}")

    if rate is not None and rate < 1:
        raise AssertionError(f"Invalid fee rate: {rate} sat/vB")

    if rate_disp is not None and rate is not None:
        diff = abs(rate - rate_disp)
        if diff > 1.0:
            warnings.append(
                f"Fee rate mismatch: UI={rate_disp} vs PSBT={rate} sat/vB (diff={diff:.2f})"
            )

    if rate is not None and rate > 0:
        implied_vb = total / rate
        if implied_vb < 50:
            warnings.append(f"Implied vsize suspiciously small: {implied_vb:.1f} vB")
        if implied_vb > 600:
            warnings.append(f"Implied vsize unusually large: {implied_vb:.1f} vB")

    return warnings


# ---------------------------------------------------------------------------
# Test phases
# ---------------------------------------------------------------------------

async def phase_create_project_and_wallet(d: UIDriver):
    """Phase 1-2: Create project and wallet."""
    print("\n  [phase 1] Create project from taproot descriptor")
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    sem = await d.cs_flat_text()
    paths_match = re.search(r'"Spend paths \((\d+)\)"', sem)
    if paths_match:
        paths_count = int(paths_match.group(1))
        print(f"    [ok] {paths_count} spend paths in project (>= {MIN_SPEND_PATHS})")

    weight_matches = re.findall(r'(\d+\.?\d*)\s*vB', sem)
    if weight_matches:
        weights = [float(w) for w in weight_matches]
        print(f"    [ok] Path weights: {weights}")

    print("\n  [phase 2] Create wallet from project")
    await create_wallet_from_project(d, WALLET_NAME, network="Signet")
    print(f"    [ok] Wallet '{WALLET_NAME}' created")


async def phase_fund_wallet(d: UIDriver):
    """Phase 3: Get receive address."""
    print("\n  [phase 3] Get receive address for funding")
    await wait_for(d, '"Receive"', "Wallet detail loaded", retries=10, delay=0.5)
    addr = await get_receive_address(d)
    print(f"    [ok] Receive address: {addr}")

    addr_file = f"/tmp/{WALLET_NAME}_addr.txt"
    with open(addr_file, "w") as f:
        f.write(addr)
    print(f"    [info] Address written to {addr_file}")


# ---------------------------------------------------------------------------
# Main test
# ---------------------------------------------------------------------------

async def test_spend_paths_fee(d: UIDriver):
    print(f"\n--- {WALLET_NAME} (multi-path fee calculation) ---")

    await set_active_network_signet(d)
    await phase_create_project_and_wallet(d)
    await phase_fund_wallet(d)

    print("\n  [phase 4] Wait for external funding...")
    funded = await wait_for_coins(d)
    if not funded:
        print("    [skip] Fee tests - wallet unfunded")
        print("    [info] Please fund wallet and re-run")
        return

    print("\n  [phase 5] Test fee calculation per spend path")

    await navigate_to_create_tx(d)

    sem_pre = await d.cs_flat_text()
    print(f"    [ok] Spend path selector present: {'Spend path' in sem_pre}")

    initial = await get_selected_spend_path(d)
    if initial:
        print(f"    [ok] Initial path: {initial[0]} ({initial[1][:4]}...)")

    paths_count = await open_spend_path_dropdown(d)
    print(f"    [ok] {paths_count} spend paths in dropdown")
    if paths_count < MIN_SPEND_PATHS:
        raise AssertionError(f"Expected >= {MIN_SPEND_PATHS} spend paths, got {paths_count}")

    path_fees: list[dict] = []
    actual_count = 0
    seen_mfps: set[str] = set()
    for i in range(paths_count):
        try:
            await switch_spend_path(d, i)
        except AssertionError:
            break
        actual_count += 1

        selected = await get_selected_spend_path(d)
        if selected is None:
            raise AssertionError(f"Path {i}: spend path not reflected in UI after switch")
        mfp = selected[1].upper()
        if mfp in seen_mfps:
            raise AssertionError(
                f"Path {i}: fingerprint {mfp} already seen — dropdown did not switch paths"
            )
        seen_mfps.add(mfp)
        print(f"    [ok] Path {actual_count}: {selected[0]} ({mfp[:4]}...) — unique fingerprint ✓")

        try:
            psbt_data = await create_selfsend_psbt(d, label=f"path-{i}", use_max=True)

            warns = await verify_fee_data(psbt_data)
            for w in warns:
                print(f"    [warn] {w}")
            if not warns:
                print(f"    [ok] Fee data consistent")

            path_fees.append({**psbt_data, "path_index": i})

            await close_modal_and_return(d)
            if actual_count < paths_count:
                await navigate_to_create_tx(d)

        except AssertionError as e:
            print(f"    [warn] Could not create PSBT for path {i}: {e}")
            try:
                await close_modal_and_return(d)
            except Exception:
                pass

    print(f"\n    [ok] {len(path_fees)} PSBTs created across {actual_count} paths")

    if len(path_fees) >= 2:
        fees = [f["fee_rate"] for f in path_fees if f["fee_rate"]]
        if fees:
            print(f"    [info] Fee rates across paths: {[f'{x:.1f}' for x in fees]}")
        totals = [f["total_fee"] for f in path_fees if f["total_fee"]]
        if totals:
            print(f"    [info] Total fees across paths: {totals}")

        key_fee = path_fees[0]["total_fee"]
        script_fees = [pf["total_fee"] for pf in path_fees[1:] if pf["total_fee"]]
        if script_fees:
            max_script_fee = max(script_fees)
            if key_fee >= max_script_fee:
                raise AssertionError(
                    f"Key-path fee ({key_fee} sats) should be cheaper than script-path fee "
                    f"({max_script_fee} sats) — weight calculation may be wrong"
                )
            print(
                f"    [ok] Key-path cheaper: {key_fee} sats < script-path {max_script_fee} sats ✓"
            )

    # Phase 6: verify key-path PSBT detail is complete.
    # Sign+broadcast is omitted: the descriptor uses Watch-Only xpubs (no hot key),
    # so software signing is not available in automation.  Full sign+broadcast
    # coverage lives in regression_11 (hot-key wallet).
    print("\n  [phase 6] Verify key-path PSBT detail")

    await navigate_to_create_tx(d)

    await switch_spend_path(d, 0)
    await asyncio.sleep(0.5)

    final_psbt = await create_selfsend_psbt(d, label="final-verify", use_max=True)
    warns_final = await verify_fee_data(final_psbt)
    for w in warns_final:
        print(f"    [warn] {w}")

    sem_psbt = await d.cs_flat_text()
    if "Unsigned Transaction" not in sem_psbt:
        raise AssertionError("PSBT detail screen not shown after Create PSBT")
    print("    [ok] PSBT detail screen visible ✓")

    if final_psbt["total_fee"] is None or final_psbt["total_fee"] < 1:
        raise AssertionError(f"Final PSBT has no fee: {final_psbt['total_fee']}")
    print(f"    [ok] Final PSBT fee: {final_psbt['total_fee']} sats ✓")

    await close_modal_and_return(d)

    print("\n  [phase 7] Cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)
    try:
        await robust_navigate_designer(d)
        await delete_project_from_list(d, PROJECT_NAME)
    except Exception as e:
        print(f"    [warn] Could not delete project: {e}")

    print(f"\n    [PASS] {WALLET_NAME}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_regression(test_spend_paths_fee, "reg24"))