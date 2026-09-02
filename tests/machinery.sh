#!/usr/bin/env bash
# What the third-party machinery does with our files, asked of the machinery.
#
# Every other suite in this directory reads this repository's own files and
# checks that they say what we meant. That is worth having and it is not
# evidence. Twice in one day it shipped a broken image through a green suite:
#
#   1.0.0-alpha.23 wrote a correct /data line into /etc/fstab. overlayroot's
#   initramfs script rewrites every ext4 line there into a read-only mount
#   under /media/root-ro with a tmpfs upper layer, so the 230 GB share ran
#   entirely in RAM and every file copied to it vanished on reboot.
#
#   1.0.0-alpha.24 shipped data.mount into /etc/systemd/system deliberately
#   not enabled, on the theory that an unenabled unit is inert. Three services
#   declare RequiresMountsFor=/data, and systemd turns that into a hard
#   Requires= on whichever mount unit covers the path, enabled or not. First
#   boot stalled ninety seconds on a device no partition existed for, then a
#   stale filesystem got mounted under mkfs and setup died.
#
# In both cases the assertion available to a test that reads our own files was
# true and the machine was broken. So this script does not read our files. It
# installs the real overlayroot package and the real systemd, hands them what
# the image hands them, and asks what they do with it.
#
# Every check here has a control: a case where the machinery must produce the
# failure. A harness that cannot fail proves nothing, which is exactly how the
# regression test written after 1.0.0-alpha.23 passed on 1.0.0-alpha.24.
#
# Needs root, systemd, and the overlayroot package. CI runs it in a Debian
# Bookworm container; see .github/workflows/ci.yml.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
ROOTFS="$WORK/rootfs"
ENABLED="$WORK/enable-commands"
failed=0

trap 'rm -rf "$WORK"' EXIT

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; failed=1; }

need() {
  command -v "$1" >/dev/null 2>&1 \
    || { printf 'machinery: %s is not installed\n' "$1" >&2; exit 2; }
}

# This script writes to /etc/fstab and runs first-boot code as root, because
# that is what it takes to ask the real machinery a real question. On a
# throwaway container that is free; on a laptop it is somebody's afternoon.
if [ ! -e /.dockerenv ] && [ ! -e /run/.containerenv ] \
   && [ "${CARBIDE_MACHINERY_DISPOSABLE:-0}" != "1" ]; then
  cat >&2 <<'REFUSE'
machinery: this rewrites /etc/fstab and runs first-boot code as root, so it
machinery: only runs somewhere disposable. Use a container:
machinery:
machinery:   docker run --rm -v "$PWD:/work" -w /work debian:bookworm bash -c \
machinery:     'apt-get update -qq && apt-get install -y -qq systemd overlayroot \
machinery:      && bash tests/machinery.sh'
machinery:
machinery: Set CARBIDE_MACHINERY_DISPOSABLE=1 only on a machine you can throw away.
REFUSE
  exit 2
fi

need systemctl
need systemd
need awk

# --- 1. build the rootfs the way the stages build it -----------------------
#
# By running them, not by reading them. A stage that starts installing a unit
# somewhere new is then covered without anyone remembering to add it here.

