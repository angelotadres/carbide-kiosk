# Hardware test plan

First boot completes and reboots itself, confirmed on 2026-08-29. What has never worked is the step after it: the machine reaching Carbide Motion unattended. The plan is ordered by risk: the steps most likely to fail come first, so a bad image is found in ten minutes rather than two hours. Each step says what a pass looks like, what the likely failure is, and what to capture if it fails.

Work through it in order. A failure early on makes the later steps meaningless, so stop and report rather than pressing ahead.

## Before you start

You need a Pi 5, an SD card of 8 GB or more, and a display of at least 1280x1024 — Carbide Motion refuses to run smaller. The Pi 5 uses micro-HDMI, so check the cable. You also need a USB keyboard, the Shapeoko and its USB cable, a Mac or PC on the same network, and a way to cut power abruptly. A switched power strip is ideal; pulling the plug works.

## 0. Prove the way in, before anything else

Do this first and on its own, because every other step in this plan is diagnosed through it. It is also the step that has silently failed on every attempt so far, and the fix for that is unproven on hardware.

Flash `image_2026-08-29-carbide-kiosk.img.xz` with Raspberry Pi Imager, declining its customisation settings. Re-insert the card and put **only** a file named `authorized_keys` on the small partition, holding one public key line — no `kiosk.conf` at all. Connect Ethernet rather than WiFi: wired DHCP needs no configuration, so it cannot be broken by a config file that is not there.

Power on and wait two minutes.

**Pass:** `ssh kiosk@<address>` logs in. The screen and `first-boot.log` on the small partition both say `access is up at <address>`.

**If it fails,** the log on the small partition is the diagnosis and it is readable from any computer with a card reader. `NO WAY IN` means no credential was found. `PORT 22 IS SHUT` means the firewall refused the ruleset. Nothing at all from `carbide-kiosk-access` means the unit never ran, which is the original defect returning. A log that stops after `opening remote access` means a step hung and systemd killed the unit at ninety seconds; each step now names itself first, so the last line is the call that hung.

Power down and take the card out before continuing.

## 1. Flash and configure

Flash `image_2026-08-29-carbide-kiosk.img.xz` with Raspberry Pi Imager. When it offers to apply customisation settings, decline. Those settings write their own first-boot configuration and will collide with this image's.

Re-insert the card. One small partition mounts on your machine; the large one will not, and that is expected. Copy `kiosk.conf.example` to `kiosk.conf` on the partition that mounted, and set at minimum:

```ini
samba_user=cnc
samba_password=pick-something-real
```

Add `wifi_ssid` and `wifi_password` if you are not on Ethernet.

Set `enable_ssh=1` and `ssh_authorized_key` as well. Once a `kiosk.conf` exists it is authoritative, so leaving `enable_ssh` unset closes port 22 a few seconds into the boot even though step 0 opened it — the access script warns about exactly this on the console.

**Pass:** `kiosk.conf` sits next to `config.txt` on the small partition.

## 2. First boot

This is the step most likely to fail. It creates the data partition, applies your settings, switches the system to read-only, and reboots itself.

Insert the card, connect the display, power on. Watch the screen and leave it alone.

**Pass:** console text scrolls, the Pi reboots itself once within about five minutes, and comes back up.

**If it fails,** photograph the last twenty lines on screen. The three likely failures are the data partition not being created, the read-only switch refusing to engage — it is designed to halt rather than continue with a writable system — and the first-boot step failing to disable itself, which shows as a reboot loop.

## 3. Carbide Motion appears

**Pass:** Carbide Motion fills the screen. No desktop, no title bar, no mouse pointer, no login prompt.

**If it fails:** a black screen means the graphical session did not start; a text login prompt means the kiosk service did not start; a window with a title bar means the window manager did not.

## 4. Console access

Plug in the keyboard and press Ctrl+Alt+F2.

**Pass:** a shell prompt appears without asking for a password.

This one is genuinely unverified — the account has no usable password by design, and whether automatic login accepts that could go either way. If it asks for a password, that is a real finding and I will need to change how the account is set up.

While you are there, confirm the read-only system is actually active:

```bash
mount | grep ' / '
```

**Pass:** the output mentions `overlay`. Press Ctrl+Alt+F1 to get back to Carbide Motion.

## 5. The network share

From a Mac: Finder, then Go, then Connect to Server, then `smb://carbide-kiosk`. From Windows: `\\carbide-kiosk`.

If the name does not resolve, set `enable_mdns=1` in `kiosk.conf` and reboot, or connect by IP address instead.

**Pass:** it asks for the username and password you set, accepts them, and you can copy a file in.

**If it fails:** a refused connection points at the firewall, a rejected password at the account setup.

## 6. The status file

Within about ninety seconds of boot, `CARBIDE-STATUS.txt` appears in the share. Open it.

**Pass:** it is readable plain text, says Carbide Motion is running, and shows disk space and temperature. Search it for the Samba password you chose — it must not appear anywhere.

This file is the machine's only diagnostic interface, so if it is wrong or missing, everything after this gets harder.

## 7. Shapeoko detection

The USB vendor ID list is seeded from published reports rather than from your hardware, so this may well need adjusting. That is expected, not a fault.

Plug in the Shapeoko and power it on. Wait up to five minutes for the status file to refresh, or reboot to speed it up.

**Pass:** the status file says the Shapeoko is connected and names a device.

**Partial pass:** it says a serial device is present but not recognised, and names it. That is the expected outcome if the ID is wrong. Go to the console (Ctrl+Alt+F2), run `lsusb`, and send me the line for the Shapeoko. It is a one-line fix.

Then check that Carbide Motion itself connects to the machine.

## 8. Power loss

This is the feature the whole design exists for.

With the machine idle, cut power at the wall, wait five seconds, restore it. Do that five times.

Then copy a large file to the share and cut power while it is still copying. Do that five times.

**Pass:** every single boot reaches Carbide Motion, the share is still readable, and the status file still updates.

**If it fails:** any boot that does not reach Carbide Motion is a serious finding. Photograph the screen and note which of the two tests it was.

## 9. Settings survive a change

Power off, edit `hostname` in `kiosk.conf`, power back on.

**Pass:** the machine answers to the new name and the share still works with the same credentials.

## 10. A real job

Load a real G-code file over the share and run it.

Watch for sluggish or broken 3D rendering. Carbide 3D supports this software on a Pi 4, not a Pi 5, and has reported problems with files above roughly 100 MB. If your usual jobs are that large and rendering is poor, that is a limit of the application, not something this image can fix — and it is worth knowing before you build the enclosure.

## Reporting a failure

Send whichever of these you have: a photograph of the screen, the contents of `CARBIDE-STATUS.txt`, and if you can reach the console:

```bash
journalctl -b -p err --no-pager | tail -50
```
