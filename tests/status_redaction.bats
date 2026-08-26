#!/usr/bin/env bats
# The status file is written into a network share that anyone with the share
# password can read. Nothing secret may reach it, including a secret that
# leaks in via a log line the status writer merely quotes.
#
# redact is a shell function, so it must be called in this shell. Invoking it
# through `bash -c` would silently find no such command, leave the output
# empty, and pass every "must not contain the secret" assertion vacuously.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CARBIDE_KIOSK_LIB="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk"
  # shellcheck source=../stage-kiosk/08-status/files/carbide-kiosk-status
  source "$REPO_ROOT/stage-kiosk/08-status/files/carbide-kiosk-status"
  KIOSK_CONF="$BATS_TEST_TMPDIR/kiosk.conf"
  cat > "$KIOSK_CONF" <<CONF
samba_user=cnc
samba_password=SuperSecret123
wifi_password=WifiSecret456
samba_share_name=gcode
CONF
}

# Every case asserts the text survived, so an empty result can never be
# mistaken for a successful redaction.
scrub() {
  local out
  out="$(printf '%s\n' "$1" | redact)"
  [ -n "$out" ]
  printf '%s' "$out"
}

@test "the samba password never reaches the status file" {
  local out
  out="$(scrub 'smbd: auth failed for SuperSecret123')"
  [[ "$out" != *"SuperSecret123"* ]]
  [[ "$out" == *"[redacted]"* ]]
  [[ "$out" == *"auth failed for"* ]]
}

@test "the wifi password never reaches the status file" {
  local out
  out="$(scrub 'wpa: psk=WifiSecret456 rejected')"
  [[ "$out" != *"WifiSecret456"* ]]
  [[ "$out" == *"rejected"* ]]
}

@test "both secrets are stripped from the same text" {
  local out
  out="$(scrub 'a SuperSecret123 b WifiSecret456 c')"
  [[ "$out" != *"Secret"* ]]
  [[ "$out" == *"a "* ]]
  [[ "$out" == *" c"* ]]
}

@test "a secret appearing more than once is stripped every time" {
  local out
  out="$(scrub 'SuperSecret123 and again SuperSecret123')"
  [[ "$out" != *"SuperSecret123"* ]]
  [[ "$out" == *"and again"* ]]
}

@test "ordinary diagnostic text is left intact" {
  local out
  out="$(scrub 'Shapeoko connected on /dev/ttyACM0')"
  [ "$out" = "Shapeoko connected on /dev/ttyACM0" ]
}

@test "an empty password does not blank the whole file" {
  printf 'samba_password=\nwifi_password=\n' > "$KIOSK_CONF"
  local out
  out="$(scrub 'Shapeoko connected')"
  [ "$out" = "Shapeoko connected" ]
}

@test "redact is actually defined, not silently absent" {
  declare -F redact
}

# The screensaver faces a workshop and ends up in photographs. It must report
# that the machine is on a network without naming which one: an SSID beside a
# location is worth something to an attacker, "wifi" is worth nothing.

@test "the screensaver reports connection type, never the network name" {
  source "$REPO_ROOT/stage-kiosk/08-status/files/carbide-kiosk-saver-text"
  nmcli() { printf 'yes:VerySpecificHomeNetwork\n'; }
  run network
  [ "$output" = "wifi" ]
  [[ "$output" != *"VerySpecificHomeNetwork"* ]]
}

@test "a wired machine says wired" {
  source "$REPO_ROOT/stage-kiosk/08-status/files/carbide-kiosk-saver-text"
  nmcli() {
    case "$*" in
      *"dev wifi"*) return 0 ;;
      *) printf 'ethernet:connected\n' ;;
    esac
  }
  run network
  [ "$output" = "wired" ]
}

@test "an offline machine says so rather than guessing" {
  source "$REPO_ROOT/stage-kiosk/08-status/files/carbide-kiosk-saver-text"
  nmcli() { return 0; }
  run network
  [ "$output" = "not connected" ]
}
