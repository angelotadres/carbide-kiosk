#!/usr/bin/env bats
# The systemd units carry the guarantees the rest of the image depends on:
# that a failure is visible, and that the session starts even when the
# configuration run did not. Both were once lost to a single directive.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  UNITS="$REPO_ROOT/stage-kiosk/02-kiosk-session/files"
}

@test "the access unit does not report a failed run as success" {
  # SuccessExitStatus=0 1 once turned an exit that never opened port 22 into
  # a unit systemd called successful, so nothing anywhere said the machine
  # had sealed itself shut.
  ! grep -q '^SuccessExitStatus=' "$UNITS/carbide-kiosk-access.service"
}

@test "the access unit runs before first boot and before configuration" {
  grep -q '^Before=carbide-firstboot.service carbide-kiosk-config.service' \
    "$UNITS/carbide-kiosk-access.service"
}

@test "the access unit is bounded so it cannot hold the boot" {
  grep -qE '^TimeoutStartSec=[0-9]+' "$UNITS/carbide-kiosk-access.service"
}

@test "a missing working directory does not stop the session" {
  # Without the leading '-' systemd refuses to start the unit at all, which
  # made a configuration failure take the application down - the exact thing
  # Wants= rather than Requires= exists to prevent.
  grep -q '^WorkingDirectory=-' "$UNITS/carbide-kiosk.service"
}

@test "the session wants configuration rather than requiring it" {
  grep -q '^Wants=carbide-kiosk-config.service' "$UNITS/carbide-kiosk.service"
  ! grep -q '^Requires=carbide-kiosk-config.service' "$UNITS/carbide-kiosk.service"
}

@test "the session working directory is one configuration maintains" {
  # It follows samba_share_name through a symlink. A path under /data hardcoded
  # to the default share name is never created when the share is renamed.
  grep -q '^WorkingDirectory=-/home/kiosk/gcode' "$UNITS/carbide-kiosk.service"
  grep -q 'ln -sfn "$KIOSK_DATA/$share" /home/kiosk/gcode' \
    "$UNITS/usr/local/sbin/carbide-kiosk-config"
}

@test "the access unit is not gated on a file a fresh flash does not have" {
  # ConditionPathExists=/boot/firmware/kiosk.conf skipped this unit entirely on
  # every clean flash, and systemd reports a skipped condition as success - so
  # the machine came up unreachable with nothing anywhere saying why.
  ! grep -q '^ConditionPathExists=' "$UNITS/carbide-kiosk-access.service"
  ! grep -q '^RequiresMountsFor=' "$UNITS/carbide-kiosk-access.service"
}

@test "the access unit runs its own script, not the configuration script" {
  # Sharing a file with 400 lines of unrelated configuration meant a parse
  # error anywhere in it took the way in down too. Bash parses the whole file
  # before running any of it, so the fault need not even be on the path taken.
  grep -q '^ExecStart=/usr/local/sbin/carbide-kiosk-access$' \
    "$UNITS/carbide-kiosk-access.service"
  ! grep -q 'access-only' "$UNITS/usr/local/sbin/carbide-kiosk-config"
}

@test "the access script shares no code with the configuration script" {
  # Comments may name them - the script explains what runs after it. What it
  # must never do is source or run either one, because then a fault in them
  # becomes a fault in the way in.
  run grep -nE '^[[:space:]]*(\.|source)[[:space:]]|carbide-kiosk-config[[:space:]]*(--|$)' \
    "$UNITS/usr/local/sbin/carbide-kiosk-access"
  [ "$status" -ne 0 ]
}

@test "a missing kiosk.conf is announced where it can be seen" {
  # kiosk_die writes only to the journal. Configuration refusing to run is not
  # a lockout any more, but it still has to be visible from the boot partition.
  grep -q 'kiosk_alert "\$KIOSK_CONF is missing' \
    "$UNITS/usr/local/sbin/carbide-kiosk-config"
}
