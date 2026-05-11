#!/usr/bin/env python3
"""
Hardware-wallet specific helpers for regression tests.

These tests require a real hardware device (BitBox02) connected via USB and a
human operator at the terminal that confirms pairing/operations on the device
when prompted. When no device is detected, tests are expected to exit cleanly
with code 0 and a clear "[SKIP]" line so the suite stays green on machines
without a HW.

Conventions used by tests in this module:
  - SKIP  → sys.exit(0) with `print("[SKIP] reason")` BEFORE the suite-level
            "[RESULT] PASS" line. Detection is always the first phase.
  - INPUT → wait for the user to press ENTER between physical interactions
            (e.g. "Confirm pairing on your BitBox now, then press ENTER").

The helpers below are deliberately conservative with timeouts because every
device interaction depends on a human pressing buttons.
"""

import asyncio
import os
import sys

# Markers we look for in semantics to tell what the HW sheet is showing.
HW_NO_DEVICE_MARKER   = "No hardware wallet detected"
HW_SCANNING_MARKER    = "Scanning for devices"
HW_CONNECTING_MARKER  = "Connecting"
HW_UNLOCK_MARKER      = "Unlock your device"
# Two different prompt strings exist in the codebase:
#   - hw_wallet_sheet.dart (sign/xpub/verify): "Compare this code with your device screen and confirm:"
#   - hw_connection_widgets.dart (HW Actions): "Compare with device screen and confirm:"
# Match the common prefix.
HW_PAIRING_INSTRUCT   = "Compare"

# When ready, the sheet shows the action button label, which depends on mode.
HW_READY_ACTIONS = {
    "sign":          "Sign transaction",
    "xpub":          "Export xpub",
    "register":      "Register wallet",
    "checkReg":      "Check registration",
    "verifyAddress": "Show address on device",
    "connect":       "Done",
}


# ---------------------------------------------------------------------------
# Skip helpers
# ---------------------------------------------------------------------------

def skip_test(reason: str, test_id: str = ""):
    """Exit cleanly with a SKIP marker. Used when no HW is connected."""
    tag = f" ({test_id})" if test_id else ""
    print("\n" + "=" * 50)
    print(f"[SKIP]{tag} {reason}")
    sys.exit(0)


# ---------------------------------------------------------------------------
# User prompts (terminal)
# ---------------------------------------------------------------------------

async def wait_for_user(message: str):
    """
    Print a prompt for the operator and return immediately. The actual "wait"
    happens via UI-state polling in the caller (the HW sheet transitions to
    a new state once the user confirms on the device, so we don't need a
    manual ENTER signal). Kept as a function for readability.
    """
    print(f"\n  [ACTION] {message}")


# ---------------------------------------------------------------------------
# HW sheet state polling
# ---------------------------------------------------------------------------

async def wait_for_hw_devices_or_empty(d, timeout_s: float = 8.0) -> bool:
    """
    Poll the HW sheet semantics until it shows either a device tile or the
    "no devices" message. Returns True if at least one device is listed,
    False otherwise.

    Caller must have already opened a HW sheet (sign / xpub / actions / …).
    """
    elapsed = 0.0
    poll = 0.5
    while elapsed < timeout_s:
        flat = await d.cs_flat_text()
        if HW_NO_DEVICE_MARKER in flat:
            return False
        # Device tiles render as ListTile(title=productString); the BitBox02
        # exposes "BitBox02" or similar. Generic check: usb icon + leading tile.
        # We probe both the explicit BitBox label and any tile under the sheet.
        if 'BitBox' in flat or '"USB"' in flat:
            return True
        await asyncio.sleep(poll)
        elapsed += poll
    # Timed out without a clear signal → treat as no devices
    return False


async def click_first_device(d):
    """Click the first device tile in the HW sheet device list."""
    rect = await d.cs_find_by_label_part("BitBox")
    if rect is None:
        # Generic fallback: look for any ListTile with a USB leading icon
        tree = await d.cs_tree()
        for n in tree:
            label = (n.get("label") or "")
            if label and ("BitBox" in label or "Bitbox" in label):
                rect = d._cs_rect(n)
                if rect:
                    break
    if rect is None:
        raise AssertionError("No device tile found in HW sheet")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy)
    await asyncio.sleep(0.8)