build_rootfs() {
  mkdir -p \
    "$ROOTFS/etc/systemd/system" \
    "$ROOTFS/etc/udev/rules.d" \
    "$ROOTFS/usr/lib/systemd/system" \
    "$ROOTFS/usr/local/bin" \
    "$ROOTFS/usr/local/sbin" \
    "$ROOTFS/usr/local/lib" \
    "$ROOTFS/usr/local/share" \
    "$ROOTFS/boot/firmware" \
    "$ROOTFS/root"
  : > "$ROOTFS/boot/firmware/config.txt"
  printf 'console=tty1 root=PARTUUID=6545d84b-02 rootfstype=ext4 rootwait\n' \
    > "$ROOTFS/boot/firmware/cmdline.txt"

  # pi-gen's on_chroot runs its heredoc inside the image. Here it is captured
  # instead, so the systemctl enable lines the stages ask for can be replayed
  # against the rootfs with systemctl --root, which is the real enabling code.
  : > "$ENABLED"
  cp -a "$REPO_ROOT/stage-kiosk" "$WORK/stage-kiosk"
  # Proprietary, fetched at build time, never committed. Its content is
  # irrelevant to every question this script asks.
  : > "$WORK/stage-kiosk/01-carbide-motion/files/carbidemotion.deb"

  local stage
  for stage in "$WORK"/stage-kiosk/*/00-run.sh; do
    (
      cd "$(dirname "$stage")" || exit 1
      export ROOTFS_DIR="$ROOTFS"
      export CAPTURE="$ENABLED"
      # shellcheck disable=SC2329  # invoked by the stage scripts, via export -f
      on_chroot() { cat >> "$CAPTURE"; }
      export -f on_chroot
      bash -e "./$(basename "$stage")"
    ) || { printf 'machinery: %s failed\n' "$stage" >&2; exit 2; }
  done

  # Replay only the enablement, with systemd's own tool. Everything else in
  # those heredocs touches an image we do not have.
  grep -oE 'systemctl enable [a-zA-Z0-9@._ -]+' "$ENABLED" \
    | sed 's/^systemctl enable //' \
    | tr ' ' '\n' | grep -vE '^$' | sort -u \
    | while read -r unit; do
        systemctl --root="$ROOTFS" enable "$unit" >/dev/null 2>&1 || true
      done
}

# --- 2. what systemd does with our units -----------------------------------
#
# systemd --system --test computes the initial transaction and dumps every
# unit in it with the edges it resolved, without starting anything and without
# privileges. RequiresMountsFor shows up there as "Requires: <x>.mount
# (origin-path)" - the same edge that stalled first boot on 1.0.0-alpha.24,
# visible on a laptop.

transaction() {
  local extra="${1:-}" out="$2"
  # The image's unit directories, then the distribution's for the targets and
  # stock units ours order against. Never the host's /etc/systemd/system: the
  # question is what the image ships, and a unit belonging to the machine
  # running the test would answer it wrongly in both directions.
  local path="$ROOTFS/etc/systemd/system:$ROOTFS/usr/lib/systemd/system:/usr/lib/systemd/system"
  [ -n "$extra" ] && path="$extra:$path"
  # Not as root: systemd refuses test mode for root, on the grounds that a
  # mistake there is a running init rather than a dry run.
  su carbide-test -c \
    "SYSTEMD_UNIT_PATH='$path' systemd --system --test --no-pager \
       --unit=multi-user.target" > "$out" 2>&1
}

mount_requirements() {
  # Every hard Requires on a mount unit, with the unit that declares it.
  awk '
    /^\t-> Unit / { unit = $3; sub(/:$/, "", unit) }
    /^\t\tRequires: .*\.mount/ { print unit " requires " $2 }
  ' "$1" | grep -v ' requires -\.mount$' | sort -u
}

check_systemd() {
  local clean="$WORK/transaction-clean" seeded="$WORK/transaction-seeded"

  transaction "" "$clean"
  if ! grep -q 'carbide-kiosk.service' "$clean"; then
    fail "systemd --test did not load our units at all; the harness is broken"
    return
  fi

  local required
  required="$(mount_requirements "$clean")"
  if [ -n "$required" ]; then
    fail "a shipped unit requires a mount unit that first boot has not created:"
    printf '        %s\n' "$required" >&2
  else
    pass "no shipped unit requires a mount unit (1.0.0-alpha.24)"
  fi

  # The control. Put data.mount where systemd can see it and the edge must
  # appear, because RequiresMountsFor really does create it. If it does not,
  # the check above is passing for the wrong reason and is worthless.
  local seed="$WORK/seeded-units"
  mkdir -p "$seed"
  cp "$REPO_ROOT/stage-kiosk/07-firstboot/files/data.mount" "$seed/data.mount"
  transaction "$seed" "$seeded"
  if mount_requirements "$seeded" | grep -q 'requires data\.mount'; then
    pass "control: a visible data.mount is required by RequiresMountsFor"
  else
    fail "control failed: systemd did not require a visible data.mount, so the check above proves nothing"
  fi
}

# --- 3. what overlayroot does with our fstab -------------------------------
#
# overlayrootify_fstab is a shell function in the package's initramfs script.
# It is extracted by name rather than reimplemented: if a future overlayroot
# renames or drops it, the extraction fails loudly instead of validating
# against a copy of behaviour that no longer exists.

OVERLAY_SCRIPT=/usr/share/initramfs-tools/scripts/init-bottom/overlayroot

extract_rewriter() {
  local out="$1" fn
  [ -f "$OVERLAY_SCRIPT" ] || {
    printf 'machinery: %s is missing; install the overlayroot package\n' \
      "$OVERLAY_SCRIPT" >&2
    exit 2
  }
  {
    printf 'MYTAG=overlayroot\n'
    for fn in clean_path needs_workdir get_workdir overlayrootify_fstab; do
      sed -n "/^${fn}()/,/^}/p" "$OVERLAY_SCRIPT"
      grep -qE "^${fn}\(\)" "$OVERLAY_SCRIPT" || {
        printf 'machinery: overlayroot no longer defines %s\n' "$fn" >&2
        exit 2
      }
    done
    # shellcheck disable=SC2016  # $1 is for the generated script, not this one
    printf 'overlayrootify_fstab "$1"\n'
  } > "$out"
}

rewrite() { sh "$WORK/rewriter" "$1"; }

check_overlayroot() {
  extract_rewriter "$WORK/rewriter"

  # The control first, because it is what makes the real check mean anything.
  # This is the fstab 1.0.0-alpha.23 shipped.
  cat > "$WORK/fstab-alpha23" <<'FSTAB'
proc /proc proc defaults 0 0
PARTUUID=6545d84b-01 /boot/firmware vfat defaults 0 2
PARTUUID=6545d84b-02 / ext4 defaults,noatime 0 1
LABEL=CARBIDEDATA /data ext4 defaults,noatime,commit=1 0 2
/data/log/journal /var/log/journal none bind 0 0
FSTAB
  local out
  out="$(rewrite "$WORK/fstab-alpha23")"
  if printf '%s\n' "$out" | grep -q 'lowerdir=/media/root-ro/data'; then
    pass "control: overlayroot really does swallow a /data line in fstab"
  else
    fail "control failed: overlayroot left the 1.0.0-alpha.23 fstab alone, so the check below proves nothing"
    printf '%s\n' "$out" >&2
  fi

  # The real check. Whatever the image and first boot leave in /etc/fstab,
  # nothing the appliance needs to persist may come out of the rewriter as an
  # overlay - and the only way to guarantee that is for it not to be there.
  out="$(rewrite "$(fstab_after_first_boot)")"
  local swallowed
  swallowed="$(printf '%s\n' "$out" \
    | grep -E 'lowerdir=/media/root-ro(/data|/var/log/journal)')"
  if [ -n "$swallowed" ]; then
    fail "overlayroot turns a persistent mount into a tmpfs overlay (1.0.0-alpha.23):"
    printf '        %s\n' "$swallowed" >&2
  else
    pass "overlayroot leaves /data and the journal alone (1.0.0-alpha.23)"
  fi
}

# The fstab a machine has once first boot has run, obtained by running first
# boot rather than by grepping it. The container's own /etc/fstab is seeded
# with what Raspberry Pi OS ships and then handed to the real code, so a write
# to the literal path /etc/fstab is caught the same as any other. The correct
# answer is that nothing is added; this is the code path that once answered
# otherwise, and did it in a line that read perfectly well.
fstab_after_first_boot() {
  cat > /etc/fstab <<'FSTAB'
proc /proc proc defaults 0 0
PARTUUID=6545d84b-01 /boot/firmware vfat defaults 0 2
PARTUUID=6545d84b-02 / ext4 defaults,noatime 0 1
FSTAB
  (
    export CARBIDE_KIOSK_LIB="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk"
    export CARBIDE_UNIT_SOURCE="$REPO_ROOT/stage-kiosk/07-firstboot/files"
    PATH="$WORK/stubs:$PATH"
    # shellcheck disable=SC1090
    source "$REPO_ROOT/stage-kiosk/07-firstboot/files/carbide-firstboot"
    mount_data_partition
  ) >/dev/null 2>&1
  printf '%s\n' /etc/fstab
}

make_stubs() {
  mkdir -p "$WORK/stubs"
  local tool
  for tool in mount systemctl chown udevadm partprobe blkid wipefs; do
    printf '#!/bin/sh\nexit 0\n' > "$WORK/stubs/$tool"
    chmod 755 "$WORK/stubs/$tool"
  done
}

# --- run -------------------------------------------------------------------

id -u carbide-test >/dev/null 2>&1 || useradd -m carbide-test
make_stubs
build_rootfs
chmod -R a+rX "$WORK"
check_systemd
check_overlayroot

if [ "$failed" -ne 0 ]; then
  printf '\nmachinery: the image does not survive contact with its own machinery.\n' >&2
  printf 'machinery: do not tag this. See CLAUDE.md, "Our files are not the machine".\n' >&2
fi
exit "$failed"
