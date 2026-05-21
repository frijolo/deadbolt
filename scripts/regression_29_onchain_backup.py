#!/usr/bin/env python3
"""
Regression test 29: On-chain descriptor backup — recovery + create-flow
coherence check (no broadcast).

The test runs in sandbox (empty app data), recovers a hot wallet from a
known mnemonic that already has an on-chain backup published on Signet,
and exercises the on-chain backup screen end-to-end without broadcasting.

Phases:
  1. Set Active Network → Signet
  2. Recover hot wallet from mnemonic via Recover Wallet → Seed → SegWit.
  3. Open the on-chain backup screen and verify _buildBackupExists shows
     commit txid, a reveal txid (or pending notice), anchors-health line,
     and "Descriptor verified" if all anchors are reachable.
  4. Tap "Create new backup" → utxo selection.
  5. Pick the first available UTXO; set fee rate to 50 sat/vB.
  6. Build TX_COMMIT.
  7. Sign with the wallet's hot key.
  8. Confirm-broadcast view: parse vault, anchors × amount, optional
     change, commit fee, reveal fee, optional reveal change, package
     total fee, package vbytes; assert
       commit_fee + reveal_fee == total_fee_displayed
       anchor_amount == 330
       package_vb > 0, vault > 0, fees > 0
  9. Press Back to return to awaiting-signature, then Back again to
     return to utxo selection.  NEVER click "Broadcast".

Exit code: 0 = PASS, 1 = FAIL.

Usage:
    bash scripts/prepare_test_build.sh
    python3 scripts/regression_29_onchain_backup.py
"""

import asyncio
import os
import re
import sys
from pathlib import Path
import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ui_driver import UIDriver                              # noqa: E402
from regression_helpers import (                           # noqa: E402
    wait_for, click_label, click_tooltip, fill_field,
    set_active_network_signet, dismiss_startup_dialogs,
    navigate_wallets, run_regression,
)


# 12-word BIP39 mnemonic of a Signet wallet that already has an on-chain
# backup published. The Taproot keyspec derived from this mnemonic is the
# anchor key the on-chain backup recovery scanner looks for.
MNEMONIC = (
    "bachelor brick camera brave assume differ disagree "
    "judge security scrap wonder oval"
)

# Fee rate (sat/vB) used to build the backup commit — high enough that the
# resulting commit/reveal package will cleanly outpace any unconfirmed parent
# or replaced transaction left by previous runs against the same wallet.
HIGH_FEE_RATE = "50"


# ---------------------------------------------------------------------------
# Backup screen helpers
# ---------------------------------------------------------------------------

async def _open_publish_backup_sheet(d):
    """Wallet detail → More options → Export → Descriptor → Publish Backup → On-chain."""
    await click_tooltip(d, "More options", delay=0.6)
    await click_label(d, "Export", delay=0.6)
    await wait_for(d, "Descriptor", "Export choice sheet open")
    await click_label(d, "Descriptor", delay=0.6)
    await wait_for(d, "Publish Backup", "Descriptor export sheet open")
    await click_label(d, "Publish Backup", delay=0.6)
    flat = await d.cs_flat_text()
    # Singlesig wallets get an info panel first; click the "I understand"
    # link if it's there.
    if "Backup not recommended" in flat:
        try:
            await click_label(d, "I understand, show options anyway", delay=0.4)
        except AssertionError:
            pass
    await wait_for(d, '"On-chain"', "Publish backup options visible")
    await click_label(d, "On-chain", delay=1.0)


async def _wait_backup_screen_phase(d, retries=40, delay=1.0):
    """Return 'exists' | 'utxo' | 'failed' once the backup screen settles."""
    for _ in range(retries):
        flat = await d.cs_flat_text()
        if "Backup already exists" in flat:
            return "exists"
        if "Build TX_COMMIT" in flat:
            return "utxo"
        if "Retry" in flat and "Backup already exists" not in flat:
            return "failed"
        await asyncio.sleep(delay)
    raise AssertionError("Timeout waiting for on-chain backup screen to settle")


# ---------------------------------------------------------------------------
# Phase 2: recover hot wallet from mnemonic
# ---------------------------------------------------------------------------

async def _open_recovery_screen(d):
    await navigate_wallets(d)
    await click_tooltip(d, "New")
    await wait_for(d, "Recover Wallet", "bottom sheet opened")
    await click_label(d, "Recover Wallet", delay=0.5)
    await wait_for(d, 'Restoring to:', "Recover Wallet screen opened")