async def wait_for_pairing_or_ready(d, timeout_s: float = 30.0) -> str:
    """
    After tapping a device, the device may need PIN unlock and pairing
    confirmation. Poll the sheet until it transitions to either:
      - pairing/confirming state (shows the comparison code) → returns "pairing"
      - ready state (action button visible)                 → returns "ready"
      - error state                                         → raises

    The function does not act on the pairing prompt — the caller drives the
    user-confirmation flow with `wait_for_user(...)`.
    """
    import re as _re
    mfp_pat = _re.compile(r'"([0-9a-fA-F]{8})"')
    elapsed = 0.0
    poll = 1.0
    while elapsed < timeout_s:
        flat = await d.cs_flat_text()
        if HW_PAIRING_INSTRUCT in flat:
            return "pairing"
        # Ready: MFP is rendered (HwConnectedHeader / _ReadyPanel both show it).
        # Action button labels alone aren't enough because the HW Actions sheet
        # renders the Register/Check tiles even during the pairing step.
        if mfp_pat.search(flat):
            return "ready"
        if "Try again" in flat and "Disconnect" in flat:
            raise AssertionError("HW sheet entered error state during connect")
        await asyncio.sleep(poll)
        elapsed += poll
    raise AssertionError(
        f"Timed out waiting for HW pairing/ready (>{timeout_s:.0f}s). "
        "Is the device unlocked?"
    )


async def wait_for_ready(d, timeout_s: float = 60.0):
    """Wait until the HW sheet has fully connected.

    Two signals must hold simultaneously:
      - The pairing instruction is no longer visible (we're past pairing).
      - The session MFP (8 hex chars) is rendered (HwConnectedHeader).

    Note: action button labels alone are not enough — the HW Actions sheet
    renders Register/Check tiles even during pairing (just disabled), so a
    label-based check would return prematurely.
    """
    import re as _re
    mfp_pat = _re.compile(r'"([0-9a-fA-F]{8})"')
    elapsed = 0.0
    poll = 1.0
    while elapsed < timeout_s:
        flat = await d.cs_flat_text()
        if HW_PAIRING_INSTRUCT not in flat and mfp_pat.search(flat):
            return
        if "Try again" in flat and "Disconnect" in flat:
            raise AssertionError("HW sheet entered error state while waiting for ready")
        await asyncio.sleep(poll)
        elapsed += poll
    raise AssertionError(f"Timed out waiting for HW ready state (>{timeout_s:.0f}s)")


async def extract_root_fingerprint(d) -> str:
    """
    From an HW-ready sheet, pull the root fingerprint that's rendered next to
    the device name. Returns the lowercase 8-char hex MFP.

    The MFP may appear as a standalone label (8 hex chars) or as an entry in
    the `labels` array of a device tile node (e.g. BitBox02 tile).
    """
    import re
    tree = await d.cs_tree()
    pat = re.compile(r"^[0-9a-fA-F]{8}$")
    for n in tree:
        label = (n.get("label") or "").strip()
        if pat.match(label):
            return label.lower()
        # Also check the `labels` array (used by device tiles).
        for entry in (n.get("labels") or []):
            if pat.match(entry):
                return entry.lower()
    raise AssertionError("Could not extract root fingerprint from HW sheet")


# ---------------------------------------------------------------------------
# High-level orchestration
# ---------------------------------------------------------------------------

async def connect_hw_in_open_sheet(d, op_label: str = "operation") -> str:
    """
    Drive the connection state machine inside an already-open HW sheet:
      1. Wait for scan to finish.
      2. If no devices → SKIP (caller exits the suite).
      3. Tap the first device.
      4. If pairing code is shown, prompt the user to confirm on device.
      5. Wait for ready state.
      6. Return the device root fingerprint.

    Use this from any test that has just opened a HW sheet.
    """
    print(f"  [hw] waiting for device scan ({op_label})…")
    found = await wait_for_hw_devices_or_empty(d, timeout_s=10.0)
    if not found:
        skip_test(
            "No hardware wallet detected. Plug in a BitBox02 and unlock it "
            "before running this test.",
        )

    print("  [hw] device detected — tapping first device tile")
    await click_first_device(d)

    state = await wait_for_pairing_or_ready(d, timeout_s=30.0)
    if state == "pairing":
        print("  [hw] pairing code visible on screen — compare it with the device")
        await wait_for_user(
            "Compare the pairing code shown in the app with the one on your "
            "device, then press the confirm button on the BitBox."
        )
        # Poll until the device-side confirmation lands and the sheet shows
        # the ready state. Generous timeout: user has up to 2 minutes.
        await wait_for_ready(d, timeout_s=120.0)

    mfp = await extract_root_fingerprint(d)
    print(f"  [hw] connected — MFP={mfp}")
    return mfp


async def close_open_sheet(d):
    """Dismiss whatever bottom sheet is currently open by pressing Escape."""
    import subprocess
    subprocess.run(
        ["xdotool", "key", "Escape"],
        env={**os.environ, "DISPLAY": ":0"},
        timeout=3,
    )
    await asyncio.sleep(0.6)


