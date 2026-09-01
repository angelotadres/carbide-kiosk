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

@test "no mount unit is installed where systemd can see it" {
  # This is the property that matters, and 1.0.0-alpha.24 tested the wrong
  # one. It shipped data.mount into /etc/systemd/system merely *disabled*, on
  # the theory that an unenabled unit is inert. It is not: carbide-kiosk,
  # carbide-kiosk-config and carbide-kiosk-status all declare
  # RequiresMountsFor=/data, which pulls in whichever mount unit covers that
  # path with a hard Requires regardless of enablement. First boot stalled
  # ninety seconds on a device no partition had been created for yet, then a
  # stale filesystem got mounted under mkfs and setup died.
  #
  # A unit systemd cannot see cannot be required.
  # All five directories systemd actually searches, /usr/local/lib included -
  # that one is easy to forget and is a real unit path.
  ! code "$RUN" | grep -E 'install .*\.mount' \
    | grep -qE '/(etc|run|usr/lib|usr/local/lib|lib)/systemd/system'
}

@test "the mount units are staged outside every systemd search path" {
  code "$RUN" | grep -q 'usr/local/share/carbide-kiosk'
}

@test "first boot installs the units into a systemd directory itself" {
  code "$FIRSTBOOT" | grep -qE 'install .*data\.mount.* /etc/systemd/system'
  code "$FIRSTBOOT" | grep -qE 'install .*var-log-journal\.mount'
}

@test "a stale filesystem is wiped before the new one is made" {
  # Flashing rewrites only the first few GB, so a recreated partition at the
  # same offset exposes the previous run's ext4 superblock and its label.
  code "$FIRSTBOOT" | grep -q 'wipefs -a'
  # ...and the wipe has to come before mkfs, or it destroys the new filesystem.
  [ "$(code "$FIRSTBOOT" | grep -n 'wipefs -a' | cut -d: -f1)" \
    -lt "$(code "$FIRSTBOOT" | grep -n 'mkfs.ext4' | cut -d: -f1)" ]
}

@test "first boot enables both units once the partition is real" {
  code "$FIRSTBOOT" | grep -q 'systemctl enable data.mount var-log-journal.mount'
}

@test "first boot never waits on the mount units it enables" {
  # Same deadlock that cost the 2026-08-30 flash: this runs inside a unit
  # systemd is still starting, so it may enable but never --now.
  ! code "$FIRSTBOOT" | grep -E 'systemctl' | grep -q -- '--now'
}
