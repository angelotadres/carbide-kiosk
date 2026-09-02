# Release ledger

One entry per tag, newest first. A release is a thing an operator flashes, so the record has to say which one they should be holding and what happened when they held it. `1.0.0-alpha.23` and `1.0.0-alpha.24` were built a day apart and their image files carry the same name, differing only by checksum, which makes "which image was that" a question the repository has to answer rather than a memory.

Every entry says four things. Verdict is whether the image is safe to flash. Changed is what went into it. Proved is what a clean flash demonstrated, and it is `nothing` until a clean flash happens. Regressed is what the same flash broke or revealed, including defects that were already there and only became visible now.

`.githooks/pre-commit` refuses a commit when a tag has no entry here, so a release cannot be shipped and then forgotten. It cannot tell whether an entry is true, only that it exists.

Current state, rather than history, is in [STATUS.md](STATUS.md).

## 1.0.0-alpha.26 — 2026-09-01

Not yet flashed. Verdict: unproven. Identical image code to `1.0.0-alpha.25`; it exists so the gate runs on a runner rather than on someone's laptop.

- Changed: nothing under `stage-kiosk/`. `git diff 1.0.0-alpha.25 1.0.0-alpha.26 -- stage-kiosk/` is empty by construction. What is new is `tests/machinery.sh`, the `machinery` CI job that `image` now depends on, and the restructured documents.
- Proved: nothing on hardware. It is the first tag whose image cannot exist unless the real `overlayroot` and the real systemd were asked what they do with it.
- Regressed: unknown. Not flashed.

`1.0.0-alpha.25` was cut before the gate existed, so CI never ran `machinery` for it. The harness was run locally against that tag's `stage-kiosk/`, which is byte-identical to this one's, and passed. This tag makes that a CI fact rather than a claim.

## 1.0.0-alpha.25 — 2026-09-01

Not yet flashed. Verdict: unproven. It is the candidate fix for `1.0.0-alpha.24` and nothing has been on hardware.

- Changed: `data.mount` and `var-log-journal.mount` are staged at `/usr/local/share/carbide-kiosk/`, outside every directory systemd searches, and `carbide-firstboot` installs them into `/etc/systemd/system/` after the partition exists and before the overlay is enabled. `create_data_partition` now unmounts and `wipefs` the new partition before `mkfs`, so a stale `CARBIDEDATA` signature left by a previous flash cannot be claimed out from under it.
- Proved: nothing. Not flashed.
- Regressed: unknown. Not flashed.

`tests/machinery.sh` was written after this tag was cut and reproduces both of the failures below offline, so it did not gate this release. It gates the next one.

## 1.0.0-alpha.24 — 2026-09-01

Flashed 2026-09-01. Verdict: broken, do not flash.

- Changed: moved `/data` and the journal bind out of `/etc/fstab` into `data.mount` and `var-log-journal.mount`, shipped into `/etc/systemd/system/` deliberately not enabled, with `carbide-firstboot` enabling them once the partition existed. Made the pre-commit hook glob `tests/*.bats` rather than run a hand-maintained list that had drifted three suites behind.
- Proved: nothing. First boot never completed, so nothing downstream of it was exercised.
- Regressed: first boot, entirely. The reasoning that an unenabled unit is inert was wrong. `carbide-kiosk.service`, `carbide-kiosk-config.service` and `carbide-kiosk-status.service` all declare `RequiresMountsFor=/data`, and systemd resolves that to a hard `Requires=` on whichever mount unit covers the path regardless of enablement. First boot stalled ninety seconds on `dev-disk-by-label-CARBIDEDATA.device`; `parted` then created the partition at the same offset where a previous flash had left a `CARBIDEDATA` filesystem, because flashing only rewrites the first few gigabytes of the card; the pending mount job fired and mounted it; and `mkfs.ext4` refused with "is mounted; will not make a filesystem here". Setup exited 1 and the machine came up with no share and no status file.

The suite written for the `1.0.0-alpha.23` fix asserted that the mount units were not enabled at build time. That is not the property that mattered, and asserting it made the failure look tested for. The suite was green.

## 1.0.0-alpha.23 — 2026-08-31

Flashed 2026-09-01. Verdict: boots and is reachable, but loses every file written to the share. Superseded.

