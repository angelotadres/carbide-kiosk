#!/usr/bin/env bats
# The way in. This suite exists because the image has twice shipped a machine
# nobody could reach and that said nothing about it: once because the access
# unit was gated on a kiosk.conf that a fresh flash does not have, and once
# because the only report of the failure went to a journal that cannot be read
# without the access the failure removed.
#
# So these tests run the script rather than grepping it, against a fake boot
# partition and stubbed system tools.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/sbin/carbide-kiosk-access"

  export CARBIDE_BOOT_DIR="$BATS_TEST_TMPDIR/firmware"
  export CARBIDE_ETC_DIR="$BATS_TEST_TMPDIR/etc"
  mkdir -p "$CARBIDE_BOOT_DIR" "$CARBIDE_ETC_DIR"

  # Stubs, on PATH ahead of anything real. Each records that it was called so
  # a test can assert on what the script tried to do to the machine.
  STUBS="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS"
  for tool in systemctl nft ssh-keygen chpasswd nmcli raspi-config hostname chown; do
    cat > "$STUBS/$tool" <<STUB
#!/bin/sh
printf '%s %s\n' "$tool" "\$*" >> "$BATS_TEST_TMPDIR/calls"
exit 0
STUB
    chmod 755 "$STUBS/$tool"
  done
  # `timeout` is coreutils - always there on the Debian image, absent on
  # macOS, and commit 834de84 runs these suites on both. Unstubbed, every
  # call the script bounds would simply not run here. Drops the duration and
  # execs the rest, so the stub below still records what was asked for.
  cat > "$STUBS/timeout" <<'STUB'
#!/bin/sh
shift
exec "$@"
STUB
  chmod 755 "$STUBS/timeout"

  # ssh-keygen has to leave a file behind or the script cannot chmod it.
  cat > "$STUBS/ssh-keygen" <<STUB
#!/bin/sh
printf 'ssh-keygen %s\n' "\$*" >> "$BATS_TEST_TMPDIR/calls"
while [ \$# -gt 0 ]; do
  [ "\$1" = "-f" ] && { mkdir -p "\$(dirname "\$2")"; : > "\$2"; }
  shift
done
exit 0
STUB
  chmod 755 "$STUBS/ssh-keygen"
  PATH="$STUBS:$PATH"

  source "$SCRIPT"
  LOG="$CARBIDE_BOOT_DIR/first-boot.log"
}

called() { grep -q "$1" "$BATS_TEST_TMPDIR/calls" 2>/dev/null; }

# --- the lockout this was built to end ----------------------------------

@test "a boot partition with no kiosk.conf still says what happened" {
  run main
  [ "$status" -eq 0 ]
  grep -q "no kiosk.conf" "$LOG"
}

@test "no config and no key refuses the port loudly rather than silently" {
  run main
  # The operator has to be told, because an unreachable machine that chose to
  # be unreachable looks exactly like one that crashed.
  grep -q "NO WAY IN" "$LOG"
  ! called "nft -f"
}

@test "a key on the boot partition alone opens the port" {
  # The whole point: no kiosk.conf at all, and the machine is still reachable.
  printf 'ssh-ed25519 AAAATESTKEY carbide@test\n' > "$CARBIDE_BOOT_DIR/authorized_keys"
  run main
  [ "$status" -eq 0 ]
  called "systemctl start --no-block ssh"
  grep -q "dport 22" "$CARBIDE_ETC_DIR/nftables.conf"
}

@test "the key from the boot partition reaches authorized_keys" {
  printf 'ssh-ed25519 AAAATESTKEY carbide@test\n' > "$CARBIDE_BOOT_DIR/authorized_keys"
  # bats folds stderr into $output and the script announces the source there,
  # so the key is the last line rather than the whole of it.
  run authorized_key
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "ssh-ed25519 AAAATESTKEY carbide@test" ]
}

@test "a comment in authorized_keys is not mistaken for a key" {
  printf '# my laptop\nssh-ed25519 AAAAREAL carbide@test\n' > "$CARBIDE_BOOT_DIR/authorized_keys"
  run authorized_key
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "ssh-ed25519 AAAAREAL carbide@test" ]
}

# --- kiosk.conf stays authoritative when it exists -----------------------

@test "an explicit enable_ssh=0 keeps the port shut" {
  printf 'enable_ssh=0\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  [ "$status" -eq 0 ]
  grep -q "port 22 stays shut by request" "$LOG"
  ! called "systemctl start"
}

@test "a key in kiosk.conf opens the port" {
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  called "systemctl start --no-block ssh"
  grep -q "PubkeyAuthentication yes" "$CARBIDE_ETC_DIR/ssh/sshd_config.d/carbide-kiosk.conf"
  grep -q "PasswordAuthentication no" "$CARBIDE_ETC_DIR/ssh/sshd_config.d/carbide-kiosk.conf"
}

@test "a password opens the port and permits password login" {
  printf 'enable_ssh=1\nssh_password=troubleshooting\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  called "chpasswd"
  grep -q "PasswordAuthentication yes" "$CARBIDE_ETC_DIR/ssh/sshd_config.d/carbide-kiosk.conf"
}

@test "the ssh password is never written to a file" {
  printf 'enable_ssh=1\nssh_password=troubleshooting\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  # kiosk.conf itself holds it; nothing this script generates may.
  ! grep -rq troubleshooting "$CARBIDE_ETC_DIR"
}

