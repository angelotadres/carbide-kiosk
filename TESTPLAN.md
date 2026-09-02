# Hardware test plan

Hardware is the only proof this project accepts, and this is how the proof is taken. The plan is ordered by risk: the steps most likely to fail come first, so a bad image is found in ten minutes rather than two hours.

Every step carries a number, `T0` through `T11`, and states the claim it proves. Those numbers are the link to [STATUS.md](STATUS.md), where each claim is recorded against the image that settled it. A step that passes is not finished until that table says so, and `.githooks/pre-commit` refuses a commit where the two files disagree about which steps exist. Which image was on the card goes in [RELEASES.md](RELEASES.md).

Work through it in order. A failure early on makes the later steps meaningless, so stop and report rather than pressing ahead.

This plan is not the first line of defence and should not be treated as one. Anything that can be settled without a Pi belongs in `tests/machinery.sh`, which asks the real `overlayroot` and the real systemd what they do with the image and which CI runs before it will build a release. Both of the failures that cost this project its last two images were detectable there, in seconds, and were instead found by flashing a card.

## Before you start

You need a Pi 5, an SD card of 8 GB or more, and a display of at least 1280x1024 — Carbide Motion refuses to run smaller. The Pi 5 uses micro-HDMI, so check the cable. You also need a USB keyboard, the Shapeoko and its USB cable, a Mac or PC on the same network, and a way to cut power abruptly. A switched power strip is ideal; pulling the plug works.

> [!WARNING]
> Use a card that has been flashed with this image before, not a fresh one. Flashing rewrites only the first few gigabytes, so a used card still carries the previous `CARBIDEDATA` filesystem at the offset the new one will use. That is half of what broke `1.0.0-alpha.24`, and a virgin card cannot reproduce it.