- Changed: the access script now says why the wifi join failed rather than only that it did, and keeps saying it after first boot.
- Proved: remote access, for the first time in this project's history. The machine joined wifi with no Ethernet present, opened port 22 eleven seconds into the first boot and fifteen seconds into the second, and accepted a key from another computer on both. The overlay root is mounted read-only over `/media/root-ro` and `/boot/firmware` is remounted `ro`. The generated firewall permits 22, 445 and 139 and answers ICMP under `enable_ping=1` while dropping the rest. `smbd`, `nmbd` and `avahi-daemon` run, the share refuses unauthenticated access, and a file written from macOS arrives as `cnc:cncshare` under a setgid directory, readable by the `kiosk` account, and reads back byte-identical. Carbide Motion reaches the panel unattended, the Shapeoko enumerates as `16d0:0fa7` and is symlinked to `/dev/shapeoko`, the status file reports `Cutter: connected (/dev/ttyACM0)`, and the machine jogs. Total startup is 17.7 seconds, of which `carbide-kiosk-access` accounts for 8.8, well inside its ninety-second budget.
- Regressed: nothing new, but the run exposed the most serious defect the image has had. `carbide-firstboot` wrote the data partition into `/etc/fstab`, and `overlayroot` rewrites every ext4 entry there, in the initramfs on every boot, into a read-only mount under `/media/root-ro` with a tmpfs upper layer. The 230 GB partition was mounted read-only and received nothing while the Samba share ran entirely in RAM. Files did not survive a reboot, Carbide Motion's settings could not persist, and the journal was volatile again. It was found by accident: Finder reported 4.15 GB free on a 230 GB share.

This run also disproved the two-minute wait the test plan asked for. NetworkManager activated the wifi profile fifteen seconds into the second boot and the machine held its address from that moment, but the Mac could not reach it for a further seven minutes, because probing the address while the Pi was still rebooting left a negative ARP entry on the client that outlived the reboot. An operator following the old timing would have declared a healthy image dead. The wait is eight minutes now and the symptom is named alongside it.

A power-cut test against this image would have passed, because nothing persisted and so nothing could be corrupted — proof of exactly the property that did not hold.

## Before the ledger

These tags predate this file. Their dates and subjects are recovered from git; what each one proved on hardware was not recorded per release, and cannot be reconstructed without guessing.

- `1.0.0-alpha.22` — 2026-08-30 — Test the guard, not the machine the guard runs on
- `1.0.0-alpha.21` — 2026-08-30 — Write down the two rules this project keeps relearning
- `1.0.0-alpha.20` — 2026-08-29 — Make the pre-commit hook able to fail
- `1.0.0-alpha.19` — 2026-08-27 — Break the ordering cycle the access unit introduced
- `1.0.0-alpha.18` — 2026-08-27 — Bring up the network and the way in before anything else
- `1.0.0-alpha.17` — 2026-08-27 — Record why a tool failed, not just that a step did
- `1.0.0-alpha.16` — 2026-08-26 — Never reboot into an overlay that was not fully installed
- `1.0.0-alpha.15` — 2026-08-26 — Stop configuration from being able to hang the boot
- `1.0.0-alpha.14` — 2026-08-26 — Detect any USB serial device as the CNC, not an allowlist
- `1.0.0-alpha.13` — 2026-08-26 — Fix three CI failures, one of which was hiding the others
- `1.0.0-alpha.12` — 2026-08-26 — Stop clipping the keyboard, and lighten the gaps between keys
- `1.0.0-alpha.11` — 2026-08-26 — Bring the image up to what actually works on hardware
- `1.0.0-alpha.10` — 2026-08-26 — Create a data partition that is actually the size of the card
- `1.0.0-alpha.9` — 2026-08-26 — Assert the ssh password reaches no generated file
- `1.0.0-alpha.7` — 2026-08-25 — Fix two violations of pi-gen's stage contract
- `1.0.0-alpha.6` — 2026-08-25 — Document what the appliance does, as expectations
- `1.0.0-alpha.5` — 2026-08-25 — Run the status redaction suite in CI
- `1.0.0-alpha.4` — 2026-08-25 — Ship no known credential in the image
- `1.0.0-alpha.3` — 2026-08-25 — Install qemu-user-static for the armhf image build
- `1.0.0-alpha.2` — 2026-08-25 — Fix clean-clone staging and the overlay call
- `1.0.0-alpha.1` — 2026-08-25 — Publish tagged builds as GitHub releases

Four hardware runs happened in that window and were recorded by date rather than by tag. On 2026-08-26 a Pi 5 with a touch panel and a Shapeoko 5 Pro ran Carbide Motion and jogged the machine, but only after five defects were fixed by hand on the running machine, so nothing that day was proved from a flash. On 2026-08-29 a clean flash took the first-boot path end to end for the first time and surfaced three more defects, including an access unit that could exit without opening port 22 while reporting success. On 2026-08-30 a clean flash reached Carbide Motion unattended for the first time — the application, the floating keyboard and the session came up with no desktop and no login prompt — while everything else on that machine failed, because two units called `systemctl enable --now` from inside a unit systemd was still starting and deadlocked. That same run showed `raspi-config nonint enable_overlayfs` silently doing nothing, because it fetches the `overlayroot` package at first boot and the machine had no network.

Which tag was on the card for each of those runs is not recorded. That is the reason this file exists.