@test "a kiosk.conf that never says enable_ssh warns that the port will close" {
  # carbide-kiosk-config runs seconds later and reclaims policy. From an ssh
  # client that looks identical to the machine crashing.
  printf 'ssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  grep -q "configuration will close port 22" "$LOG"
}

# --- the hardening must not be lost in the standalone path ---------------

@test "the generated sshd config is hardened" {
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  local d="$CARBIDE_ETC_DIR/ssh/sshd_config.d/carbide-kiosk.conf"
  grep -q "PermitRootLogin no" "$d"
  grep -q "PermitEmptyPasswords no" "$d"
  grep -q "AllowUsers kiosk" "$d"
  grep -q "MaxAuthTries 3" "$d"
  grep -q "AllowTcpForwarding no" "$d"
}

@test "the access ruleset drops everything except the port it opens" {
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  local r="$CARBIDE_ETC_DIR/nftables.conf"
  grep -q "policy drop" "$r"
  grep -q "dport 22" "$r"
  # Samba is the full ruleset's business, not this one's.
  ! grep -q "dport 445" "$r"
}

# --- ordering, which is the whole guarantee ------------------------------

@test "the port opens before the network is joined" {
  # sshd and nftables need no link. Joining wifi first meant a slow
  # association could spend the entire start budget and leave port 22 shut.
  run awk '/^main\(\)/,/^}/' "$SCRIPT"
  ssh_at=$(printf '%s\n' "$output" | grep -n 'open_port_22' | head -1 | cut -d: -f1)
  net_at=$(printf '%s\n' "$output" | grep -n 'join_network' | tail -1 | cut -d: -f1)
  [ -n "$ssh_at" ] && [ -n "$net_at" ] && [ "$ssh_at" -lt "$net_at" ]
}

# The 2026-08-30 lockout. `systemctl enable --now ssh` asks systemd to start
# a unit and waits for it, from inside a unit systemd is still starting.
# ssh.service is ordered After=network.target, which sits downstream of the
# nftables ordering this unit deliberately runs outside of, so the wait never
# returned. The unit was killed at TimeoutStartSec=90, join_network below it
# never ran, and a machine with no wired fallback came up with no network and
# no way in - having logged nothing since "opening remote access".
@test "sshd is queued, never waited on" {
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  called "systemctl start --no-block ssh"
  ! grep -q -e "--now" "$BATS_TEST_TMPDIR/calls"
}

@test "no blocking systemctl call survives anywhere in the script" {
  # Mechanical rather than behavioural: --now is the whole defect, and it must
  # not come back on a path no test happens to exercise.
  ! grep -v '^[[:space:]]*#' "$SCRIPT" | grep -q -e '--now'
}

@test "the network is joined even though sshd was only queued" {
  # The point of not waiting. join_network runs after the ssh block, so
  # anything that stalls there takes the network down with it.
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\nwifi_ssid=workshop\nwifi_password=secret\n' \
    > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  [ "$status" -eq 0 ]
  called "nmcli connection reload"
}

# A step that hangs is killed with no output of its own, so the log ends on
# the last thing that finished. Announcing each step before running it is what
# turns "it stopped somewhere after opening remote access" into a named call.
@test "each step announces itself before it runs" {
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  grep -q "host key" "$LOG"
  grep -q "sshd configuration" "$LOG"
  grep -q "credential" "$LOG"
  grep -q "firewall" "$LOG"
  grep -q "starting sshd" "$LOG"
}

@test "every step that can hang is bounded" {
  # The unit budget is 90 seconds in total, so no single call may be able to
  # spend it. The wifi calls were already capped; these were not.
  grep -q 'timeout [0-9]* ssh-keygen' "$SCRIPT"
  grep -q 'timeout [0-9]* nft -f' "$SCRIPT"
  grep -q 'timeout [0-9]* systemctl' "$SCRIPT"
}

@test "a missing wifi_ssid falls back to wired rather than failing" {
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  [ "$status" -eq 0 ]
  grep -q "relying on a wired connection" "$LOG"
}

@test "the final address is recorded where it can be read without ssh" {
  printf 'enable_ssh=1\nssh_authorized_key=ssh-ed25519 AAAAKEY t@t\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run main
  grep -q "access is up" "$LOG"
}

# --- the config reader must match common.sh ------------------------------

@test "a hash inside a value is part of the value, as in common.sh" {
  printf 'ssh_password=pa#ssword\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run conf_get ssh_password
  [ "$output" = "pa#ssword" ]
}

@test "quotes are stripped but inner spaces kept, as in common.sh" {
  printf 'wifi_ssid="the shop network"\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run conf_get wifi_ssid
  [ "$output" = "the shop network" ]
}

@test "a commented-out key is not read, as in common.sh" {
  printf '#enable_ssh=1\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run conf_get enable_ssh unset
  [ "$output" = "unset" ]
}

@test "the last assignment wins, as in common.sh" {
  printf 'wifi_ssid=first\nwifi_ssid=second\n' > "$CARBIDE_BOOT_DIR/kiosk.conf"
  run conf_get wifi_ssid
  [ "$output" = "second" ]
}

@test "a missing config file yields the default, as in common.sh" {
  run conf_get wifi_country US
  [ "$output" = "US" ]
}
