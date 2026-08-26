#!/usr/bin/env bats
# kiosk.conf is the entire administration surface of this image, edited by hand
# on a card reader. Every wrong reading here becomes a machine that will not
# come up, so the parser is tested harder than anything else in the repo.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk/common.sh
  source "$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk/common.sh"
  KIOSK_CONF="$BATS_TEST_TMPDIR/kiosk.conf"
}

@test "reads a plain value" {
  printf 'hostname=shopfloor\n' > "$KIOSK_CONF"
  run kiosk_get hostname
  [ "$output" = "shopfloor" ]
}

@test "falls back to the default when the key is absent" {
  printf 'hostname=shopfloor\n' > "$KIOSK_CONF"
  run kiosk_get samba_share_name gcode
  [ "$output" = "gcode" ]
}

@test "falls back to the default when the value is empty" {
  printf 'wifi_ssid=\n' > "$KIOSK_CONF"
  run kiosk_get wifi_ssid fallback
  [ "$output" = "fallback" ]
}

@test "tolerates surrounding whitespace" {
  printf '  hostname   =   shopfloor   \n' > "$KIOSK_CONF"
  run kiosk_get hostname
  [ "$output" = "shopfloor" ]
}

@test "strips matching quotes but keeps inner spaces" {
  printf 'samba_password="two words"\n' > "$KIOSK_CONF"
  run kiosk_get samba_password
  [ "$output" = "two words" ]
}

@test "a hash inside a value is part of the password" {
  printf 'samba_password=abc#123\n' > "$KIOSK_CONF"
  run kiosk_get samba_password
  [ "$output" = "abc#123" ]
}

@test "a commented-out key is not read" {
  printf '#hostname=commented\n' > "$KIOSK_CONF"
  run kiosk_get hostname carbide-kiosk
  [ "$output" = "carbide-kiosk" ]
}

@test "the last assignment wins" {
  printf 'hostname=first\nhostname=second\n' > "$KIOSK_CONF"
  run kiosk_get hostname
  [ "$output" = "second" ]
}

@test "a key is not matched as a suffix of a longer key" {
  printf 'samba_password=secret\n' > "$KIOSK_CONF"
  run kiosk_get password notfound
  [ "$output" = "notfound" ]
}

@test "a missing config file yields the default" {
  KIOSK_CONF="$BATS_TEST_TMPDIR/absent.conf"
  run kiosk_get hostname carbide-kiosk
  [ "$output" = "carbide-kiosk" ]
}

@test "flags are off unless explicitly truthy" {
  printf 'enable_ssh=1\nenable_mdns=yes\nenable_ping=0\n' > "$KIOSK_CONF"
  kiosk_enabled enable_ssh
  kiosk_enabled enable_mdns
  ! kiosk_enabled enable_ping
}

@test "a typoed flag value closes the port rather than opening it" {
  printf 'enable_ssh=ture\n' > "$KIOSK_CONF"
  ! kiosk_enabled enable_ssh
}

@test "an absent flag is off" {
  printf 'hostname=shopfloor\n' > "$KIOSK_CONF"
  ! kiosk_enabled enable_ssh
}

@test "hostname validation rejects what hostnamectl would" {
  kiosk_valid_hostname "carbide-kiosk"
  kiosk_valid_hostname "a"
  ! kiosk_valid_hostname "-leading"
  ! kiosk_valid_hostname "trailing-"
  ! kiosk_valid_hostname "has space"
  ! kiosk_valid_hostname "has.dot"
  ! kiosk_valid_hostname ""
  ! kiosk_valid_hostname 'rm -rf /'
}

@test "usb id validation accepts only four hex digits" {
  kiosk_valid_usb_id "03eb"
  kiosk_valid_usb_id "1A86"
  ! kiosk_valid_usb_id "3eb"
  ! kiosk_valid_usb_id "03ebb"
  ! kiosk_valid_usb_id "03e_"
  ! kiosk_valid_usb_id ""
}
