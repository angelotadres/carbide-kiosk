#!/usr/bin/env bats
# Whether the read-only root is real. On 2026-08-30 a clean flash reported the
# overlay as done and came up writable: raspi-config's enable_overlayfs fetches
# the overlayroot package from the network at the moment it is asked, the
# machine had no network because the access unit had already died, apt failed,
# and raspi-config exited 0 anyway. The guard that should have caught it only
# checked that an initramfs file existed - and every image ships one, so it
# passed on the file the build wrote.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CARBIDE_KIOSK_LIB="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk"
  source "$REPO_ROOT/stage-kiosk/07-firstboot/files/carbide-firstboot"

  STUBS="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS"
  PATH="$STUBS:$PATH"
}

# dpkg-query reporting whatever a test needs it to for each package.
stub_dpkg() {
  cat > "$STUBS/dpkg-query" <<STUB
#!/bin/sh
for arg in "\$@"; do
  case "\$arg" in
    overlayroot) printf '%s' '$1'; exit 0 ;;
    cryptsetup)  printf '%s' '$2'; exit 0 ;;
  esac
done
exit 1
STUB
  chmod 755 "$STUBS/dpkg-query"
}

# lsinitramfs listing a fixed set of paths, so a test can include or omit the
# overlay hook without building a real initramfs.
stub_lsinitramfs() {
  cat > "$STUBS/lsinitramfs" <<STUB
#!/bin/sh
printf '%s\n' $1
exit 0
STUB
  chmod 755 "$STUBS/lsinitramfs"
}

# --- the packages have to be installed, not merely asked for ---------------

@test "both packages installed is the only passing case" {
  stub_dpkg 'install ok installed' 'install ok installed'
  run overlay_packages_installed
  [ "$status" -eq 0 ]
}

@test "a missing overlayroot is refused" {
  stub_dpkg 'unknown ok not-installed' 'install ok installed'
  run overlay_packages_installed
  [ "$status" -ne 0 ]
}

@test "a missing cryptsetup is refused" {
  stub_dpkg 'install ok installed' 'unknown ok not-installed'
  run overlay_packages_installed
  [ "$status" -ne 0 ]
}

# A failed apt leaves the package unpacked but not configured. That is the
# exact state the 2026-08-30 boot would have been in had the download half
# succeeded, and it must not count as installed.
@test "a half-configured package is not installed" {
  stub_dpkg 'install ok half-configured' 'install ok installed'
  run overlay_packages_installed
  [ "$status" -ne 0 ]
}

@test "no dpkg-query at all is refused rather than assumed" {
  rm -f "$STUBS/dpkg-query"
  run overlay_packages_installed
  [ "$status" -ne 0 ]
}

# --- the hook has to be inside the initramfs -------------------------------

@test "an initramfs carrying the overlay hook passes" {
  stub_lsinitramfs 'bin/sh scripts/init-bottom/overlayroot etc/fstab'
  run overlay_hook_present "$BATS_TEST_TMPDIR/initramfs8"
  [ "$status" -eq 0 ]
}

# The regression. The image's own initramfs is a real, loadable file with no
# overlay hook in it, and the old check - that the file exists - passed on it.
@test "the initramfs the image shipped with does not pass" {
  stub_lsinitramfs 'bin/sh scripts/init-bottom/udev etc/fstab'
  run overlay_hook_present "$BATS_TEST_TMPDIR/initramfs8"
  [ "$status" -ne 0 ]
}

@test "an unreadable initramfs does not pass" {
  cat > "$STUBS/lsinitramfs" <<'STUB'
#!/bin/sh
echo "lsinitramfs: not an initramfs" >&2
exit 1
STUB
  chmod 755 "$STUBS/lsinitramfs"
  run overlay_hook_present "$BATS_TEST_TMPDIR/nonsense"
  [ "$status" -ne 0 ]
}
