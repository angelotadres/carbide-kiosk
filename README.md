# Carbide Motion Kiosk

A Raspberry Pi 5 image that boots straight into [Carbide Motion](https://carbide3d.com/carbidemotion/pi/), shares a folder over the network for G-code, and survives having its power cut mid-job.

Flash it, drop a config file on the boot partition, and plug it in next to a Shapeoko. There is no setup wizard, no desktop, and no keyboard required.

## What it does

The root filesystem is read-only under an overlay, so an unclean shutdown cannot corrupt the operating system. A separate data partition holds the Samba share and Carbide Motion's settings. Samba is the only service reachable from the network; everything else is dropped by a default-deny firewall. A USB Shapeoko is detected automatically and exposed to the session as `/dev/shapeoko`.

The full design, including the reasoning behind each choice, is in [SPEC.md](SPEC.md).

> [!WARNING]
> Carbide 3D supports this package on a Raspberry Pi 4 running 32-bit Raspberry Pi OS, not on a Pi 5, and has reported rendering problems with G-code files above roughly 100 MB. Those are limits of the application, not of this image. Read [the upstream constraints](SPEC.md#upstream-constraints) before committing to this hardware.

## Using a built image

Flash the `.img.xz` from the [releases page](https://github.com/angelotadres/carbide-kiosk/releases) with Raspberry Pi Imager or `dd`. Do not apply Imager's own customisation settings; they conflict with the first-boot sequence.

With the card still mounted, copy `kiosk.conf.example` from the boot partition to `kiosk.conf` and edit it. At minimum, set a Samba account:

```ini
samba_user=cnc
samba_password=choose-something-real
```

Leave `wifi_ssid` empty for a wired connection, or fill in the WiFi block. Every other setting has a working default, and every inbound exception is off until you turn it on.

First boot takes a few minutes and ends in a reboot: the Pi creates its data partition, applies the config, and switches the root filesystem to read-only. From then on it comes up in Carbide Motion in well under a minute.

The share appears as `\\carbide-kiosk\gcode` on Windows and `smb://carbide-kiosk/gcode` on macOS. If macOS cannot find it by name, set `enable_mdns=1`.

## Changing the configuration later

`kiosk.conf` is read fresh on every boot, so the whole administration story is: power the Pi down, read the card on another machine, edit the file, put it back. Nothing else on the system needs to be touched, and nothing you change on the running system survives a reboot — that is what makes the power-loss guarantee hold.

To get a shell for diagnosis, set `enable_ssh=1`. That opens exactly one more port and nothing else.

## Building the image

You need Docker and about 12 GB of free disk. The build fetches Carbide Motion from Carbide 3D's public bucket; the package is proprietary and is never committed to this repository.

```bash
./build.sh
```

Output lands in `deploy/`. Build-time settings live in [build.conf](build.conf) — the pi-gen tag, the image name, and whether to pin a specific Carbide Motion build.

To build without network access to Carbide 3D, or to pin an exact version, drop the package into `deb/` first:

```bash
curl -O https://motion-pi.us-east-1.linodeobjects.com/carbidemotion-654.deb
mv carbidemotion-654.deb deb/
./build.sh
```

A package found in `deb/` is always preferred over anything downloaded.

## Development

```bash
./scripts/install-hooks.sh   # once per clone
bats tests/                  # unit suites
bash tests/render-config.sh  # needs testparm and nft; CI runs it in a container
```

The hook runs `shellcheck` and the unit suites before each commit, using local binaries or Docker, whichever is available. CI is the authoritative gate: it also renders the generated `smb.conf` and firewall ruleset through the real parsers, and resolves the whole package list against Bookworm armhf.

## License

MIT. See [LICENSE](LICENSE). This covers the build scripts in this repository only — Carbide Motion itself is proprietary software from Carbide 3D, downloaded at build time under their terms.
