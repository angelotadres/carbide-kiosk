#!/usr/bin/env bats
# The status file is written into a network share that everyone on the shop
# LAN with the share password can read. Nothing secret may reach it, including
# secrets that leak in via a log line the status writer merely quotes.

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

@test "the samba password never reaches the status file" {
  run bash -c 'printf "smbd: auth failed for SuperSecret123\n" | redact'
  [[ "$output" != *"SuperSecret123"* ]]
  [[ "$output" == *"[redacted]"* ]]
}

@test "the wifi password never reaches the status file" {
  run bash -c 'printf "wpa: psk=WifiSecret456 rejected\n" | redact'
  [[ "$output" != *"WifiSecret456"* ]]
}

@test "both secrets are stripped from the same text" {
  run bash -c 'printf "a SuperSecret123 b WifiSecret456 c\n" | redact'
  [[ "$output" != *"Secret"* ]]
}

@test "a secret appearing more than once is stripped every time" {
  run bash -c 'printf "SuperSecret123 and again SuperSecret123\n" | redact'
  [[ "$output" != *"SuperSecret123"* ]]
}

@test "ordinary diagnostic text is left intact" {
  run bash -c 'printf "Shapeoko connected on /dev/ttyACM0\n" | redact'
  [[ "$output" == *"/dev/ttyACM0"* ]]
}

@test "an empty password does not blank the whole file" {
  printf 'samba_password=\nwifi_password=\n' > "$KIOSK_CONF"
  run bash -c 'printf "Shapeoko connected\n" | redact'
  [[ "$output" == *"Shapeoko connected"* ]]
  [[ "$output" != *"[redacted]"* ]]
}
