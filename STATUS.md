# Where the kiosk stands

Read this first. It is the whole state of the project in one file: what the machine is, which image is newest, what a clean flash has actually proved, what is broken, what is being worked on, and what to do next. It is meant to be read in two minutes by someone who has never seen this repository.

The reasoning behind the design is in [SPEC.md](SPEC.md). What each release changed, proved and regressed is in [RELEASES.md](RELEASES.md). The hardware procedure is in [TESTPLAN.md](TESTPLAN.md). The rules an agent working here must not break are in [CLAUDE.md](CLAUDE.md).

## What the machine is

A Raspberry Pi 5 image that boots straight into Carbide Motion driving a Shapeoko, with no keyboard, no desktop and no remote management. The root filesystem is read-only under an overlay, and a third partition created on first boot holds the Samba share, Carbide Motion's settings and the journal. Everything an operator can change lives in `kiosk.conf` on the boot partition, so changing anything means holding the card.

There is exactly one test rig: a Pi 5 with a 1920x1200 touch panel and a Shapeoko 5 Pro, in a different room from the Mac that drives the testing. It is wifi only. Wired DHCP is the fallback that survives a wrong or missing `kiosk.conf`, and this rig does not have it, so any defect in the wifi path is a total lockout rather than an inconvenience.

## The mistake this project keeps making

Read this before writing any code here. It has cost two images in one day and it will cost a third.

The suites in `tests/` read this repository's own files and check that they say what we meant. That catches typos. It cannot catch the thing that has actually broken every recent image, which is third-party machinery doing something to our correct-looking files that we did not expect:

- `1.0.0-alpha.23` wrote a perfectly good `/data` line into `/etc/fstab`. `overlayroot` rewrites every ext4 line there, from the initramfs on every boot, into a read-only mount under `/media/root-ro` with a tmpfs upper layer. The 230 GB share ran entirely in RAM.
- `1.0.0-alpha.24` shipped `data.mount` into `/etc/systemd/system/` deliberately not enabled, on the theory that an unenabled unit is inert. Three services declare `RequiresMountsFor=/data`, and systemd turns that into a hard `Requires=` on whichever mount unit covers the path, enabled or not. First boot died.

Both shipped through a fully green suite and a green CI. Worse, the regression test written after the first failure asserted that the mount units were "not enabled at build time" — it tested the wrong property, passed on the broken image, and made the second failure look guarded against. A test shaped like that is not a partial win; it is the defect.

Both failures were mechanically detectable on a laptop, with no hardware, and neither was detected. `tests/machinery.sh` now detects both: it installs the real `overlayroot` package and the real systemd, hands them what the image hands them, and asserts on what they do. Each of its checks carries a control case that must fail, because a harness that cannot fail is how this happened. CI runs it as the `machinery` job and the `image` job depends on it, so a tag that cannot answer for its own machinery produces no release. The rule it enforces is written out in [CLAUDE.md](CLAUDE.md) under "Our files are not the machine".

## Where things stand

The newest release is `1.0.0-beta.1`, tagged 2026-09-02. `1.0.0-alpha.27` is the image that earned it: the first where a clean flash left a working machine, and the first to cut a real piece. Storage persists, the read-only root holds, remote access works, and the cutter is driven from the panel. Its image code is identical to `1.0.0-alpha.25` — the candidate fix for the `1.0.0-alpha.24` first-boot failure — and it was re-tagged only so the `machinery` gate runs in CI rather than on a laptop. Nothing about it is proven on hardware.

`1.0.0-alpha.24` does not boot. Three services declare `RequiresMountsFor=/data`, which pulled in a mount unit for a partition that did not exist yet; the boot stalled ninety seconds on the device, and on a card that had been flashed before, the pending mount then grabbed the new partition out from under `mkfs.ext4`, which refused and killed setup.

The last image that booted is `1.0.0-alpha.23`, flashed 2026-09-01. It is the first image in this project's history to come up reachable, which is the guarantee everything else is diagnosed through. It is also the one that ran the whole share in RAM.

## Broken right now

There is no image anyone should flash for real use. `1.0.0-alpha.24` does not complete first boot, `1.0.0-alpha.23` silently loses every file written to the share, and `1.0.0-alpha.27` is untested.

The persistent journal lives on `/data`, so it went into RAM alongside the share on `1.0.0-alpha.23`. Nothing has confirmed it comes back when `/data` does.

## In flight

`1.0.0-alpha.27` is tagged and waiting for a clean flash. `1.0.0-alpha.26` was rejected by the gate before producing an image. It is the candidate fix for the first-boot failure and nothing else.

`tests/machinery.sh`, the `machinery` CI job, this file and `RELEASES.md` are committed. They were written after `1.0.0-alpha.25` was cut, so CI never ran the gate for that tag; `1.0.0-alpha.26` is the first release the gate actually stands in front of.

> [!NOTE]
> This section is prose about work in progress and nothing enforces that it is current. The release record and the table below are checked by `.githooks/pre-commit`; this paragraph is not.

