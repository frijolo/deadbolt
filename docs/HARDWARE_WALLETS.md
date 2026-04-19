# Hardware Wallet Setup

Deadbolt integrates with the BitBox02 hardware wallet for three workflows:

- **PSBT signing** — sign an unsigned transaction without exposing private keys to the host machine.
- **xpub export** — export the device's xpub for a derivation path directly into a wallet descriptor.
- **Restore from hardware wallet** — connect a BitBox02 to scan on-chain accounts and fetch Nostr backups, recovering a wallet without entering a seed phrase (accessible from the wallet list via "Recover from hardware wallet").

## Supported devices

| Device   | Android | Linux | Windows |
|----------|---------|-------|---------|
| BitBox02 | ✓       | ✓     | ✓       |

## Android

No extra setup required. When you connect the BitBox02 via USB-C, Android will show a permission dialog — tap **Allow**.

## Linux

### udev rule (required)

On Linux, `/dev/hidraw*` devices are only accessible to root by default. You must install a udev rule so Deadbolt can open the BitBox02 without elevated privileges.

Create `/etc/udev/rules.d/51-bitbox02.rules`:

```bash
sudo tee /etc/udev/rules.d/51-bitbox02.rules << 'EOF'
# BitBox02 hardware wallet (Atmel / ShiftCrypto, VID 0x03eb)
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="03eb", TAG+="uaccess"
EOF
```

Then reload the rules and re-plug the device:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

> `TAG+="uaccess"` grants access to the currently logged-in user via systemd-logind. It is the modern alternative to `MODE="0666"` and does not open the device to all users on the system.

After re-plugging, Deadbolt should be able to open the device. If you still get "Permission denied", verify the rule was applied:

```bash
stat /dev/hidraw0   # or whichever hidraw node your BitBox02 uses
# Look for "Uid: (1000/youruser)" or ACL entries
```

### Identifying the correct hidraw node

If you have multiple HID devices, you can find the BitBox02 node by vendor ID:

```bash
for f in /dev/hidraw*; do
  echo -n "$f: "
  cat /sys/class/hidraw/$(basename $f)/device/uevent 2>/dev/null | grep HID_ID || echo "no info"
done
```

The BitBox02 reports vendor ID `03eb` (`HID_ID=0003:000003EB:...`).

## Windows

No extra setup required. The BitBox02 HID driver is built into Windows.

> **Note:** Windows support has not been exhaustively audited. If you encounter issues, please report them at https://github.com/frijolo/deadbolt/issues.

## Troubleshooting

**"Cannot open device: Permission denied"** (Linux)
→ The udev rule is missing or has not been applied yet. Follow the steps above and re-plug the device.

**"No BitBox02 detected"**
→ Make sure the device is unlocked (PIN entered) before scanning. The device only appears as a HID device after the PIN screen.

**"Handshake failed: u2f framing decoding error"**
→ Unplug and re-plug the BitBox02, then try again. This can happen if a previous connection was interrupted mid-protocol, leaving stale USB data buffered in the device.

**"Pairing code" screen**
→ On first connection Deadbolt and the BitBox02 perform a Noise XX key exchange. Compare the code shown on both screens — if they match, confirm on the device. Subsequent connections skip this step.
