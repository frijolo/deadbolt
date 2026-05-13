#!/usr/bin/env python3
"""
Regression test 30: Hardware wallet singlesig PSBT signing.

Covers the most common HW path: build a self-pay MAX PSBT in a singlesig
wallet that uses the HW key as its only signer, then sign it with the device.

Flow:
  1. Set Signet.
  2. Guided create wpkh wallet from HW xpub (m/84'/1'/0').
  3. Verify receive_address_0 on the device.
  4. Sync wallet. If balance == 0 → FAIL with the receive address printed.
  5. Send → self-pay MAX → Create PSBT → PSBT detail.
  6. Tap "Sign with hardware wallet" → confirm on device.
  7. Broadcast — assert the node accepts the tx.
  8. Cleanup: delete wallet.

Skips ONLY if no HW device is detected.

Exit code: 0 = PASS or SKIP, 1 = FAIL.
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
    open_watch_only_hardware_wallet,
)
from hw_helpers import (  # noqa: E402
    connect_hw_in_open_sheet, wait_for_user, close_open_sheet,
    extract_first_receive_address, fail_no_funds,
    verify_first_receive_address_on_hw, bump_fee_if_rbf,
    verify_descriptor_sig_with_hw,
)

WALLET_NAME = "Reg30-HW-Sign-WPKH"
DERIVATION_PATH = "m/84'/1'/0'"
PSBT_LABEL = "reg30-hw-selfpay"


async def _create_wallet_with_hw_xpub(d: UIDriver):
    print("\n  [phase 1] create singlesig wallet from HW xpub")
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Guided creation", "bottom sheet opened", retries=10, delay=0.5)
    await click_label(d, "Guided creation", delay=0.5)
    await wait_for(d, '"New Wallet"', "guided creation screen opened", retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)

    await click_label(d, "Add key", delay=0.5)
    await open_watch_only_hardware_wallet(d)
    await fill_field(d, "Derivation path", DERIVATION_PATH)
    await click_label(d, "Confirm", delay=0.6)

    mfp = await connect_hw_in_open_sheet(d, op_label="export xpub")
    await click_label(d, "Export xpub", delay=0.5)
    await wait_for(d, mfp, f"key card with MFP {mfp} visible", retries=30, delay=1.0)

    await click_label(d, "Create wallet", delay=0.5)
    await wait_for(
        d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
        retries=60, delay=1.0,
    )
    return mfp


async def _sync_and_check_funds(d: UIDriver):
    """Sync the wallet and skip the test if the wallet has no UTXOs."""
    print("\n  [phase 2] sync wallet — wait for UTXOs")
    await wait_for_tooltip(d, "Sync wallet", "sync button available")
    await click_label(d, "Coins", delay=1.0)
    # Allow up to 3 minutes for Signet sync
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
    print("    [ok] sync complete — confirmed UTXO present")
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview", retries=8, delay=0.5)


async def _build_self_pay_psbt(d: UIDriver):
    print("\n  [phase 3] build self-pay MAX PSBT")
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
    print("\n  [phase 4] sign with hardware wallet")
    await click_label(d, "Sign with hardware wallet", delay=0.5)
    # Sign sheet opens. Pairing was already done earlier in this test, but the
    # sheet still scans + connects fresh; reuse the helper.
    await connect_hw_in_open_sheet(d, op_label="sign PSBT")
    await click_label(d, "Sign transaction", delay=0.5)
    await wait_for_user(
        "Review the inputs/outputs on the BitBox screen and confirm the "
        "signature."
    )
    # The "Sign with hardware wallet" button stays visible even after signing
    # (you can re-sign), so we can't use wait_absent on it. Instead wait for
    # the PSBT detail to render the SIGNED status badge / Broadcast button.
    await wait_for(d, '"SIGNED"', "PSBT signed (SIGNED status)",
                   retries=180, delay=1.0)
    await wait_for(d, '"Broadcast"', "Broadcast button visible",
                   retries=10, delay=0.5)
    print("    [ok] PSBT signed by hardware wallet")


async def _broadcast(d: UIDriver):
    print("\n  [phase 5] broadcast")
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


async def test_hw_sign_singlesig(d: UIDriver):
    print(f"\n--- {WALLET_NAME} ---")

    await set_active_network_signet(d)
    await _create_wallet_with_hw_xpub(d)
    await verify_first_receive_address_on_hw(d, op_label="verify P2WPKH address")
    await _sync_and_check_funds(d)
    await _build_self_pay_psbt(d)
    await _sign_with_hw(d)
    await _broadcast(d)

    print("\n  [phase 6] verify descriptor signature")
    await verify_descriptor_sig_with_hw(d, WALLET_NAME)

    print("\n  [phase 7] cleanup")
    await delete_wallet_from_list(d, WALLET_NAME)
    print(f"    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_hw_sign_singlesig, "reg30"))