async def _recover_wallet_from_onchain_backup(d):
    """Recover the wallet by importing its on-chain backup.

    Recovery flow (Seed tab → Taproot): the scanner derives the Taproot
    keyspec from the mnemonic and queries Electrum for any descriptor
    backup whose anchors are funded by that key. The backup contains the
    full descriptor (which may be multisig). We import the backup via the
    "On-chain" icon button on the matching card — NOT the "Create wallet"
    button (which would just create a fresh singlesig from the seed).
    """
    print("\n  [phase 2] Recover wallet from on-chain backup")
    await _open_recovery_screen(d)

    await click_label(d, "Seed", delay=0.5)
    await wait_for(d, "word1 word2 word3 ...", "Seed tab active",
                   retries=8, delay=0.5)

    await click_label(d, "Taproot", delay=0.5)

    mnemonic_rect = await d.cs_find_textfield_by_label("word1 word2 word3 ...")
    if mnemonic_rect is None:
        raise AssertionError("Mnemonic text field not found in Seed tab")
    cx = (mnemonic_rect[0] + mnemonic_rect[2]) // 2
    cy = (mnemonic_rect[1] + mnemonic_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.4)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    _env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(["xclip", "-selection", "clipboard"],
                   input=MNEMONIC.encode(), env=_env, check=True)
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.5)
    print("    [ok] mnemonic entered")

    await click_label(d, "Scan accounts", delay=0.5)

    # Wait for the on-chain backup card to appear (tooltip 'On-chain').
    # Retry on transient scan failures.
    onchain_rect = None
    for attempt in range(3):
        for _ in range(180):
            sem = await d.cs_flat_text()
            if '"Retry"' in sem and "Backup" not in sem:
                break
            onchain_rect = await d.cs_find_by_tooltip("On-chain")
            if onchain_rect is not None:
                break
            await asyncio.sleep(2.0)
        if onchain_rect is not None:
            break
        sem = await d.cs_flat_text()
        if '"Retry"' in sem:
            print("    [warn] scan failed, retrying…")
            await click_label(d, "Retry", delay=1.0)
            await asyncio.sleep(2.0)
            continue
        break
    if onchain_rect is None:
        raise AssertionError(
            "No on-chain backup discovered for this mnemonic — expected at "
            "least one card with the 'On-chain' import action"
        )
    print("    [ok] on-chain backup discovered")

    # Click the 'On-chain' tooltip IconButton to import the descriptor backup.
    d.flutter_click((onchain_rect[0] + onchain_rect[2]) // 2,
                    (onchain_rect[1] + onchain_rect[3]) // 2)
    await asyncio.sleep(0.6)

    # Confirmation dialog: 'Verify after import' → tap 'Import Wallet'.
    await wait_for(d, "Verify after import", "import-confirm dialog visible",
                   retries=10, delay=0.5)
    await click_label(d, "Import Wallet", delay=1.0)

    # Import navigates straight to wallet detail (no SimpleWalletDialog).
    await wait_for(d, '"Receive"', "wallet detail loaded after import",
                   retries=60, delay=1.0)
    print("    [ok] descriptor imported — wallet detail opened")

    # Trigger a sync — descriptor import does not auto-sync the freshly
    # imported wallet on every code path. Then wait for UTXOs in the Coins tab.
    if await d.cs_find_by_tooltip("Sync wallet") is not None:
        await click_tooltip(d, "Sync wallet", delay=1.0)
    await click_label(d, "Coins", delay=1.0)
    for _ in range(120):
        sem_coins = await d.cs_flat_text()
        if '" sats"' in sem_coins or "sats\n" in sem_coins or "sats " in sem_coins:
            if '"No coins.' not in sem_coins:
                break
        # Re-trigger sync periodically if it idles back to "No coins".
        await asyncio.sleep(1.5)
    else:
        raise AssertionError(
            "Coins tab still shows 'No coins' after sync — recovered wallet "
            "has no UTXOs to fund the backup commit"
        )
    print("    [ok] sync complete — UTXOs available")


# ---------------------------------------------------------------------------
# View verifiers
# ---------------------------------------------------------------------------

_NUM_RX = r"[0-9][0-9,\.\s ]*"


def _to_int(s: str) -> int:
    return int(re.sub(r"[^\d]", "", s))


async def _verify_backup_exists_view(d):
    print("\n  [phase 3] Verify backup-exists view")
    flat = await d.cs_flat_text()
    assert "Backup already exists" in flat, "header missing"
    assert "TX_COMMIT" in flat, "TX_COMMIT label missing"
    if "TX_REVEAL not yet published" in flat:
        print("    [warn] TX_REVEAL still pending — recovery half-published")
    else:
        assert "TX_REVEAL" in flat, "TX_REVEAL label missing"

    m = re.search(r"(\d+)\s+of\s+(\d+)\s+anchors\s+accessible", flat)
    assert m, "anchors-health line missing"
    reachable, total = int(m.group(1)), int(m.group(2))
    assert total >= 1, "expected at least 1 anchor"
    assert reachable <= total, "reachable cannot exceed total"
    print(f"    [ok] anchors {reachable}/{total} accessible")

    txids = re.findall(r"\b[0-9a-f]{64}\b", flat)
    assert len(txids) >= 1, "no txid present in semantics"
    print(f"    [ok] {len(txids)} txid(s) shown")

    if reachable == total and "TX_REVEAL not yet published" not in flat:
        assert "Descriptor verified" in flat, (
            "all anchors reachable but 'Descriptor verified' absent"
        )
        print("    [ok] descriptor verified")

    assert reachable >= 3, (
        f"expected at least 3 accessible anchors, got {reachable}"
    )
    print(f"    [ok] {reachable} anchors accessible (≥ 3)")


async def _enter_create_flow(d):
    print("\n  [phase 4] Tap 'Create new backup' → utxo selection")
    await click_label(d, "Create new backup", delay=1.0)
    await wait_for(
        d, '"Build TX_COMMIT"', "utxo-selection screen visible",
        retries=30, delay=0.8,
    )


async def _select_first_utxo(d):
    print("\n  [phase 5a] Open coin selector and pick the first UTXO")
    rect = (
        await d.cs_find_label_containing("Tap to select coins")
        or await d.cs_find_label_containing("Select a coin with at least")
        or await d.cs_find_label_containing("No coins selected")
        or await d.cs_find_label_containing("coins selected")
        or await d.cs_find_label_containing("UTXOs available")
    )
    if rect is None:
        raise AssertionError("Coin-selector card not found")
    flat = await d.cs_flat_text()
    if "No UTXOs available" in flat:
        raise AssertionError(
            "Wallet has no UTXOs — cannot exercise the backup-build flow"
        )
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(1.5)
    await wait_for(d, '"Select coins"', "coin selector opened",
                   retries=10, delay=0.5)

    # Tap the first "X sats" coin row.  cs_find_all_label_containing returns
    # in tree order, so the first match is the topmost row.
    rows = await d.cs_find_all_label_containing(" sats")
    target = None
    for r in rows:
        if (r[3] - r[1]) >= 30:           # skip bare badge labels
            target = r
            break
    if target is None:
        raise AssertionError("No coin rows visible in coin selector")
    d.flutter_click((target[0] + target[2]) // 2,
                    (target[1] + target[3]) // 2)
    await asyncio.sleep(0.8)
    # Done button: label "Done" or "Done (N)"
    done = (
        await d.cs_find_by_label_part_containing("Done")
        or await d.cs_find_label_containing("Done")
    )
    if done is None:
        raise AssertionError("Coin-selector 'Done' button missing")
    d.flutter_click((done[0] + done[2]) // 2, (done[1] + done[3]) // 2)
    await asyncio.sleep(1.2)
    print("    [ok] one coin selected")


async def _promote_key_to_hot(d):
    """Recovery via on-chain backup imports the wallet as watch-only — the
    descriptor blob carries no key material. Promote the BC0DBBCE key to
    hot by tapping the 'Add private key' button below the keys list and
    pasting the mnemonic; the destination is inferred from the MFP."""
    print("\n  [phase 2b] Promote BC0DBBCE key to hot (attach mnemonic)")
    await click_label(d, "Descriptor", delay=1.0)
    # Descriptor view has sub-tabs: Spend paths / Keys / Descriptor.
    # Switch to Keys so the global 'Add private key' button is visible.
    keys_tab = await d.cs_find_label_containing("Keys (")
    if keys_tab is None:
        raise AssertionError("Keys sub-tab not found in Descriptor view")
    d.flutter_click((keys_tab[0] + keys_tab[2]) // 2,
                    (keys_tab[1] + keys_tab[3]) // 2)
    await asyncio.sleep(0.6)
    await wait_for(d, "BC0DBBCE", "key card visible in Keys sub-tab",
                   retries=15, delay=0.6)

    # Tap the global 'Add private key' button below the keys list.
    # The sheet opens directly on the hot-sources picker (walletMode).
    await wait_for(d, "Add private key",
                   "Add private key button visible below keys list",
                   retries=10, delay=0.5)
    await click_label(d, "Add private key", delay=0.8)
    await wait_for(d, '"Enter existing mnemonic"',
                   "addPrivateKeySheet hot-sources picker visible",
                   retries=8, delay=0.5)
    await click_label(d, "Enter existing mnemonic", delay=0.6)

    # Wallet-mode seed form is opened on the Mnemonic tab by default.
    await wait_for(d, "word1 word2 word3 ...", "mnemonic field ready",
                   retries=15, delay=0.5)

    mnemonic_rect = await d.cs_find_textfield_by_label("word1 word2 word3 ...")
    if mnemonic_rect is None:
        raise AssertionError("Mnemonic text field not found in wallet seed form")
    cx = (mnemonic_rect[0] + mnemonic_rect[2]) // 2
    cy = (mnemonic_rect[1] + mnemonic_rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.4)
    d.key("ctrl+a")
    await asyncio.sleep(0.1)
    _env = {**os.environ, "DISPLAY": ":0"}
    subprocess.run(["xclip", "-selection", "clipboard"],
                   input=MNEMONIC.encode(), env=_env, check=True)
    await asyncio.sleep(0.1)
    d.key("ctrl+v")
    await asyncio.sleep(0.6)

    # Wait for the validating MFP preview to settle on a green check.
    for _ in range(20):
        sem = await d.cs_flat_text()
        if "MFP: bc0dbbce" in sem.lower() or "MFP: BC0DBBCE" in sem:
            break
        await asyncio.sleep(0.5)

    # Submit — the sheet has TWO 'Add private key' labels (the dialog title
    # and the submit button). Click the bottom-most occurrence.
    rects = await d.cs_find_all_label_containing("Add private key")
    if not rects:
        raise AssertionError("'Add private key' submit button not found")
    submit = max(rects, key=lambda r: r[1])
    d.flutter_click((submit[0] + submit[2]) // 2,
                    (submit[1] + submit[3]) // 2)
    await asyncio.sleep(2.0)
    # Sheet closes and we land back on the Keys sub-tab.
    await wait_for(d, "BC0DBBCE", "back on Keys sub-tab after promotion",
                   retries=20, delay=0.6)
    print("    [ok] mnemonic attached — BC0DBBCE is now hot")


async def _select_spend_path(d):
    """Multisig wallets surface a 'Spend path' dropdown that defaults to
    nothing selected — leaving it unset makes Build TX_COMMIT compute a
    zero-fee no-op. Pick the singlesig path controlled by the recovered
    hot key (fingerprint BC0DBBCE) so the build can proceed."""
    print("\n  [phase 5c] Select spend path")
    rect = await d.cs_find_label_containing("Spend path")
    if rect is None:
        # Singlesig wallets have no dropdown — nothing to do.
        print("    [skip] no spend-path picker present")
        return
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    await asyncio.sleep(0.2)
    # Pick the path that includes 'BC0D' — the recovered hot key fingerprint.
    pick = (
        await d.cs_find_label_containing("BC0D")
        or await d.cs_find_label_containing("1-of-1")
    )
    if pick is None:
        raise AssertionError("Spend-path dropdown opened but no '1-of-1 (BC0D)' option visible")
    d.flutter_click((pick[0] + pick[2]) // 2, (pick[1] + pick[3]) // 2)
    await asyncio.sleep(0.2)
    print("    [ok] spend path '1-of-1 (BC0D)' selected")


async def _set_fee_rate_high(d):
    print(f"\n  [phase 5b] Set fee rate to {HIGH_FEE_RATE} sat/vB")
    await fill_field(d, "Fee rate (sats/vB)", HIGH_FEE_RATE)
    await asyncio.sleep(0.3)
    flat = await d.cs_flat_text()
    assert HIGH_FEE_RATE in flat, (
        f"fee rate field not updated to '{HIGH_FEE_RATE}' — not found in semantics"
    )
    print(f"    [ok] fee rate confirmed as {HIGH_FEE_RATE} sat/vB")


async def _build_psbt(d):
    print("\n  [phase 6] Build TX_COMMIT")
    await click_label(d, "Build TX_COMMIT", delay=1.0)
    # Wait for either awaiting-signature or an error toast.
    for _ in range(30):
        flat = await d.cs_flat_text()
        if "Sign with hot key" in flat or "Sign with HW" in flat:
            print("    [ok] PSBT built — awaiting signature")
            assert "Sign with hot key" in flat, (
                "expected 'Sign with hot key' but got different signing option"
            )
            return
        if "Build TX_COMMIT" not in flat and "Building PSBT" not in flat:
            # phase changed to something else — likely error toast brought us back
            await asyncio.sleep(0.5)
        await asyncio.sleep(0.6)
    raise AssertionError("Timeout: PSBT build did not produce signing options")


async def _sign_with_hot_key(d) -> bool:
    print("\n  [phase 7] Sign with first available hot key")
    rect = (
        await d.cs_find_by_label_part_containing("Sign with hot key")
        or await d.cs_find_label_containing("Sign with hot key")
    )
    if rect is None:
        print("    [skip] no hot key available — cannot reach confirm-broadcast")
        return False
    d.flutter_click((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)
    # Signing is synchronous (in-process Argon2 unwrap + PSBT sign).  Wait
    # for the confirm-broadcast view.
    for _ in range(40):
        flat = await d.cs_flat_text()
        if "Confirm broadcast" in flat:
            print("    [ok] reached confirm-broadcast view")
            return True
        await asyncio.sleep(0.6)
    raise AssertionError("Timeout: signing did not reach confirm-broadcast")


def _dedupe_consecutive(values: list) -> list:
    """Flutter merged semantics expose each label twice in flat-text dumps
    (once on the merged parent, once on its children). Collapse consecutive
    equal values so the order [a, a, b, b, c] becomes [a, b, c]."""
    out: list = []
    for v in values:
        if not out or out[-1] != v:
            out.append(v)
    return out


def _parse_confirm_broadcast(flat: str) -> dict:
    """Extract numeric fields from the confirm-broadcast semantics dump."""
    out: dict = {}

    m = re.search(rf"Vault:\s+({_NUM_RX})\s+sats", flat)
    if m:
        out["vault"] = _to_int(m.group(1))

    m = re.search(rf"Anchors:\s+(\d+)\s+×\s+(\d+)\s+sats", flat)
    if m:
        out["anchor_count"] = int(m.group(1))
        out["anchor_amount"] = int(m.group(2))

    # "Change: X sats" appears at most twice (commit change, reveal change).
    changes = _dedupe_consecutive(
        [_to_int(s) for s in
         re.findall(rf"Change:\s+({_NUM_RX})\s+sats", flat)]
    )
    if changes:
        out["changes"] = changes

    # "Fee: X sats" without the "· vB" suffix → commit fee then reveal fee.
    fee_only = _dedupe_consecutive(
        [_to_int(s) for s in
         re.findall(rf"Fee:\s+({_NUM_RX})\s+sats(?!\s*·)", flat)]
    )
    if len(fee_only) >= 2:
        out["commit_fee"] = fee_only[0]
        out["reveal_fee"] = fee_only[1]

    # "Fee: X sats · Y vB" → package total + vbytes
    m = re.search(rf"Fee:\s+({_NUM_RX})\s+sats\s+·\s+(\d+)\s+vB", flat)
    if m:
        out["total_fee"] = _to_int(m.group(1))
        out["package_vb"] = int(m.group(2))

    return out


async def _verify_confirm_broadcast(d):
    print("\n  [phase 8] Validate confirm-broadcast coherence")
    await asyncio.sleep(0.4)
    flat = await d.cs_flat_text()
    assert "Confirm broadcast" in flat, "not on confirm-broadcast view"

    parsed = _parse_confirm_broadcast(flat)
    print(f"    [parsed] {parsed}")

    required = {"vault", "anchor_count", "anchor_amount",
                "commit_fee", "reveal_fee", "total_fee", "package_vb"}
    missing = required - parsed.keys()
    assert not missing, f"missing fields in confirm-broadcast view: {missing}"

    # Anchors.
    assert parsed["anchor_amount"] == 330, (
        f"anchor amount expected 330 sats, got {parsed['anchor_amount']}"
    )
    assert parsed["anchor_count"] >= 1, "expected at least 1 anchor"

    # On-chain backup publishes at least 3 anchors (minimum standard).
    assert parsed["anchor_count"] >= 3, (
        f"expected at least 3 anchors for on-chain backup, got {parsed['anchor_count']}"
    )
    print(f"    [ok] anchor count = {parsed['anchor_count']} (≥ 3)")

    # Per §5.4: vault_sats = max(330, reveal_fee − N_anchors × 330).
    # The vault is the TX_COMMIT output that funds TX_REVEAL.
    # TX_REVEAL change = vault + anchors - reveal_fee (may be negative if fee rate is high).
    # The app should prevent reaching confirm-broadcast when fee > vault, but if it does,
    # we still validate the fee arithmetic is coherent.
    # Vault must be at least the P2TR dust minimum (330 sats).
    assert parsed["vault"] >= 330, f"vault {parsed['vault']} sats below dust (330)"
    print(f"    [ok] vault {parsed['vault']} sats ≥ 330 dust threshold")

    # Positive amounts.
    assert parsed["commit_fee"] > 0, "commit fee not positive"
    assert parsed["reveal_fee"] > 0, "reveal fee not positive"
    assert parsed["package_vb"] > 0, "package vbytes not positive"

    # Total fee == commit fee + reveal fee.
    expected_total = parsed["commit_fee"] + parsed["reveal_fee"]
    assert parsed["total_fee"] == expected_total, (
        f"total fee mismatch: shown {parsed['total_fee']}, "
        f"commit+reveal={expected_total}"
    )
    print(f"    [ok] commit_fee {parsed['commit_fee']} + "
          f"reveal_fee {parsed['reveal_fee']} == total_fee "
          f"{parsed['total_fee']} sats")

    # Optional changes — must be ≥ 330 (dust threshold) when present.
    for ch in parsed.get("changes", []):
        assert ch >= 330, f"sub-dust change displayed: {ch} sats"


async def _back_out_without_broadcasting(d):
    print("\n  [phase 9] Back out of confirm-broadcast WITHOUT broadcasting")
    flat = await d.cs_flat_text()
    assert "Broadcast" in flat, "Broadcast button gone — view changed unexpectedly"
    print(f"\n    [DEBUG confirm-broadcast flat text]\n{flat}\n[END DEBUG]\n")
    # PopScope handles Back: it returns us to awaiting-signature, then to
    # utxo-selection.  We do NOT click "Broadcast".
    await click_tooltip(d, "Back", delay=0.8)
    flat = await d.cs_flat_text()
    assert "Confirm broadcast" not in flat, (
        "still on confirm-broadcast after Back — would have remained one "
        "tap away from a real signet broadcast"
    )
    assert "Sign with hot key" in flat or "Sign with HW" in flat, (
        "did not return to awaiting-signature view after Back"
    )
    print("    [ok] returned to awaiting-signature without broadcasting")
    # One more Back → utxo-selection.
    await click_tooltip(d, "Back", delay=0.6)
    flat = await d.cs_flat_text()
    assert "Build TX_COMMIT" in flat, "did not return to utxo-selection"
    print("    [ok] returned to utxo-selection — backup never broadcast")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def test_reg29(d):
    await set_active_network_signet(d)
    await asyncio.sleep(1.5)

    # Phase 2: recover wallet from its on-chain backup. The recovery screen
    # auto-attaches the seed as a hot key when the descriptor matches, so
    # the wallet is hot immediately after the import returns.
    await _recover_wallet_from_onchain_backup(d)

    # Phase 3: open on-chain backup screen on the recovered wallet. The
    # screen may settle on either 'exists' (an on-chain backup is already
    # published for this descriptor) or 'utxo' (none found — go straight
    # to the build flow). Both are acceptable starting points.
    await _open_publish_backup_sheet(d)
    phase = await _wait_backup_screen_phase(d)
    print(f"    [ok] backup screen settled on phase '{phase}'")
    if phase == "exists":
        await _verify_backup_exists_view(d)
        await _enter_create_flow(d)
    elif phase == "utxo":
        # Already on the utxo-selection screen; nothing to tap.
        pass
    else:
        raise AssertionError(
            f"Backup screen settled on unexpected phase '{phase}'"
        )

    # Phases 4-7: build + sign without broadcasting.
    await _select_first_utxo(d)
    await _select_spend_path(d)
    await _set_fee_rate_high(d)
    await _build_psbt(d)
    signed = await _sign_with_hot_key(d)
    if not signed:
        raise AssertionError(
            "Recovered wallet should be hot but no 'Sign with hot key' "
            "option was offered"
        )

    # Phases 8-9: coherence check + back out without broadcasting.
    await _verify_confirm_broadcast(d)
    await _back_out_without_broadcasting(d)


if __name__ == "__main__":
    asyncio.run(run_regression(test_reg29, "reg29"))
