#!/usr/bin/env python3
"""
Regression test 34: HW signs a 1-of-2 wsh(sortedmulti(...)) PSBT and the
node accepts the broadcast.

Exercises the full Multisig firmware variant for sign:
  - Register wallet on BB02 (BIP48 sortedmulti via parse_bip48_sortedmulti
    fast-path, NOT wallet-policies).
  - Sign with HW (1-of-2 ⇒ HW signature alone is sufficient for finalize).
  - Broadcast on Signet — assert "Broadcasted" so we don't ship a regression
    where Flutter believes the PSBT is valid but the node rejects it.

Skips ONLY if no HW device is detected.
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver  # noqa: E402
from regression_helpers import (  # noqa: E402
    wait_for, wait_absent,
    navigate_wallets, click_label, click_tooltip, fill_field,
    set_active_network_signet, go_back_to_wallet_list,
    delete_wallet_from_list, wait_for_tooltip, run_regression,
    open_watch_only_manual_entry, fill_manual_keyspec,
    open_watch_only_hardware_wallet,
)
from hw_helpers import (  # noqa: E402
    connect_hw_in_open_sheet, wait_for_user, close_open_sheet,
    extract_first_receive_address, fail_no_funds,
    verify_first_receive_address_on_hw, bump_fee_if_rbf,
    verify_descriptor_sig_with_hw,
)

WALLET_NAME = "Reg34-HW-Sign-WSH-1of2"
HW_DERIVATION_PATH = "m/48'/1'/0'/2'"
PSBT_LABEL = "reg34-hw-wsh-selfpay"

COSIGNER_MFP = "ff81be5d"
COSIGNER_PATH = "48'/1'/0'/2'"
COSIGNER_XPUB = (
    "tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL"
    "7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K"
)


async def _add_cosigner_watchonly(d: UIDriver):
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_manual_entry(d)
    await fill_manual_keyspec(d, mfp=COSIGNER_MFP, path=COSIGNER_PATH,
                              xpub=COSIGNER_XPUB, compact=True)
    await wait_for(d, COSIGNER_MFP.lower(), "watch-only key card visible",
                   retries=15, delay=0.5)


async def _create_wallet(d: UIDriver):
    print("\n  [phase 1] create 1-of-2 wsh sortedmulti (HW + watch-only)")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened", retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "guided creation screen opened",
                   retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)
    await wait_for(d, "Singlesig", "wallet type segments visible",
                   retries=10, delay=0.5)
    await click_label(d, "Multisig", delay=0.5)
    await click_label(d, "SegWit", delay=0.4)

    print("\n  [phase 2] add HW key")
    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_hardware_wallet(d)
    await fill_field(d, "Derivation path", HW_DERIVATION_PATH)
    await click_label(d, "Confirm", delay=0.6)

    hw_mfp = await connect_hw_in_open_sheet(d, op_label="export xpub for wsh multisig")
    await click_label(d, "Export xpub", delay=0.5)
    await wait_for(d, hw_mfp, f"HW key card with MFP {hw_mfp} visible",
                   retries=30, delay=1.0)

    print("\n  [phase 3] add watch-only cosigner")
    await _add_cosigner_watchonly(d)

    # Default threshold = 1 ⇒ 1-of-2.
    await wait_for(d, "Required signatures: 1 of 2",
                   "threshold = 1 of 2", retries=10, delay=0.4)

    print("\n  [phase 4] create wallet")
    await click_label(d, "Create wallet", delay=0.5)
    await wait_for(d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
                   retries=60, delay=1.0)
    return hw_mfp


async def _register_on_hw(d: UIDriver):
    print("\n  [phase 5] register policy on HW (idempotent)")
    await click_label(d, "Hardware wallet", delay=0.5)
    await wait_for(d, "Register wallet", "HW Actions sheet opened",
                   retries=15, delay=0.6)
    await connect_hw_in_open_sheet(d, op_label="wsh multisig register")

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
        await wait_for_user("Confirm the wallet registration on the BitBox screen.")
        await wait_for(d, "registered on device",
                       "device confirms wallet registered",
                       retries=180, delay=1.0)
        await click_label(d, "Back", delay=0.5)
    else:
        print("    [info] policy was already registered from a previous run")
    await close_open_sheet(d)


async def _sync_or_fail(d: UIDriver):
    print("\n  [phase 6] sync — fail if no funds")
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
    print("\n  [phase 7] build self-pay MAX PSBT")
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
    print("\n  [phase 8] sign with HW")
    await click_label(d, "Sign with hardware wallet", delay=0.5)
    await connect_hw_in_open_sheet(d, op_label="sign wsh multisig PSBT")
    await click_label(d, "Sign transaction", delay=0.5)
    await wait_for_user("Confirm the transaction on the BitBox screen.")
    await wait_for(d, '"SIGNED"', "PSBT signed (SIGNED status)",
                   retries=180, delay=1.0)
    await wait_for(d, '"Broadcast"', "Broadcast button visible",
                   retries=10, delay=0.5)


async def _broadcast(d: UIDriver):
    print("\n  [phase 9] broadcast")
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


async def test_hw_sign_wsh_multisig(d: UIDriver):
    print(f"\n--- {WALLET_NAME} ---")
    await set_active_network_signet(d)
    await _create_wallet(d)
    await _register_on_hw(d)
    await verify_first_receive_address_on_hw(d, op_label="verify wsh multisig address")
    await _sync_or_fail(d)
    await _build_psbt(d)
    await _sign_with_hw(d)
    await _broadcast(d)

    print("\n  [phase 9] verify descriptor signature")
    await verify_descriptor_sig_with_hw(d, WALLET_NAME)

    print("\n  [phase 10] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)
    print(f"    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_hw_sign_wsh_multisig, "reg34"))
