#!/usr/bin/env python3
"""
Regression test 36: HW signs a 1-of-2 wsh-miniscript inheritance descriptor
and the node accepts the broadcast.

Descriptor:
    wsh(or_d(
      pk([HW_MFP/...]HW_XPUB),
      and_v(v:pk([WO_MFP/...]WO_XPUB),older(5))
    ))

The HW key path is the primary spend path — a single HW signature finalises
the PSBT. The recovery path requires the watch-only key + 5 confirmations.

This exercises the Policy variant on wsh (NOT taproot script-tree like
reg31). The dispatch in btc_sign_psbt:322-337 routes wsh miniscript through
extract_script_config_policy.

Skips ONLY if no HW device is detected.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver  # noqa: E402
from regression_helpers import (  # noqa: E402
    wait_for, wait_absent,
    navigate_designer, navigate_wallets,
    click_label, click_tooltip, fill_field,
    set_active_network_signet, go_back, go_back_to_wallet_list,
    delete_wallet_from_list, delete_project_from_list,
    create_project, wait_for_tooltip, run_regression,
)
from hw_helpers import (  # noqa: E402
    connect_hw_in_open_sheet, wait_for_user, close_open_sheet,
    extract_first_receive_address, fail_no_funds,
    verify_first_receive_address_on_hw, bump_fee_if_rbf,
    verify_descriptor_sig_with_hw,
)

PROJECT_NAME = "Reg36-HW-WshMs"
WALLET_NAME = "Reg36-HW-WshMs-1of2"
PSBT_LABEL = "reg36-hw-wshms-selfpay"

# Same HW (4061aff0) and watch-only (ff81be5d) keys used in reg31. Both at
# m/48'/1'/0'/2' (P2WSH BIP48 sub-account). Multipath kept simple (<0;1>).
DESCRIPTOR = (
    "wsh(or_d("
    "pk([4061aff0/48'/1'/0'/2']"
    "tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*),"
    "and_v(v:pk([ff81be5d/48'/1'/0'/2']"
    "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*),older(5))"
    "))"
)


async def _import_and_create_wallet(d: UIDriver):
    print("\n  [phase 1] import descriptor as project")
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    print("\n  [phase 2] create wallet from project")
    from regression_helpers import click_popup_item
    await click_popup_item(d, "More options", 72, "Create wallet")
    await wait_for(d, '"New Wallet"', "Create wallet screen opened",
                   retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)
    d.scroll_down(8)
    await asyncio.sleep(0.5)
    await wait_for(d, '"Create wallet"', "Create wallet button visible",
                   retries=10, delay=0.5)
    await click_label(d, "Create wallet", delay=0.5)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=90, delay=1.0)


async def _register_on_hw(d: UIDriver):
    print("\n  [phase 3] register wsh-miniscript policy on HW (idempotent)")
    await click_label(d, "Hardware wallet", delay=0.5)
    await wait_for(d, "Register wallet", "HW Actions sheet opened",
                   retries=15, delay=0.6)
    await connect_hw_in_open_sheet(d, op_label="wsh miniscript register")

    await click_label(d, "Check registration", delay=0.5)
    initial = None
    for _ in range(30):
        flat = await d.cs_flat_text()
        if "NOT registered" in flat:
            initial = "absent"
            break
        if "is registered on this device" in flat:
            initial = "present"
            break
        await asyncio.sleep(1.0)
    if initial is None:
        raise AssertionError("Check registration did not report a known state")
    await click_label(d, "Back", delay=0.5)

    if initial == "absent":
        await click_label(d, "Register wallet", delay=0.5)
        await wait_for_user(
            "Confirm the wsh miniscript policy on the BitBox screen "
            "(approve the inheritance policy)."
        )
        await wait_for(d, "registered on device",
                       "device confirms wallet registered",
                       retries=240, delay=1.0)
        await click_label(d, "Back", delay=0.5)
    else:
        print("    [info] policy was already registered from a previous run")
    await close_open_sheet(d)


async def _sync_or_fail(d: UIDriver):
    print("\n  [phase 4] sync — fail if no funds")
    await wait_for_tooltip(d, "Sync wallet", "sync button available")
    await click_label(d, "Coins", delay=1.0)
    sem = ""
    for _ in range(120):
        sem = await d.cs_flat_text()
        if "sats" in sem or "No coins" in sem:
            break
        await asyncio.sleep(1.5)
    if "No coins" in sem or "sats" not in sem:
        await click_label(d, "Addresses", delay=0.8)
        await wait_for(d, "receive_address_0", "first receive address visible",
                       retries=15, delay=1.0)
        addr = await extract_first_receive_address(d)
        fail_no_funds(addr, WALLET_NAME)


async def _build_psbt(d: UIDriver):
    print("\n  [phase 5] build self-pay MAX PSBT (HW path)")
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview", retries=8, delay=0.5)
    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                   retries=10, delay=0.5)

    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector opened", retries=10, delay=0.5)
    coin_rect = await d.cs_find_by_label_part_containing("sats")
    if coin_rect is None:
        raise AssertionError("No coin tile visible")
    cx = (coin_rect[0] + coin_rect[2]) // 2
    cy = (coin_rect[1] + coin_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.5)
    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX screen",
                   retries=10, delay=0.5)

    await fill_field(d, "Label", PSBT_LABEL)
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)
    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed",
                      retries=15, delay=0.5)
    await bump_fee_if_rbf(d)
    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail opened",
                   retries=15, delay=1.0)


async def _sign_with_hw(d: UIDriver):
    print("\n  [phase 6] sign with HW (primary path)")
    await click_label(d, "Sign with hardware wallet", delay=0.5)
    await connect_hw_in_open_sheet(d, op_label="sign wsh miniscript PSBT")
    await click_label(d, "Sign transaction", delay=0.5)
    await wait_for_user("Confirm the transaction on the BitBox screen.")
    await wait_for(d, '"SIGNED"', "PSBT signed (SIGNED status)",
                   retries=240, delay=1.0)
    await wait_for(d, '"Broadcast"', "Broadcast button visible",
                   retries=10, delay=0.5)


async def _broadcast(d: UIDriver):
    print("\n  [phase 7] broadcast")
    await click_label(d, "Broadcast", delay=0.8)
    for _ in range(60):
        flat = await d.cs_flat_text()
        if "Transaction broadcast" in flat:
            print("    [ok] broadcast succeeded")
            return
        if "Broadcast failed" in flat:
            raise AssertionError(
                "Broadcast failed — the signed PSBT was rejected by the network."
            )
        await asyncio.sleep(1.0)
    raise AssertionError("Timed out waiting for broadcast result toast")


async def _cleanup(d: UIDriver):
    print("\n  [phase 8] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)
    try:
        await navigate_designer(d)
        await delete_project_from_list(d, PROJECT_NAME)
    except Exception as e:
        print(f"    [warn] could not delete project: {e}")


async def test_hw_sign_wsh_miniscript(d: UIDriver):
    print(f"\n--- {WALLET_NAME} ---")
    await set_active_network_signet(d)
    await _import_and_create_wallet(d)
    await _register_on_hw(d)
    await verify_first_receive_address_on_hw(d, op_label="verify wsh miniscript address")
    await _sync_or_fail(d)
    await _build_psbt(d)
    await _sign_with_hw(d)
    await _broadcast(d)

    print("\n  [phase 7] verify descriptor signature")
    await verify_descriptor_sig_with_hw(d, WALLET_NAME)

    await _cleanup(d)
    print(f"    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_hw_sign_wsh_miniscript, "reg36"))
