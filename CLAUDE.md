# Working on carbide-kiosk

This image runs a CNC machine on a Raspberry Pi with no keyboard, no desktop and no remote management. Every rule below exists because breaking it cost a real evening of someone's time.

## Remote access is a guarantee, not a feature

The image must always come up with SSH reachable and a network joined, as an isolated service that shares fate with nothing else. SSH is off by default for security, so "reachable" means the machine honours `enable_ssh=1` and an `authorized_keys` file the moment either is present, and says so out loud when it will not.

`carbide-kiosk-access` is that service and it is deliberately paranoid. Keep it that way:

- It is a standalone script. It must never source `common.sh` or call `carbide-kiosk-config` — bash parses a whole file before running any of it, so a syntax error on a path this script never takes would still take the way in down.
- It runs before everything: `Before=carbide-firstboot.service carbide-kiosk-config.service`. Never gate it on `ConditionPathExists` or `RequiresMountsFor`. A fresh flash has no `kiosk.conf`, and systemd reports a skipped condition as success, which is how a lockout became invisible.
- Every outcome goes to `tty1` and to `first-boot.log` on the boot partition. Never only the journal — the journal is unreadable on precisely the machine these messages are for.
- It brings the network up itself rather than waiting for `network.target`. Waiting closes an ordering cycle through `nftables.service`.
- Never ask systemd to start a unit and wait for it from inside a boot script. `systemctl enable --now` deadlocks: the script is a unit systemd is still starting, and `carbide-kiosk-config` is ordered `Before=ssh.service`, so the two wait on each other until the unit is killed. Enable the unit, then `systemctl start --no-block`.
- Every step announces itself before it runs. A step that hangs is killed with no output of its own, so without a breadcrumb ahead of it the log ends on the last thing that succeeded and names nothing.
- Bound every call that can hang, and keep the sum under the unit's `TimeoutStartSec`. `tests/units.bats` adds them up and fails when they stop fitting.

The test rig has no ethernet. Wired DHCP is the fallback that survives a wrong or absent `kiosk.conf`, and this machine does not have it, so any defect in the wifi path is a total lockout rather than an inconvenience.

## Images come from CI, never from a local build

When work is done and it needs testing on hardware, the deliverable is a GitHub release, not a file in `deploy/`. Push the commits, tag, and let CI build and publish it.

```bash
git push origin main
git tag 1.0.0-alpha.N && git push origin 1.0.0-alpha.N
```

The workflow builds on any tag matching `[0-9]*` and runs `gh release create` with the image and its checksum attached. Releases are at <https://github.com/angelotadres/carbide-kiosk/releases>.

Never hand over a locally built image to flash. A local build is fine for checking that the build still works, but `deploy/` accumulates images across builds, pi-gen re-copies all of them at the end of every run so their timestamps are identical, and the filenames differ by a single digit. Pointing someone at that directory is how a two-hour session ends up testing yesterday's bits.

State plainly whether a given image contains a given change, and verify it rather than assuming. The image manifest, `deploy/<date>-carbide-kiosk.info`, lists installed packages; `initramfs8` changes size when the overlay hook goes in.

## Hardware is the only proof

Anything working on a running Pi is unproven in the image until a clean flash reaches it. That gap is where this project keeps losing time, and it is invisible unless stated explicitly. Fix a problem on the machine first to confirm the fix is real, then write it into `stage-kiosk/` and commit — but never report it as fixed in the image on that basis. First-boot-path changes are the exception, because they cannot be confirmed on an already-repaired machine.

`SPEC.md` carries a "Confirmed on hardware" section separating what real hardware proved from what is still untested. Update it after every hardware run, including what the run disproved.

Prefer troubleshooting the Pi directly over relaying instructions through whoever is standing next to it. `TESTPLAN.md` is ordered by risk so a bad image is found in ten minutes rather than two hours.

## Conventions

Runtime settings live in `kiosk.conf` on the boot partition and are regenerated on every boot; build-time settings live in `build.conf`. `config/kiosk.conf.example` is the template and the pre-commit hook fails when it and the code disagree about which keys exist.

Every fix leaves a test behind. The suites run the scripts against stubs rather than grepping them, and they run on macOS as well as Linux, so anything the script shells out to needs a stub — including `timeout`, which macOS does not have.

Run what CI runs before saying something passes:

```bash
npx --yes bats@1.11.0 tests/*.bats
docker run --rm -v "$PWD:/work" -w /work debian:bookworm bash -c 'apt-get update -qq && apt-get install -y -qq shellcheck && shellcheck -x -e SC1091,SC2154 $(find . -path ./pi-gen -prune -o -type f \( -name "*.sh" -o -name "carbide-*" \) -print | grep -vE "\.service$|\.conf$")'
```

Install nothing globally to do it. The pre-commit hook falls back to Docker for both tools, and so should you.
