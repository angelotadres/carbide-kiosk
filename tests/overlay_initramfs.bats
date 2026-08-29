#!/usr/bin/env bats
# The overlay is only safe to boot into if the firmware will really load an
# initramfs. Looking for an explicit "initramfs" line in config.txt missed the
# auto_initramfs=1 mechanism this base image actually uses, so a correctly
# installed overlay was reverted and the machine came up writable.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CARBIDE_KIOSK_LIB="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk"
  source "$REPO_ROOT/stage-kiosk/07-firstboot/files/carbide-firstboot"
  BOOT="$BATS_TEST_TMPDIR/firmware"
  mkdir -p "$BOOT"
}

@test "auto_initramfs names the file matching the running kernel" {
  printf 'auto_initramfs=1\n' > "$BOOT/config.txt"
  : > "$BOOT/initramfs8"
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v8'
  [ "$output" = "initramfs8" ]
}

@test "the v7l kernel is not mistaken for v7" {
  printf 'auto_initramfs=1\n' > "$BOOT/config.txt"
  : > "$BOOT/initramfs7l"
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v7l'
  [ "$output" = "initramfs7l" ]
}

@test "a v6 kernel takes the unsuffixed name" {
  printf 'auto_initramfs=1\n' > "$BOOT/config.txt"
  : > "$BOOT/initramfs"
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v6'
  [ "$output" = "initramfs" ]
}

@test "an explicit initramfs line takes precedence" {
  printf 'auto_initramfs=1\ninitramfs initramfs7 followkernel\n' > "$BOOT/config.txt"
  : > "$BOOT/initramfs7"
  : > "$BOOT/initramfs8"
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v8'
  [ "$output" = "initramfs7" ]
}

@test "auto_initramfs with no matching file yields nothing" {
  printf 'auto_initramfs=1\n' > "$BOOT/config.txt"
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v8'
  [ "$status" -ne 127 ]
  [ -z "$output" ]
}

@test "an explicit line naming a missing file yields nothing" {
  printf 'initramfs initramfs8 followkernel\n' > "$BOOT/config.txt"
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v8'
  [ "$status" -ne 127 ]
  [ -z "$output" ]
}

@test "neither mechanism configured yields nothing" {
  printf 'dtparam=audio=on\n' > "$BOOT/config.txt"
  : > "$BOOT/initramfs8"
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v8'
  [ "$status" -ne 127 ]
  [ -z "$output" ]
}

@test "a missing config.txt yields nothing rather than failing" {
  run overlay_initramfs "$BOOT" '6.12.96+rpt-rpi-v8'
  [ "$status" -ne 127 ]
  [ -z "$output" ]
}