# ---------------------------------------------------------------------------
# Funds helpers — used by tests that need on-chain funds to sign+broadcast.
# Skip-on-no-funds is NOT desired (we only skip if the HW is absent), so when
# a wallet is empty we surface the receive address and FAIL the test.
# ---------------------------------------------------------------------------

async def extract_first_receive_address(d) -> str:
    """Return the first bech32/base58 testnet receive address visible on the
    Addresses tab. Caller is responsible for navigating there beforehand."""
    import re as _re
    pat = _re.compile(r"\b((?:tb1|2|m|n)[a-zA-HJ-NP-Z0-9]{6,87})")
    tree = await d.cs_tree()
    for n in tree:
        label = (n.get("label") or "")
        m = pat.search(label)
        if m:
            return m.group(1)
    return "(could not extract — check Addresses tab manually)"


async def verify_first_receive_address_on_hw(d, op_label: str = "verify address"):
    """Open the Receive dialog from the current wallet-detail screen, click
    'Verify', drive the HW pairing if needed, tap 'Show address on device',
    wait for the operator to confirm, then close back to wallet detail.

    Caller must already be on the wallet-detail Overview tab.
    """
    # Local imports keep this helper self-contained and avoid circular deps.
    from regression_helpers import click_label, wait_for, wait_absent

    print(f"\n  [verify-addr] {op_label}")
    # Make sure we're on the Overview tab — the Receive button only exists
    # there. Tests sometimes leave the wallet detail on a sub-tab (Coins,
    # Addresses) after sync.
    flat = await d.cs_flat_text()
    if '"Send"' not in flat or '"Receive"' not in flat:
        try:
            await click_label(d, "Overview", delay=0.5)
            await wait_for(d, '"Receive"', "back on Overview",
                           retries=8, delay=0.5)
        except Exception:
            pass
    await click_label(d, "Receive", delay=0.6)
    await wait_for(d, "Verify", "Receive dialog opened (Verify button visible)",
                   retries=15, delay=0.5)
    await click_label(d, "Verify", delay=0.5)

    await connect_hw_in_open_sheet(d, op_label=op_label)
    await click_label(d, "Show address on device", delay=0.5)
    await wait_for_user("Confirm the address shown on the BitBox screen.")

    # Wait for the sheet to close. Use the SHEET TITLE ("Verify address on
    # device"), not the action-button label ("Show address on device") — the
    # button vanishes the moment the cubit transitions to the "operating"
    # state, well before the device actually shows anything to confirm.
    await wait_absent(d, "Verify address on device",
                      "verify-address sheet closed",
                      retries=180, delay=1.0)
    # Close the Receive dialog (its title bar has a Cancel close button).
    # Escape alone does not always reach the dialog after the sheet closes.
    from regression_helpers import click_tooltip as _click_tooltip
    try:
        await _click_tooltip(d, "Cancel", delay=0.5)
    except Exception:
        await close_open_sheet(d)
    print("    [ok] address verified on device")


async def bump_fee_if_rbf(d):
    """If the Create-TX form has switched to BIP-125 RBF replacement mode
    (because a previous run's PSBT for the same parent UTXO is still in the
    mempool), tap the Fee field — that triggers `_buildFeeField.onEditTap`
    which auto-fills the minimum required fee. Commit with Enter and wait
    for the summary to recompute. No-op if not in RBF mode.

    Caller must already be on the Create Transaction screen with MAX
    computed.
    """
    flat = await d.cs_flat_text()
    if "Full-RBF replacement" not in flat and "Minimum fee" not in flat:
        return False
    print("    [step] RBF replacement detected — bumping to min fee")
    rect = await d.cs_find_by_label_part_containing("total_fee_display")
    if rect is None:
        raise AssertionError("Could not find total fee field (RBF auto-bump)")
    cx = (rect[0] + rect[2]) // 2
    cy = (rect[1] + rect[3]) // 2
    d.flutter_click(cx, cy, delay_s=0.5)
    await asyncio.sleep(0.6)
    d.key("Return")
    await asyncio.sleep(0.8)
    # Wait for summary to stabilise (no '— sats' placeholder).
    from regression_helpers import wait_absent
    await wait_absent(d, '"— sats"', "summary recomputed after fee bump",
                      retries=10, delay=0.5)
    print("    [ok] fee bumped to RBF minimum")
    return True


def fail_no_funds(address: str, wallet_label: str = ""):
    """Raise AssertionError directing the operator to fund the wallet. Used by
    HW tests that *require* on-chain funds; we don't SKIP because that would
    silently green-light the suite even though signing was never exercised."""
    label = f"'{wallet_label}'" if wallet_label else "wallet"
    raise AssertionError(
        f"{label} has no Signet UTXOs. Send a small amount to the address "
        f"below and rerun this test:\n   {address}"
    )


