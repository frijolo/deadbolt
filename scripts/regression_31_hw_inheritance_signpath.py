#!/usr/bin/env python3
"""
Regression test 31: HW signing on a complex taproot inheritance descriptor
                    where the BitBox key appears in MULTIPLE script leaves
                    with different multipath chain indices.

This is the exact regression the suite was built to catch: the same HW key
(MFP 4061aff0) appears in 5 distinct leaves with chain indices `<0;1>`,
`<2;3>`, `<4;5>`, `<6;7>` and `<8;9>`. The device-side firmware would sign
the wrong leaf unless `signerChainIndex` (a.k.a. `keyChanges` in Dart) is
passed correctly. The fix in `psbt_detail_screen.dart` filters tap_key_origins
so the BB02 only sees the leaf entry whose chain index matches the
user-selected spend path.

Flow:
  1. Set Signet.
  2. Import the inheritance descriptor as a project, then create a wallet
     from the project (Device-key protection, Signet).
  3. Sync. If no UTXOs → print first receive address and SKIP.
  4. Build a self-pay MAX PSBT using the default spend path.
  5. Sign with the BitBox (the device must sign through the correct leaf).
  6. Verify the PSBT becomes SIGNED + Broadcast available.
  7. Cleanup: delete wallet + project (no broadcast).

Skips cleanly if no HW device is detected OR if the wallet has no funds.

Pre-requisite: the connected BitBox holds the seed whose MFP is 4061aff0
(any HW signer with that fingerprint can produce the signatures expected
by this descriptor).

Exit code: 0 = PASS or SKIP, 1 = FAIL.
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
    create_project, create_wallet_from_project,
    wait_for_tooltip, run_regression,
)
from hw_helpers import (  # noqa: E402
    connect_hw_in_open_sheet, wait_for_user, close_open_sheet,
    extract_first_receive_address, fail_no_funds,
    verify_first_receive_address_on_hw,
    verify_descriptor_sig_with_hw,
)

PROJECT_NAME = "Reg31-HW-Inherit"
WALLET_NAME = "Reg31-HW-Inherit-TR"
PSBT_LABEL = "reg31-hw-multileaf"

# Taproot inheritance descriptor where the HW key (MFP 4061aff0) appears in
# FIVE different script leaves with multipath indices <0;1>, <2;3>, <4;5>,
# <6;7> and <8;9>. The internal key (no MFP origin) is unspendable.
DESCRIPTOR = (
    "tr("
    "tpubD6NzVbkrYhZ4WgRd5dPVwkWEXmzmAuLiJr8SZEtVgsYuE5d5dXLNwf4aFjftJTncXjMPAZmsoUfB615QLkSoqCxkMpKVFcPA4iCf5giaNYT/<0;1>/*,"
    "{"
      "and_v(v:and_v(v:pk("
        "[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<0;1>/*"
      "),pk("
        "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<0;1>/*"
      ")),older(1)),"
      "{"
        "{"
          "and_v(v:multi_a(2,"
            "[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<2;3>/*,"
            "[f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<0;1>/*,"
            "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<2;3>/*"
          "),older(2)),"
          "and_v(v:multi_a(2,"
            "[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<4;5>/*,"
            "[a045ca01/48'/1'/0'/2']tpubDE2KGCrYbgcNjvSyHG9ytdgR5LhGj8GvWpCGgcMvsTZnuuqE259tatGFhTbg2BvRfoziW4soM8Mhgk6juTAKNaM19GauMPEerjbeY2R2p9J/<0;1>/*,"
            "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<4;5>/*"
          "),older(3))"
        "},"
        "{"
          "and_v(v:multi_a(2,"
            "[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<6;7>/*,"
            "[ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<0;1>/*,"
            "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<6;7>/*"
          "),older(4)),"
          "{"
            "and_v(v:multi_a(1,"
              "[4061aff0/48'/1'/0'/2']tpubDFAv39stw4ELPsWiyqNL2UcFwruoVdX89CEpzJwb1TV3k9JgW6tLPUicWJvRT5iUSH7HHdt6rXtgRSX5TWJZqDcwJZZTtj1WTcHLUCC7eXC/<8;9>/*,"
              "[ff81be5d/48'/1'/0'/2']tpubDDxjvuVfYHF4KcVyd5wkNS6pKJvg1x6CUtCRL3nRX2MDHKcja6M7YB7FYFYDkXzx8fL7k9bYi8XDpfPetqvd6ER2VYt1WsQSHYnhhT2EX7K/<8;9>/*"
            "),older(5)),"
            "and_v(v:multi_a(1,"
              "[a045ca01/48'/1'/0'/2']tpubDE2KGCrYbgcNjvSyHG9ytdgR5LhGj8GvWpCGgcMvsTZnuuqE259tatGFhTbg2BvRfoziW4soM8Mhgk6juTAKNaM19GauMPEerjbeY2R2p9J/<2;3>/*,"
              "[ca6205d9/48'/1'/0'/2']tpubDE7Kf5xBnX5qHJKbAk3JdzxRg1hjoaxHkwCQBQHTAR32NYr6BKhbN78hENp59actsGTsUKjrqhTXCXbmW4hy5NGc5s1Ap9Mx66cKzvyzWaT/<2;3>/*,"
              "[f3d33d4f/48'/1'/0'/2']tpubDFLYS7v5vvjyhLMotrmn6KzdN46jJ8ife9yD8DUMygtNCR4U389Wr46vJj7kG9bJPqFmLSet7hAP5fVJvyc97x9fhKZ7Zm9cTdvMxHqT55h/<2;3>/*"
            "),older(6))"
          "}"
        "}"
      "}"
    "}"
    ")#2fdut6vr"
)


async def _import_and_create_wallet(d: UIDriver):
    print("\n  [phase 1] import descriptor as project")
    await create_project(d, PROJECT_NAME, DESCRIPTOR)

    print("\n  [phase 2] create wallet from project (Device key, Signet)")
    # Inline create-wallet flow: the upstream helper's final click on
    # 'Create wallet' fails for this complex inheritance form because the
    # button sits well below the visible viewport and Flutter only emits
    # semantics for rendered widgets. We scroll the form before clicking.
    from regression_helpers import click_popup_item  # noqa: WPS433
    await click_popup_item(d, "More options", 72, "Create wallet")
    await wait_for(d, '"New Wallet"', "Create wallet screen opened",
                   retries=10, delay=0.5)
    await fill_field(d, "Wallet name", WALLET_NAME)
    # Tab out of the text field so scroll-wheel events reach the form, not the
    # focused field. Without this the scroll is silently swallowed.
    d.key("Tab")
    await asyncio.sleep(0.3)
    # Scroll all the way down so the FilledButton at the bottom enters the
    # render tree and emits semantics.
    d.scroll_down(15)
    await asyncio.sleep(0.8)
    await wait_for(d, '"Create wallet"', "Create wallet button visible",
                   retries=20, delay=0.5)
    await click_label(d, "Create wallet", delay=0.5)
    await wait_for(
        d, '"Receive"', f"wallet detail loaded: '{WALLET_NAME}'",
        retries=90, delay=1.0,
    )


async def _sync_or_skip(d: UIDriver):
    print("\n  [phase 3] sync wallet — wait for UTXOs")
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
    print("    [ok] sync complete — confirmed UTXO present")
    await click_label(d, "Overview", delay=0.5)
    await wait_for(d, '"Send"', "back on Overview", retries=8, delay=0.5)


async def _register_policy_on_hw(d: UIDriver):
    """Register the wallet policy on the BitBox02 (idempotent).

    BB02 firmware refuses to sign a multi-leaf taproot policy unless that exact
    policy template is registered. We open the HW Actions sheet, run a
    Check Registration, and only register if the device says it's missing.
    """
    print("\n  [phase 3.5] register policy on HW (idempotent)")
    await click_label(d, "Hardware wallet", delay=0.5)
    await wait_for(d, "Register wallet", "HW Actions sheet opened",
                   retries=15, delay=0.6)
    await connect_hw_in_open_sheet(d, op_label="register policy")

    await click_label(d, "Check registration", delay=0.5)
    initial_state = None
    for _ in range(30):
        flat = await d.cs_flat_text()
        if "NOT registered" in flat:
            initial_state = "absent"
            break
        if "is registered on this device" in flat:
            initial_state = "present"
            break
        await asyncio.sleep(1.0)
    if initial_state is None:
        raise AssertionError("Check registration did not report a known state")
    print(f"    [ok] initial check → {initial_state}")
    await click_label(d, "Back", delay=0.5)

    if initial_state == "absent":
        print("    [step] register policy on device")
        await click_label(d, "Register wallet", delay=0.5)
        await wait_for_user(
            "Approve the policy registration on the BitBox screen."
        )
        await wait_for(d, "registered on device",
                       "device confirms wallet was just registered",
                       retries=180, delay=1.0)
        print("    [ok] policy registered on device")
        await click_label(d, "Back", delay=0.5)
    else:
        print("    [info] policy was already registered — skipping")

    await close_open_sheet(d)
    await wait_for(d, '"Send"', "back on Overview", retries=10, delay=0.5)


async def _build_and_sign(d: UIDriver):
    print("\n  [phase 4] build self-pay MAX PSBT (1-of-2 spend path)")
    await click_label(d, "Send", delay=0.5)
    await wait_for(d, '"Create Transaction"', "Create TX screen opened",
                   retries=10, delay=0.5)

    # Order: recipient → spend path → UTXO selection. Selecting the UTXO LAST
    # is the stable approach because changing the spend path resets the prior
    # coin selection (the cubit auto-deselects coins that don't match the new
    # path), so any UTXO ticked beforehand would be lost — leading to off-by-
    # one selection bugs in the coin selector.
    await fill_field(d, "Label", PSBT_LABEL)
    await click_tooltip(d, "MY WALLETS", delay=0.5)
    await wait_for(d, "This wallet (Self)", "wallet picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "This wallet (Self)", delay=1.5)

    # Pick the 1-of-2 spend path (HW + heir1, older(5) leaf) so that the HW
    # alone is enough to sign. Path is selected via the DropdownButtonFormField
    # whose current value is shown as "Spend path\n<label>\n<lock>".
    print("    [step] open spend path dropdown")
    d.scroll_down(4)
    await asyncio.sleep(0.4)
    rect = await d.cs_find_by_label_part_containing("Spend path")
    if rect is None:
        raise AssertionError("Spend path dropdown not found")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy, delay_s=0.5)
    await asyncio.sleep(0.6)
    await wait_for(d, "1-of-2", "1-of-2 entry visible in dropdown",
                   retries=10, delay=0.5)
    # The full label is "1-of-2 (4061 + FF81)\nUnlocked" — click_label requires
    # an exact part match, so use cs_find_by_label_part_containing instead.
    item_rect = await d.cs_find_by_label_part_containing("1-of-2")
    if item_rect is None:
        raise AssertionError("'1-of-2' dropdown entry not clickable")
    ix = (item_rect[0] + item_rect[2]) // 2
    iy = (item_rect[1] + item_rect[3]) // 2
    d.flutter_click(ix, iy, delay_s=0.5)
    await asyncio.sleep(0.6)

    # ── Step C: with the 1-of-2 spend path active, open the coin selector for
    # the FIRST time. Each tile now shows the per-path timelock badge; we
    # pick a tile tagged "Unlocked".
    print("    [step] open coin selector to pick an Unlocked UTXO")
    await click_label(d, "Tap to select coins...", delay=1.0)
    await wait_for(d, "sats", "coin selector opened", retries=10, delay=0.5)
    await asyncio.sleep(0.6)

    tree = await d.cs_tree()
    unlocked_tiles = []
    selected_tile = None
    for n in tree:
        label = (n.get("label") or "")
        # Coin tile titles look like "<num> sats" with badges as multi-line
        # subtitle (`Receive`, `Change`, `Unlocked`, `Unconfirmed`, `+N blocks`).
        if not ("sats" in label and "tb1" in label):
            continue
        r = d._cs_rect(n)
        if r is None:
            continue
        is_unlocked = "Unlocked" in label
        # The semantics tree exposes the Checkbox node separately; the tile
        # label itself doesn't say "selected", so we can't detect that here.
        if is_unlocked:
            unlocked_tiles.append((label, r))
        if selected_tile is None and not is_unlocked:
            selected_tile = (label, r)

    if not unlocked_tiles:
        raise AssertionError(
            "No UTXO is Unlocked for the 1-of-2 (older(5)) spend path. Wait "
            "for the most recent change UTXO to reach 5 confirmations on "
            "Signet and rerun."
        )

    target_label, target_rect = unlocked_tiles[0]
    print(f"    [ok] target Unlocked UTXO: {target_label[:50]}")

    # Selection count is exposed via the "Done (N)" button label. After
    # changing the spend path, the previously-selected UTXO may have been
    # auto-deselected by the cubit, so we cannot assume the prior selection
    # survived. Probe the current count and act accordingly.
    async def _selection_count() -> int:
        flat_now = await d.cs_flat_text()
        import re as _re
        m = _re.search(r"Done \((\d+)\)", flat_now)
        if m:
            return int(m.group(1))
        if '"Done"' in flat_now:
            return 0
        return -1

    # Tap the target to select it. (If it was already selected for some
    # reason this would deselect — handled below.)
    tx = (target_rect[0] + target_rect[2]) // 2
    ty = (target_rect[1] + target_rect[3]) // 2
    d.flutter_click(tx, ty)
    await asyncio.sleep(0.6)

    count = await _selection_count()
    print(f"    [step] selection count after target tap = {count}")

    # If count > 1, deselect every non-target tile by tapping it. We rely on
    # tile coordinates captured before the tap (selection toggling does not
    # re-layout the list).
    if count > 1:
        for lbl, rect in [(label, _r) for n in tree
                          for label in [(n.get("label") or "")]
                          for _r in [d._cs_rect(n)]
                          if _r is not None
                          and "sats" in label and "tb1" in label
                          and label != target_label]:
            cx = (rect[0] + rect[2]) // 2
            cy = (rect[1] + rect[3]) // 2
            d.flutter_click(cx, cy)
            await asyncio.sleep(0.4)
            count = await _selection_count()
            if count == 1:
                break
    elif count == 0:
        # Re-tap target — first tap may have landed on a chip/badge.
        d.flutter_click(tx, ty)
        await asyncio.sleep(0.5)
        count = await _selection_count()

    if count != 1:
        raise AssertionError(
            f"Could not converge to exactly 1 UTXO selected (current={count})"
        )

    await click_label(d, "Done (1)", delay=1.0)
    await wait_for(d, '"Create Transaction"', "back on Create TX screen",
                   retries=10, delay=0.5)
    # Confirm the selected path now shows 1-of-2.
    await wait_for(d, "Spend path", "spend path field still rendered",
                   retries=5, delay=0.4)
    print("    [ok] 1-of-2 spend path selected")

    await click_label(d, "MAX", delay=0.8)
    await wait_absent(d, '"— sats"', "MAX amount computed", retries=40, delay=0.5)

    # If a previous run already broadcast a tx that's still in the mempool and
    # we picked the parent UTXO, the form switches to BIP-125 RBF mode and
    # demands a higher absolute fee than the original. Tapping the
    # "Fee (sats)" field auto-fills the minimum (`rbfMinFeeSats` from preview)
    # via _buildFeeField.onEditTap. We then commit with Enter.
    flat = await d.cs_flat_text()
    if "Full-RBF replacement" in flat or "Minimum fee" in flat:
        print("    [step] RBF replacement detected — bumping to min fee")
        rect = await d.cs_find_by_label_part_containing("total_fee_display")
        if rect is None:
            raise AssertionError("Could not find total fee field (RBF auto-bump)")
        cx = (rect[0] + rect[2]) // 2
        cy = (rect[1] + rect[3]) // 2
        d.flutter_click(cx, cy, delay_s=0.5)
        await asyncio.sleep(0.6)
        # The field now contains the min fee value; commit and recompute summary.
        d.key("Return")
        await asyncio.sleep(0.8)
        # MAX amount adjusts when fee changes — wait for stable summary.
        await wait_absent(d, '"— sats"', "summary recomputed after fee bump",
                          retries=40, delay=0.5)
        print("    [ok] fee bumped to RBF minimum")

    await click_label(d, "Create PSBT", delay=0.5)
    await wait_for(d, '"Unsigned Transaction"', "PSBT detail opened",
                   retries=15, delay=1.0)

    print("\n  [phase 5] sign with hardware wallet (multi-leaf descriptor)")
    await click_label(d, "Sign with hardware wallet", delay=0.5)
    await connect_hw_in_open_sheet(d, op_label="sign multi-leaf PSBT")
    await click_label(d, "Sign transaction", delay=0.5)
    await wait_for_user(
        "On the BitBox: review the inputs/outputs and approve the signature. "
        "If the device shows an error about descriptor mismatch / wrong leaf, "
        "the regression has reproduced — capture the error."
    )
    await wait_for(d, '"SIGNED"', "PSBT shows SIGNED badge",
                   retries=240, delay=1.0)
    # Stronger assertion: the PSBT detail renders "Signatures (X/Y of Z)" where
    # X = sigs provided, Y = sigs required, Z = total possible signers. We need
    # X == Y (all required present). For our 1-of-2 leaf the label reads
    # "Signatures (1/1 of 2)". In the previous regression Flutter still painted
    # "SIGNED" while X < Y and the final tx couldn't be extracted — so this
    # assertion is what actually catches the bug at the UI level.
    await wait_for(d, "Signatures (1/1 of",
                   "all required signatures present (X/X)",
                   retries=20, delay=0.5)
    print("    [ok] PSBT signed by HW through the selected spend path")

    # Final regression check: actually broadcast the transaction. In the
    # original bug the PSBT looked signed but the network rejected the final
    # tx — only `_broadcast` exposed the failure. On Signet this is harmless
    # (self-pay, ~0 cost).
    print("\n  [phase 6] broadcast the signed PSBT")
    await click_label(d, "Broadcast", delay=0.8)
    # The success path emits a toast like "Transaction broadcast! TXID: ..."
    # The failure path emits "Broadcast failed: <error>". Wait for either.
    success = False
    for _ in range(60):
        flat = await d.cs_flat_text()
        if "Transaction broadcast" in flat:
            success = True
            break
        if "Broadcast failed" in flat:
            raise AssertionError(
                "Broadcast failed — the signed PSBT was rejected by the "
                "network. This is the regression scenario."
            )
        await asyncio.sleep(1.0)
    if not success:
        raise AssertionError("Broadcast did not produce a success or failure toast")
    print("    [ok] transaction broadcast accepted by the Signet network")


async def _cleanup(d: UIDriver):
    print("\n  [phase 7] cleanup")
    await go_back_to_wallet_list(d)
    await delete_wallet_from_list(d, WALLET_NAME)

    # Also delete the project so reruns start clean. navigate_designer waits
    # for "No projects" (empty marker) and would fail because our project is
    # still there — swallow that specific case and verify by AppBar title.
    try:
        await navigate_designer(d)
    except AssertionError:
        pass
    await wait_for(d, '"Projects"', "back on project list", retries=10, delay=0.5)
    flat = await d.cs_flat_text()
    if PROJECT_NAME in flat:
        await delete_project_from_list(d, PROJECT_NAME)


async def test_hw_inheritance_signpath(d: UIDriver):
    print(f"\n--- {WALLET_NAME} ---")

    await set_active_network_signet(d)
    await _import_and_create_wallet(d)
    await _register_policy_on_hw(d)
    await verify_first_receive_address_on_hw(
        d, op_label="verify TR multi-leaf address"
    )
    await _sync_or_skip(d)
    await _build_and_sign(d)

    print("\n  [phase 6] verify descriptor signature")
    await verify_descriptor_sig_with_hw(d, WALLET_NAME)

    await _cleanup(d)
    print(f"    [PASS] {WALLET_NAME}")


if __name__ == "__main__":
    asyncio.run(run_regression(test_hw_inheritance_signpath, "reg31"))