## What to do next

1. Confirm CI is green on `1.0.0-alpha.27`, including the `machinery` job, and take the image from that release rather than from `deploy/`. Both alpha.23 and alpha.24 produced image files with identical names, so check the SHA256 against the release before flashing.
2. Flash it on a card that has been flashed before — a virgin card cannot reproduce the `1.0.0-alpha.24` failure, because flashing only rewrites the first few gigabytes and the stale `CARBIDEDATA` filesystem further out is half of what broke it.
3. Work [TESTPLAN.md](TESTPLAN.md) in order, stopping at the first failure. Steps T4 and T6 are the ones that catch the `1.0.0-alpha.23` defect, and T4 costs one command.
4. Record the outcome in [RELEASES.md](RELEASES.md) and update the table below, including what the run disproved.

## What a clean flash has proved

Each row is one claim, the state of that claim, the image that settled it and when, and the [TESTPLAN.md](TESTPLAN.md) step that tests it. Four states, and only these four:

- `proven` — a clean flash of the named image demonstrated it.
- `broken` — a clean flash of the named image disproved it.
- `unproven` — never demonstrated from a clean flash.
- `repaired only` — works on the rig after fixing it by hand, never from a flash. This is not proof. It is the distinction this project keeps losing time to.

| Claim | State | Image | When | Step |
| --- | --- | --- | --- | --- |
| SSH is open before first-boot setup runs | proven | 1.0.0-alpha.23 | 2026-09-01 | T0 |
| The machine joins wifi with no Ethernet present | proven | 1.0.0-alpha.23 | 2026-09-01 | T0 |
| A card with only `authorized_keys` is reachable | unproven | — | — | T0 |
| First boot completes and reboots itself | proven | 1.0.0-alpha.27 | 2026-09-01 | T1 |
| Carbide Motion reaches the panel unattended | proven | 1.0.0-alpha.23 | 2026-09-01 | T2 |
| The on-screen keyboard floats above the application | proven | unrecorded | 2026-08-30 | T2 |
| Autologin console on Ctrl+Alt+F2 | unproven | — | — | T3 |
| The root is an overlay and the boot partition is `ro` | proven | 1.0.0-alpha.23 | 2026-09-01 | T4 |
| `/data` is a real partition, not a tmpfs | proven | 1.0.0-alpha.27 | 2026-09-01 | T4 |
| The share is reachable and refuses anonymous access | proven | 1.0.0-alpha.23 | 2026-09-01 | T5 |
| The firewall permits only what `kiosk.conf` asks for | proven | 1.0.0-alpha.23 | 2026-09-01 | T5 |
| A file written to the share survives a reboot | proven | 1.0.0-alpha.27 | 2026-09-01 | T6 |
| The journal survives a reboot | proven | 1.0.0-alpha.27 | 2026-09-01 | T6 |
| The status file appears and reports real state | proven | 1.0.0-alpha.23 | 2026-09-01 | T7 |
| The status file leaks no configured password | unproven | — | — | T7 |
| The Shapeoko is detected and symlinked | proven | 1.0.0-alpha.23 | 2026-09-01 | T8 |
| Carbide Motion connects to the machine and jogs it | proven | 1.0.0-alpha.23 | 2026-09-01 | T8 |
| Cutting power mid-job leaves a bootable machine | unproven | — | — | T9 |
| The SSH host key survives a reboot | proven | 1.0.0-alpha.27 | 2026-09-01 | T6 |
| A short press on the power button shuts the machine down | broken | 1.0.0-alpha.27 | 2026-09-01 | T3 |
| A changed `kiosk.conf` takes effect on the next boot | unproven | — | — | T10 |
| Carbide Motion loads a job and cuts it | proven | 1.0.0-alpha.27 | 2026-09-01 | T11 |
| Rendering holds up on large jobs (~100 MB) | unproven | — | — | T11 |

An `unrecorded` image means a flash happened on that date and nobody wrote down which tag was on the card. That is the gap [RELEASES.md](RELEASES.md) exists to close, and the two entries above it are the only ones left.

## What this rig cannot test

A card with no `kiosk.conf` and only an `authorized_keys` file is the case that used to lock the machine out silently, and it cannot be tested here. With no `kiosk.conf` there is no wifi configuration, `join_network` says so and returns, and a rig with no Ethernet has no network to be reachable over. Closing that claim needs a wired location or a second rig.

Power-loss resilience is testable here, but it was untestable in a stronger sense on `1.0.0-alpha.23`: with the share running in RAM, the power-cut run would have passed while proving nothing, because nothing persisted and so nothing could be corrupted. Do not run T9 against an image that has not passed T4 and T6 first.

## The one capability that does not exist

No keyboard can appear when a text field is focused. That needs the application to publish focus over accessibility, and Carbide Motion does not. The keyboard is summoned by hand from a launcher instead. This is not a defect to be fixed.