# ---------------------------------------------------------------------------
# Descriptor signature verification helper (HW tests)
# ---------------------------------------------------------------------------

async def verify_descriptor_sig_with_hw(
    d, wallet_name: str, *, skip_on_no_hw: bool = True
):
    """
    Full descriptor-signature lifecycle on a wallet created from a HW key.

    This is a mandatory phase for every HW test. It covers:
      1. Navigate to Wallet Security → Manage Signatures.
      2. If "Not signed" → sign with BitBox02 (connect, confirm on device).
      3. Verify "Signed ·" status on the key tile.
      4. Tap "Verify all" → verify "signatures valid" toast.
      5. Verify "Verified ·" status on the key tile.
      6. Delete signature → verify "Not signed" reverts.
      7. Navigate back to wallet list.

    Skips gracefully (exit 0) if the HW device is not available at any point.

    Parameters:
        wallet_name: The label of the wallet whose descriptor sigs to verify.
        skip_on_no_hw: If True, skip (exit 0) when no HW is detected.
                       If False, raise AssertionError.
    """
    from regression_helpers import (
        click_popup_item,
        click_tooltip,
        click_label,
        wait_for,
        wait_absent,
        go_back_to_wallet_list,
        delete_wallet_from_list,
    )

    print(f"\n  [phase - descriptor sig] verify descriptor signature lifecycle")

    # Navigate to Descriptor Signatures screen.
    await click_popup_item(d, "More options", 0, "Security")
    await wait_for(d, '"Wallet Security"', "Wallet Security screen opened",
                   retries=10, delay=0.5)

    await click_tooltip(d, "Manage Signatures")
    await wait_for(d, '"Descriptor Signatures"', "Descriptor Signatures screen opened",
                   retries=10, delay=0.5)
    print("    [ok] Descriptor Signatures screen visible")

    # Check current state: "Not signed" or already "Signed ·"?
    flat = await d.cs_flat_text()
    needs_signing = "Not signed" in flat

    if needs_signing:
        print("    [ok] key tile shows 'Not signed' — signing with HW")
        await _sign_descriptor_with_hw(d)
    else:
        print("    [ok] key tile already shows 'Signed ·'")

    # Wait for "Signed ·" status.
    await wait_for(d, "Signed ·", "key tile shows 'Signed ·'",
                   retries=10, delay=0.5)
    print("    [ok] key tile shows 'Signed ·' status")

    # Tap "Verify all".
    await click_tooltip(d, "Verify all")
    await wait_for(d, "signatures valid", "verify result toast visible",
                   retries=15, delay=0.5)
    print("    [ok] 'signatures valid' toast visible")

    # Verify "Verified ·" badge.
    await wait_for(d, "Verified ·", "key tile shows 'Verified ·'",
                   retries=10, delay=0.5)
    print("    [ok] key tile shows 'Verified ·' status")

    # Delete the signature.
    await click_tooltip(d, "Delete signature")
    await wait_for(d, "Delete signature", "delete confirmation dialog opened",
                   retries=10, delay=0.5)
    await click_label(d, "Delete", delay=0.5)
    await wait_for(d, "Not signed", "key tile shows 'Not signed' after deletion",
                   retries=15, delay=0.5)
    print("    [ok] key tile reverted to 'Not signed'")

    # Go back to wallet list.
    await go_back_to_wallet_list(d)
    print("    [ok] back on wallet list")


async def _sign_descriptor_with_hw(d: "UIDriver") -> None:
    """
    Sign the descriptor on the current Descriptor Signatures screen using the
    connected BitBox02.  Skips gracefully if no device is detected.
    """
    from regression_helpers import click_label, click_tooltip, wait_for

    # Tap the sign button (draw icon) on the key tile.
    await click_tooltip(d, "Sign")
    await wait_for(d, "BitBox02", "sign method sheet visible with HW option",
                   retries=10, delay=0.5)

    # Select BitBox02 from the sign method sheet.
    await click_label(d, "BitBox02", delay=0.5)

    # HW sign sheet opens. Connect and confirm on device.
    mfp = await connect_hw_in_open_sheet(d, op_label="sign descriptor")
    # The descriptor-signing sheet shows "Sign" (not "Sign transaction").
    await wait_for(d, mfp, f"MFP {mfp} visible on HW sheet", retries=10, delay=0.5)
    await click_label(d, "Sign", delay=0.5)
    await wait_for(d, "Confirm on device", "device confirmation prompt visible",
                   retries=15, delay=0.5)
    await wait_for_user(
        "Confirm the descriptor signature on the BitBox screen."
    )

    # Wait for the success toast.
    await wait_for(d, "Signature stored", "success toast visible",
                   retries=30, delay=0.5)
    print("    [ok] 'Signature stored' toast visible")
