# Carbide Motion Kiosk

A reproducible Raspberry Pi 5 image that boots straight into Carbide Motion, exposes a Samba share for G-code transfer, and survives having its power cut mid-job.

This document is the design and the reasoning behind it. It describes what the image is meant to be, not what any particular build of it turned out to do. What a clean flash has actually proved is in [STATUS.md](STATUS.md), and what each release changed is in [RELEASES.md](RELEASES.md). Nothing here should be read as a statement that the current image behaves this way.

## Goal

Flash one image, drop a config file on the boot partition, power the Pi on next to a Shapeoko. It comes up in Carbide Motion on the attached display with no keyboard, no monitor-and-mouse setup step, and no writable root filesystem to corrupt. Shop machines on the LAN copy `.nc` files to a Samba share; nothing else on the box is reachable from the network.

## Upstream constraints

These are properties of Carbide 3D's Pi package, not choices this project makes. They drive most of the decisions below.

Carbide Motion for Raspberry Pi is distributed from a public bucket at `https://motion-pi.us-east-1.linodeobjects.com/carbidemotion-<build>.deb`. The [download page](https://carbide3d.com/carbidemotion/pi/) resolves the newest build by listing that bucket and taking the highest build number; this project does the same. The package is never redistributed here, which keeps the repository cleanly MIT.

The package is `Architecture: armhf` — 32-bit. Build 654 is version `6.0-654`, 4.6 MB, and links against system Qt5: `libqt5core5a`, `libqt5gui5`, `libqt5widgets5`, `libqt5network5`, `libqt5gamepad5`, `libqt5serialport5`, `libqt5websockets5`. The payload is a single binary at `/usr/local/bin/carbidemotion` plus a desktop entry — there is no bundled runtime and no service.

Those dependency names pin the base to Debian Bookworm. Debian's 64-bit `time_t` transition renamed four of them on armhf — `libqt5core5t64`, `libqt5gui5t64`, `libqt5widgets5t64`, `libqt5network5t64` — so on Trixie the package's dependencies are unsatisfiable. The rename is not cosmetic: the `t64` builds are ABI-incompatible with a binary compiled against 32-bit `time_t`, so satisfying the names with aliases would trade a clean install failure for silent misbehaviour. Bookworm armhf carries all seven under the names the package declares.

Carbide 3D's stated requirement is a Pi 4 on 32-bit Raspbian with a 1280x1024 minimum display, and they have acknowledged Pi 5 rendering problems on very large (>100 MB) G-code files, which are GPU-bound rather than fixable from the image side.

## Decisions at a glance

- 32-bit Raspberry Pi OS Lite, Bookworm, built with pi-gen in Docker at a pinned tag.
- Carbide Motion downloaded at build time, never redistributed; a package in `deb/` overrides the download.
- Read-only root under overlayfs; a third partition, created on first boot, holds all writable state.
- All runtime configuration regenerated every boot from `kiosk.conf` on the boot partition.
- Samba with one authenticated account, no guest access, fixed share UID.
- Samba is the only listener by default. SSH, mDNS and ICMP are opt-in through `kiosk.conf`, which can only be changed by physically removing the card.
- Diagnostics delivered as a plain-text status file in the share, refreshed every five minutes.
- Service access is physical: autologin console on tty2.
- No known credential in the published image; the first-user password is random per build and then disabled.
- Bounded 64M persistent journal on the data partition.

## Decisions

The base is Raspberry Pi OS Lite 32-bit (armhf), Bookworm. The application package is armhf, so a native 32-bit userland takes its Qt5 dependencies straight from the Raspberry Pi OS archive with no multi-arch and no second library stack to track. Bookworm rather than Trixie because of the `t64` rename above. The Pi 5 boots 32-bit Bookworm without issue and Carbide Motion needs nothing 64-bit.

The image is built by [pi-gen](https://github.com/RPi-Distro/pi-gen) inside Docker, pinned to the `2026-06-18-raspios-bookworm-armhf` tag, driven by a single custom stage in this repository and run in CI on every tag. The output is a real flashable `.img`.

The root filesystem is read-only under overlayfs. A third partition, created on first boot from the remaining card space, holds everything that must persist: the Samba share and Carbide Motion's own settings. Power loss can then only ever damage the data partition, which is journaled and mounted with a short commit interval.

Samba runs with a single authenticated account, no guest access. The password is seeded from the boot-partition config file and the share does not come up without one.

## Architecture

### Partitions

The image ships two partitions; the third is created by the first-boot unit from whatever space is left on the card.

- `/boot/firmware` — FAT32, holds `kiosk.conf`. Mounted read-only after first boot.
- `/` — ext4, read-only, overlayfs with a tmpfs upper layer.
- `/data` — ext4, label `CARBIDEDATA`, the only writable persistent storage. Mounted by `data.mount` rather than from `/etc/fstab`, because `overlayroot` rewrites every ext4 entry in `fstab` into a read-only mount under `/media/root-ro` with a tmpfs upper layer. That is right for the root filesystem and exactly wrong here, and it only rewrites `fstab`, so a mount unit is out of its reach by construction. The persistent journal is bound onto the partition the same way, by `var-log-journal.mount`.

Neither mount unit is present in the image where systemd can see it. Both are staged at `/usr/local/share/carbide-kiosk/`, and `carbide-firstboot` installs them into `/etc/systemd/system/` once the partition exists and before the overlay is enabled. Shipping them into a unit directory merely disabled is not enough: `carbide-kiosk.service`, `carbide-kiosk-config.service` and `carbide-kiosk-status.service` all declare `RequiresMountsFor=/data`, and systemd resolves that to a hard `Requires=` on whichever mount unit covers the path, enabled or not. On a first boot there is no partition yet, so the boot waits on a device that does not exist. A unit systemd cannot see cannot be required.

### Boot flow

```mermaid
flowchart TD
    A[First boot] --> B[carbide-firstboot.service]
    B --> C["Create and format /data from free space"]
    C --> D["Enable overlayfs root and remount boot read-only"]
    D --> E[Reboot]
    E --> F["Every subsequent boot, read-only root"]
    F --> G["carbide-kiosk-config.service regenerates smb.conf, nftables, udev rule, hostname, WiFi"]
    G --> H["smbd and nftables start"]
    H --> I[Autologin kiosk user]
    I --> J["carbide-kiosk.service, Restart always"]
    J --> K["xinit with openbox running carbidemotion"]
    K -->|carbidemotion exits| J
```

The first-boot unit disables itself before rebooting, and enabling overlayfs is the last step it takes, since everything after that point is no longer persistent. Because the overlay upper layer is tmpfs, every write to `/etc` is discarded at shutdown, so `carbide-kiosk-config.service` regenerates the Samba, nftables, udev, hostname and WiFi configuration from `kiosk.conf` on every boot rather than once at first boot.

### Kiosk session

`carbide-kiosk.service` runs as the unprivileged `kiosk` user, launching `xinit` against a minimal X session: `openbox` as the window manager, `xvkbd` as the on-screen keyboard with a one-button `tint2` launcher to summon it, `xscreensaver`, `unclutter` to hide the pointer, then `/usr/local/bin/carbidemotion`. If Carbide Motion crashes the session restarts, but only five times in two minutes: a session that cannot start must leave the operator a usable console rather than fighting them for the keyboard.

openbox rather than matchbox because matchbox has no window layers and the keyboard could never float above the application. The main window is maximised and undecorated rather than fullscreen, deliberately: a fullscreen window outranks the always-on-top layer and would cover the keyboard. Dialogs keep their natural size for the same reason.

Carbide Motion's interface is scaled with `QT_SCALE_FACTOR`. The keyboard is an Athena application and ignores that entirely, so its type is sized separately through X resources.

Carbide Motion's settings directory is symlinked into `/data` so preferences and machine configuration survive the read-only root.

### Accounts

pi-gen always creates a first user and, when the first-boot rename wizard is disabled — which headless operation requires — insists on a password for it. `build.sh` therefore generates a random password per build and the kiosk stage locks the account immediately. The session is started by systemd, which does not authenticate, so the account never needs a usable password, and no published image carries a known credential. CI asserts both the length and that two builds differ.

The Samba account is separate, created at boot from `kiosk.conf` with a fixed UID so renaming it does not orphan files already on the data partition.

### Network exposure

`nftables` with a default-drop input policy. Permitted inbound: loopback, established and related, and Samba (`445/tcp`, `139/tcp`, `137-138/udp`). mDNS (`5353/udp`, for macOS Finder discovery) is opt-in via `enable_mdns=1`, and ICMP echo via `enable_ping=1`. Everything else is dropped.

Remote access is a separate unit running a separate script, `carbide-kiosk-access`, ordered before first-boot setup and before configuration. It shares no code with anything it might have to diagnose: it reads `kiosk.conf` with its own four-line reader rather than sourcing the shared library, and it neither sources nor runs the configuration script. It always runs, and every outcome - including refusing to open the port - is written to `tty1` and to `first-boot.log` on the boot partition, never only to the journal, which is unreadable on exactly the machine these messages are about.

Credentials come from `kiosk.conf` or from a plain `authorized_keys` file on the boot partition. The second is the way back into a machine whose config file never arrived or cannot be parsed; dropping a key next to it is as physical an act as editing it. Nothing is baked into the image, so no published image carries a credential. Once a `kiosk.conf` does exist it is authoritative: configuration runs moments later and closes the port again unless `enable_ssh=1` is actually set, and the access script says so on the console when it sees that combination, because a door that opens and shuts looks identical to a crash from the other end.

SSH is off by default and opens only when `enable_ssh=1` is paired with a credential. `enable_ssh=1` on its own leaves the port shut: an open port onto an account nobody can authenticate against is worse than no port. A key in `ssh_authorized_key` is preferred and disables password authentication outright; `ssh_password` exists as a fallback and is stored in clear text on the card.

The door is gated on physical possession. `kiosk.conf` lives on the boot partition, so opening SSH means powering the machine down, taking the card out, and editing it on another computer. Nothing reachable over the network can turn it on.

When open, `sshd` permits only the `kiosk` account, refuses root, refuses empty passwords, disables both forwarding kinds, allows three authentication attempts and a twenty-second grace period. New connections to port 22 are rate limited to six a minute in the firewall, which blunts brute force without a log-scraping daemon. The host key lives on the data partition so it survives the volatile overlay and does not change on every boot.

### Diagnostics

The appliance reports on itself through the share, the way a printer has a status page rather than a shell. `carbide-kiosk-status` writes `CARBIDE-STATUS.txt` into the share on boot and every five minutes: whether Carbide Motion is running and how often it has restarted, whether the Shapeoko is detected, free space, temperature, power-supply throttling, and recent errors from this boot and the one before it. It is plain text, so it opens on any machine that can reach the share — which matters because the data partition is ext4 and a Mac cannot read it off the card.

Nothing from `kiosk.conf` reaches that file except the hostname and share name. Everything else is observed state, and the writer strips the configured Samba and WiFi passwords from its own output in case one leaks through a quoted log line. Six tests cover that stripping.

Service access is physical. `getty@tty2` autologins the kiosk account, so Ctrl+Alt+F2 on a keyboard plugged into the machine gives a console. Anyone who can reach that keyboard can already remove the SD card, so it withholds nothing that matters, and it avoids a password that would otherwise have to live in a file.

### CNC device detection

A udev rule symlinks matching USB serial devices to `/dev/shapeoko` and grants the `kiosk` user access via the `dialout` group. The vendor allowlist is seeded with the IDs Carbide 3D and Shapeoko-family boards are known to present — `03eb` (Atmel, used by the Carbide Motion board), `2341` and `2a03` (Arduino), `1a86` (CH340), `0403` (FTDI) — and is extended from `usb_vendor_ids` in `kiosk.conf` without rebuilding the image.

> [!NOTE]
> The allowlist is seeded from published reports rather than from hardware in hand. Confirming the running-mode vendor and product ID of the specific Shapeoko this image will drive is a task below, not a settled fact.

## Configuration surface

Everything an operator sets lives in `kiosk.conf` on the boot partition, readable from any machine that can mount an SD card. `config/kiosk.conf.example` is the documented template.

- `hostname` — defaults to `carbide-kiosk`.
- `samba_user`, `samba_password` — required; the share stays down without them.
- `samba_share_name`, `samba_min_protocol`, `samba_encrypt` — share naming and transport hardening.
- `wifi_ssid`, `wifi_password`, `wifi_country` — omit entirely for Ethernet.
- `enable_ssh`, `ssh_authorized_key`, `ssh_password` — troubleshooting access, off by default and refusing to open without a credential.
- `enable_mdns`, `enable_ping` — inbound exceptions, both off by default.
- `usb_vendor_ids` — additional USB vendor IDs to treat as a CNC controller.
- `screen_rotation`, `screen_resolution` — display handling for panel-mounted screens.

Build-time settings live in `build.conf` at the repository root. `build.sh` merges them with the pi-gen variables it generates.

- `CARBIDE_MOTION_BUILD` — pin an exact build number, or leave unset to take the newest.
- `CARBIDE_MOTION_DEB_DIR` — directory searched for an offline `.deb` before any network fetch.
- `DATA_PARTITION_MIN_MB` — refuse first boot on a card too small to hold a useful share.

## Repository layout

```text
carbide-kiosk/
├── build.sh                  pi-gen Docker wrapper
├── build.conf                build-time settings
├── config/
│   └── kiosk.conf.example    runtime settings template
├── deb/                      optional offline Carbide Motion package
├── scripts/
│   └── fetch-carbide-motion.sh
├── stage-kiosk/              custom pi-gen stage
│   ├── 00-base/00-packages
│   ├── 01-carbide-motion/
│   ├── 02-kiosk-session/
│   ├── 03-samba/
│   ├── 04-firewall/
│   ├── 05-udev-cnc/
│   ├── 06-resilience/
│   └── 07-firstboot/
└── tests/                    bats suites
```

## What the automated suites can and cannot prove

CI runs `shellcheck` over every shell script, a `bats` suite per behaviour, `testparm -s` and `nft -c -f` over configuration rendered by the real generator rather than a copy of it, and an `apt-get install --simulate` of the whole package list plus Carbide Motion inside a Bookworm armhf container which then asks the linker what the binary actually needs. It also stages the repository from a clean clone, checks the package list holds only package names, checks `kiosk.conf.example` documents exactly the settings the code reads, and checks no known credential ships in the image.

That is a lot of coverage, and it is coverage of one thing: that this repository's files say what this repository intends. It is structurally incapable of covering the other thing, which is what `overlayroot`, systemd, pi-gen and the Raspberry Pi firmware do with those files once they are on a card.

Both of the worst defects this image has had lived in that gap and shipped through a fully green suite. `carbide-firstboot` wrote a correct `fstab` line and `overlayroot` rewrote it into a tmpfs. Three services declared `RequiresMountsFor=/data` and systemd turned that into a hard dependency on a mount unit nobody had enabled. In each case the assertion available to a test that reads our own files was true, and the machine was broken.

So the suites are joined by `tests/machinery.sh`, which reads none of our files. It builds a rootfs by running the stage scripts, installs the real `overlayroot` package and the real systemd, and asks them: `systemd --system --test` for the transaction our units resolve to, and `overlayroot`'s own `overlayrootify_fstab` function for what becomes of our `fstab`. Both defects above reproduce in it in seconds, on a laptop. Every check carries a control — a case where the machinery must produce the bad outcome — because a harness that has quietly stopped working reports success indefinitely, and that is how the second failure got past the test written for the first.

CI runs it as the `machinery` job, and the job that builds an image depends on it. A tag that fails it produces no release, so there is nothing to flash and nothing to remember to check.

That still settles only what can be settled off the machine. A claim about the running appliance is not proven until [TESTPLAN.md](TESTPLAN.md) settles it on hardware and [STATUS.md](STATUS.md) records which image did it.

## Known risks

Carbide 3D supports this package on a Pi 4, not a Pi 5, and the forum reports large-job rendering problems that no image-side change can address. If the shop's typical G-code exceeds roughly 100 MB, this hardware choice needs revisiting before the rest of the work matters.

Bookworm is oldstable and its security support ends before Carbide 3D is likely to ship an arm64 or Qt6 build. There is no forward path on Trixie without upstream rebuilding against `t64` Qt5, so the plan when Bookworm goes end-of-life is a pinned `snapshot.debian.org` archive rather than a suite upgrade. The narrow network exposure is what makes holding an ageing base tolerable; it is not a reason to widen it.

An overlayfs root means updates are a deliberate act: remount read-write, change, reboot. That is the point, but it makes the box harder to fix in place, which is why the fault path is to reflash rather than to repair. Reflashing also destroys the data partition, so the share is a drop box for jobs and not where masters live.

The hardware watchdog reboots if PID 1 stops responding. Mid-job that stops the G-code stream while the spindle is still turning, which ruins the workpiece. It is kept because by the time it fires the machine is already unresponsive, but it is a deliberate trade rather than a free safety net.
