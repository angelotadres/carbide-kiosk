#!/usr/bin/env bats
# The systemd units carry the guarantees the rest of the image depends on:
# that a failure is visible, and that the session starts even when the
# configuration run did not. Both were once lost to a single directive.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  UNITS="$REPO_ROOT/stage-kiosk/02-kiosk-session/files"
  SBIN="$UNITS/usr/local/sbin"
}

# Code lines only. The comments in these scripts name the directive they exist
# to warn against, and a check that reads them can never pass.
code() { grep -v '^[[:space:]]*#' "$1"; }

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

# --- the deadlock of 2026-08-30 -----------------------------------------
#
# Both boot scripts run as units systemd is still starting, so neither may ask
# systemd to start another unit and wait for it. carbide-kiosk-config makes
# that fatal rather than merely slow: it declares Before=ssh.service, so
# ssh.service cannot start until the script returns, and `--now` does not
# return until ssh.service has started. The pair waited on each other until
# TimeoutStartSec, and a clean flash came up with no network and no way in.

@test "the access script never waits for a unit to start" {
  ! code "$SBIN/carbide-kiosk-access" | grep -q -e 'enable --now'
  code "$SBIN/carbide-kiosk-access" | grep -q 'systemctl start --no-block ssh'
}

@test "the configuration script never waits for a unit to start" {
  ! code "$SBIN/carbide-kiosk-config" | grep -q -e 'enable --now'
  code "$SBIN/carbide-kiosk-config" | grep -q 'systemctl start --no-block ssh'
}

@test "the configuration unit is still ordered before sshd" {
  # The ordering is correct and worth keeping: configuration owns the firewall
  # and the credential, so sshd must not accept a connection before it has
  # run. It is the blocking call that was wrong, not this.
  grep -q '^Before=.*ssh.service' "$UNITS/carbide-kiosk-config.service"
}

@test "closing the port is still allowed to block" {
  # disable --now is a stop job. Stop jobs do not wait on Before= start
  # ordering, and this is the path that shuts port 22 - it should complete
  # before the script moves on, not be queued behind it.
  code "$SBIN/carbide-kiosk-config" | grep -q 'disable --now ssh'
}

@test "the unit budget fits everything the script can spend" {
  # The per-step timeouts are what stop one call hanging the boot. The unit
  # budget is what stops the collection of them being killed part way
  # through - and a step that never runs is indistinguishable from a step
  # that failed, except that nothing says so. 185s of ceilings under a 90s
  # budget is what left a wifi-only machine with no network at all.
  #
  # Summing the `timeout` literals alone undercounts: the script also has two
  # polling loops whose deadlines are arguments, not ceilings, and they are
  # spent on exactly the boot that is already going wrong. They are added here
  # so the budget covers what the script can really take.
  local spent loops budget
  spent=$(grep -oE 'timeout [0-9]+' "$SBIN/carbide-kiosk-access" \
    | awk '{s+=$2} END {print s+0}')
  loops=$(grep -oE '(wifi_device_ready|wait_for_address) [0-9]+' \
    "$SBIN/carbide-kiosk-access" | awk '{s+=$2} END {print s+0}')
  budget=$(grep -oE '^TimeoutStartSec=[0-9]+' \
    "$UNITS/carbide-kiosk-access.service" | cut -d= -f2)
  [ "$loops" -gt 0 ]
  [ "$budget" -ge "$((spent + loops))" ]
}

# --- the only off switch the machine has --------------------------------
#
# No keyboard, no dependable network shell, and no shutdown control inside
# Carbide Motion. A short press on the power button is how this machine is
# turned off, so it may not depend on whichever default a systemd release
# happens to ship. The alternative an operator falls back on is a five-second
# hold, which the Pi 5 services in hardware as an abrupt cut.

@test "a short press on the power button shuts the machine down" {
  grep -q '^HandlePowerKey=poweroff' "$UNITS/logind/carbide-power.conf"
}

@test "the long press is not claimed to be handled" {
  # The firmware cuts power at five seconds below the OS. Saying anything
  # else here would document behaviour that cannot happen.
  grep -q '^HandlePowerKeyLongPress=ignore' "$UNITS/logind/carbide-power.conf"
}

@test "nothing may defer the shutdown indefinitely" {
  grep -qE '^InhibitDelayMaxSec=[0-9]+' "$UNITS/logind/carbide-power.conf"
}

@test "the power configuration is actually installed" {
  # A file in files/ that no install line copies is invisible in the image,
  # which is the failure mode this whole suite exists for.
  grep -q 'logind.conf.d/carbide-power.conf' \
    "$(dirname "$UNITS")/00-run.sh"
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