Flash the `.img.xz` from the [releases page](https://github.com/angelotadres/carbide-kiosk/releases) with Raspberry Pi Imager. When it offers to apply customisation settings, decline: those settings write their own first-boot configuration and collide with this image's. Never flash a locally built image out of `deploy/`, which accumulates builds with identical timestamps and near-identical names.

Re-insert the card. One small partition mounts on your machine; the large one will not, and that is expected.

For `T0`, put **only** a file named `authorized_keys` on that partition, holding one public key line, with no `kiosk.conf` at all. For everything from `T1` onward, copy `kiosk.conf.example` to `kiosk.conf` and set at minimum:

```ini
samba_user=cnc
samba_password=pick-something-real
enable_ssh=1
ssh_authorized_key=ssh-ed25519 AAAA... you@example.com
```

Add `wifi_ssid`, `wifi_password` and `wifi_country` unless you are on Ethernet. Once a `kiosk.conf` exists it is authoritative, so leaving `enable_ssh` unset closes port 22 a few seconds into the boot even though `T0` opened it — the access script warns about exactly this on the console.

## T0. Prove the way in, before anything else

**Proves:** SSH is open before first-boot setup runs, the machine joins the network on its own, and a card carrying only `authorized_keys` is still reachable.

Do this first and on its own, because every other step in this plan is diagnosed through it. It failed silently on every attempt before `1.0.0-alpha.23`, which is the first image to pass any part of it.

Connect Ethernet rather than wifi: wired DHCP needs no configuration, so it cannot be broken by a config file that is not there.

> [!WARNING]
> A rig with no Ethernet cannot run this step as written, and the only rig this project has is wifi only. With no `kiosk.conf` there is no wifi configuration, `join_network` logs `no wifi_ssid set; relying on a wired connection` and returns, and the machine has no network to be reachable over. On such a rig, skip to `T1` with a complete `kiosk.conf` on the card, and leave the `authorized_keys` claim recorded as unproven rather than assuming it.

Power on and wait thirty minutes on a first boot, eight on any boot after it. The first boot formats the data partition, which took 27 minutes for 230 GB on the 2026-09-01 run — `01:34:09` to `02:00:27` in `first-boot.log` — and the machine reboots itself only when that finishes. Eight is right for every later boot and badly wrong for the first. Two is not enough even then: the machine can hold its address within twenty seconds and still not answer for several minutes afterwards, because probing the address while it is rebooting leaves a negative ARP entry on the watching computer that outlives the reboot. Ping the address rather than retrying `ssh`, which is rate limited to six new connections a minute.

**Pass:** `ssh kiosk@<address>` logs in. The screen and `first-boot.log` on the small partition both say `access is up at <address>`.

**If it fails,** the log on the small partition is the diagnosis and it is readable from any computer with a card reader. `NO WAY IN` means no credential was found. `PORT 22 IS SHUT` means the firewall refused the ruleset. Nothing at all from `carbide-kiosk-access` means the unit never ran, which is the original defect returning. A log that stops after `opening remote access` means a step hung and systemd killed the unit at ninety seconds; each step names itself first, so the last line is the call that hung.

Power down and take the card out before continuing.

## T1. First boot

**Proves:** first boot creates and formats the data partition, applies the configuration, switches the system to read-only, disables itself and reboots.

This is the step most likely to fail, and it is the step `1.0.0-alpha.24` failed.

Insert the card, connect the display, power on. Watch the screen and leave it alone.

**Pass:** console text scrolls through `[1/4]` to `[4/4]`, the Pi reboots itself once within about five minutes, and comes back up.

**If it fails,** photograph the last twenty lines on screen and read `first-boot.log` off the small partition. Four failures have real history here. `could not format /dev/mmcblk0p3` means something mounted the partition before `mkfs` reached it, which is the `1.0.0-alpha.24` defect. A ninety-second stall before `[1/4]`, on `dev-disk-by-label-CARBIDEDATA.device`, is the same defect one stage earlier and is visible even when the format then succeeds. A halt at the read-only switch is deliberate — it refuses to continue with a writable system. A reboot loop means the unit did not disable itself.

## T2. Carbide Motion appears

**Proves:** the machine reaches Carbide Motion unattended, with the on-screen keyboard able to float above it.

**Pass:** Carbide Motion fills the screen. No desktop, no title bar, no mouse pointer, no login prompt. The keyboard launcher summons a keyboard that appears over the application rather than behind it.

**If it fails:** a black screen means the graphical session did not start; a text login prompt means the kiosk service did not start; a window with a title bar means the window manager did not; a keyboard that vanishes behind the application means the window manager or the maximise behaviour regressed.

## T3. Console access

**Proves:** `agetty --autologin` accepts an account whose password field is `*`, so the physical console works.

Plug in the keyboard and press Ctrl+Alt+F2.

**Pass:** a shell prompt appears without asking for a password.

This one is genuinely unverified. The account has no usable password by design and whether automatic login accepts that could go either way. If it asks for a password, that is a real finding and the account setup has to change.

## T4. The read-only root and a real data partition

**Proves:** the root is an overlay, the boot partition is remounted read-only, and `/data` is the actual card partition rather than a tmpfs.

This is the cheapest check in the plan and it is the one that would have caught the worst defect the image has had. On `1.0.0-alpha.23` the share ran entirely in RAM and nothing inside the machine said so.

From the console at `T3`, or over SSH:

```bash
mount | grep ' / '
mount | grep ' /boot/firmware '
df -h /data
findmnt -no SOURCE,FSTYPE /data
```

**Pass:** the root line mentions `overlay`. The boot line says `ro`. `df -h /data` reports the size of the card, not the size of RAM — hundreds of gigabytes on a 256 GB card, not four. `findmnt` names a real block device and `ext4`, never `tmpfs` and never anything under `/media/root-ro`.

**If it fails:** a `/data` of a few gigabytes is the `1.0.0-alpha.23` defect. Stop. Everything after this point will appear to work and prove nothing.

## T5. The network share

**Proves:** the share is reachable, refuses unauthenticated access, and the firewall permits only what `kiosk.conf` asked for.

From a Mac: Finder, then Go, then Connect to Server, then `smb://carbide-kiosk`. From Windows: `\\carbide-kiosk`.

If the name does not resolve, set `enable_mdns=1` in `kiosk.conf` and reboot, or connect by IP address instead.

**Pass:** it asks for the username and password you set, accepts them, and you can copy a file in. Connecting as guest is refused. Nothing answers on a port you did not open — check from the Mac with `nc -z <address> 22 445 139` and one port you never enabled.

**If it fails:** a refused connection points at the firewall, a rejected password at the account setup.

## T6. The share survives a reboot

**Proves:** a file written to the share is still there after a reboot, and the journal persists across one too.

`T4` catches the tmpfs share in seconds; this is the end-to-end confirmation, and it is the property the whole architecture exists to provide.

Copy a file to the share, note its size, then reboot the machine and look again. From the console or over SSH:

```bash
journalctl --list-boots
```

**Pass:** the file is still in the share and still the right size. `journalctl --list-boots` lists more than the current boot.

**If it fails:** a share that empties itself on reboot means `/data` is not persistent, whatever `T4` appeared to say. A journal that only knows this boot means `var-log-journal.mount` did not take.

## T7. The status file

**Proves:** the status file appears, reports real state, and leaks no configured password.

Within about ninety seconds of boot, `CARBIDE-STATUS.txt` appears in the share. Open it.

**Pass:** it is readable plain text, says Carbide Motion is running, and shows disk space and temperature. Search it for the Samba password and for the wifi password — neither may appear anywhere in the file.

This file is the machine's only diagnostic interface, so if it is wrong or missing, everything after this gets harder.

## T8. Shapeoko detection

**Proves:** the Shapeoko is detected and symlinked, and Carbide Motion connects to it and jogs the machine.

Plug in the Shapeoko and power it on. Wait up to five minutes for the status file to refresh, or reboot to speed it up.

**Pass:** the status file says the Shapeoko is connected and names a device. Carbide Motion connects and the machine jogs.

**Partial pass:** the status file says a serial device is present but not recognised, and names it. That is the expected outcome if the USB vendor ID is wrong. Go to the console, run `lsusb`, and add the ID to `usb_vendor_ids` in `kiosk.conf`. It is a one-line fix, not a defect.

## T9. Power loss

**Proves:** cutting power at any moment leaves a machine that boots cleanly with an intact share.

This is the feature the whole design exists for.

> [!WARNING]
> Do not run this step against an image that has not passed `T4` and `T6`. On `1.0.0-alpha.23` this test would have passed while proving nothing: with the share in RAM, nothing persisted, so nothing could be corrupted.

With the machine idle, cut power at the wall, wait five seconds, restore it. Do that five times.

Then copy a large file to the share and cut power while it is still copying. Do that five times.

**Pass:** every single boot reaches Carbide Motion, the share is still readable, and the status file still updates.

**If it fails:** any boot that does not reach Carbide Motion is a serious finding. Photograph the screen and note which of the two tests it was.

## T10. Settings survive a change

**Proves:** an edited `kiosk.conf` takes effect on the next boot and nothing on the data partition is orphaned by it.

Power off, edit `hostname` in `kiosk.conf`, power back on.

**Pass:** the machine answers to the new name and the share still works with the same credentials, on the same files.

## T11. A real job

**Proves:** rendering holds up on the intended display at the job sizes this shop actually runs.

Load a real G-code file over the share and run it.

Watch for sluggish or broken 3D rendering. Carbide 3D supports this software on a Pi 4, not a Pi 5, and has reported problems with files above roughly 100 MB. If your usual jobs are that large and rendering is poor, that is a limit of the application, not something this image can fix — and it is worth knowing before you build the enclosure.

## Reporting a failure

Send whichever of these you have: a photograph of the screen, `first-boot.log` from the small partition, the contents of `CARBIDE-STATUS.txt`, and if you can reach the console:

```bash
journalctl -b -p err --no-pager | tail -50
```

Then record the run: which tag was on the card, what it proved, and what it broke, in [RELEASES.md](RELEASES.md), and move the affected claims in [STATUS.md](STATUS.md). A run that is not written down did not happen, and this project has already lost the tag numbers for four of them.
