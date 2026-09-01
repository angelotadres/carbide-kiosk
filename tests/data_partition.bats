#!/usr/bin/env bats
# The data partition is the one filesystem in this image that must survive a
# reboot, and on 2026-09-01 it did not. carbide-firstboot wrote it to
# /etc/fstab; overlayroot rewrites every ext4 entry there into a read-only
# mount under /media/root-ro with a tmpfs upper layer, so the share ran
# entirely in RAM. Files vanished on reboot, the share advertised 3.9 GB of
# memory rather than 230 GB of card, and the real partition received nothing.
#
# The symptom was invisible from inside: a power-cut test would have passed,
# because nothing persisted and so nothing could be corrupted.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STAGE="$REPO_ROOT/stage-kiosk/07-firstboot"
  FIRSTBOOT="$STAGE/files/carbide-firstboot"
  DATA_MOUNT="$STAGE/files/data.mount"
  JOURNAL_MOUNT="$STAGE/files/var-log-journal.mount"
  RUN="$STAGE/00-run.sh"
}

# Code lines only. These files name the mistake they exist to prevent, so a
# check that reads their comments can never fail.
code() { grep -v '^[[:space:]]*#' "$1"; }

@test "the data partition is never written to /etc/fstab" {
  ! code "$FIRSTBOOT" | grep -E 'fstab' | grep -q 'DATA_LABEL\|CARBIDEDATA'
}

@test "the journal bind is never written to /etc/fstab" {
  ! code "$FIRSTBOOT" | grep -E 'fstab' | grep -q 'journal'
}

@test "first boot writes nothing to fstab at all" {
  # The whole file, not just the data function: any ext4 line added anywhere
  # is swept into the overlay the same way.
  ! code "$FIRSTBOOT" | grep -qE '>>[[:space:]]*/etc/fstab'
}

@test "the data partition is mounted by a unit, where overlayroot cannot reach it" {
  [ -f "$DATA_MOUNT" ]
  grep -q '^What=/dev/disk/by-label/CARBIDEDATA$' "$DATA_MOUNT"
  grep -q '^Where=/data$' "$DATA_MOUNT"
  grep -q '^Type=ext4$' "$DATA_MOUNT"
}

@test "the data mount is read-write and is not itself an overlay" {
  run grep '^Options=' "$DATA_MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" != *",ro,"* ]]
  [[ "$output" != *"=ro,"* ]]
  [[ "$output" != *",ro" ]]
  # Comments stripped: this file explains overlayroot by name, at length.
  ! code "$DATA_MOUNT" | grep -qi 'overlay\|tmpfs\|lowerdir\|upperdir' 
}

@test "the journal lands on the data partition and waits for it" {
  [ -f "$JOURNAL_MOUNT" ]
  grep -q '^What=/data/log/journal$' "$JOURNAL_MOUNT"
  grep -q '^Where=/var/log/journal$' "$JOURNAL_MOUNT"
  grep -q '^RequiresMountsFor=/data$' "$JOURNAL_MOUNT"
}

@test "both units are installed into the image" {
  grep -q 'files/data.mount' "$RUN"
  grep -q 'files/var-log-journal.mount' "$RUN"
}

@test "neither mount unit is enabled at build time" {
  # There is no partition until first boot creates one. An enabled mount unit
  # waiting on a device that does not exist times out and takes
  # local-fs.target with it, on the one boot that must not fail.
  ! code "$RUN" | grep -E 'systemctl enable' | grep -q 'mount'
}

@test "first boot enables both units once the partition is real" {
  code "$FIRSTBOOT" | grep -q 'systemctl enable data.mount var-log-journal.mount'
}

@test "first boot never waits on the mount units it enables" {
  # Same deadlock that cost the 2026-08-30 flash: this runs inside a unit
  # systemd is still starting, so it may enable but never --now.
  ! code "$FIRSTBOOT" | grep -E 'systemctl' | grep -q -- '--now'
}
