#!/usr/bin/env bash
# Run the real runtime config generator against fixture kiosk.conf files and
# check what it produces. This is the only test that exercises smb.conf and the
# nftables ruleset as Samba and nft actually parse them, so it needs testparm
# and nft on PATH; CI runs it inside a Debian Bookworm container.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/sbin/carbide-kiosk-config"
KIOSK_LIB="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk"

pass=0
fail=0

check() {
  local label="$1"; shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n' "$label" >&2
  fi
}

contains() { grep -qF -- "$2" "$1"; }
absent()   { ! grep -qF -- "$2" "$1"; }

# Render one kiosk.conf and echo the output root. Returns the generator's exit
# status so failure cases can be asserted on.
render() {
  local conf="$1" root="$2"
  mkdir -p "$root"
  CARBIDE_KIOSK_RENDER_ONLY=1 \
  CARBIDE_KIOSK_ROOT="$root" \
  CARBIDE_KIOSK_LIB="${LIB_OVERRIDE-$KIOSK_LIB}" \
  KIOSK_CONF="$conf" \
    bash "$GENERATOR" >/dev/null 2>&1
}

for tool in testparm nft; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'render-config: %s is not installed; run this in the CI container\n' "$tool" >&2
    exit 77
  }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- A minimal, closed configuration ------------------------------------

cat > "$WORK/closed.conf" <<'CONF'
hostname=shopfloor
samba_user=cnc
samba_password=hunter2
samba_share_name=gcode
enable_ssh=0
enable_mdns=0
enable_ping=0
CONF

check "minimal config renders" render "$WORK/closed.conf" "$WORK/closed"
SMB="$WORK/closed/etc/samba/smb.conf"
NFT="$WORK/closed/etc/nftables.conf"
UDEV="$WORK/closed/etc/udev/rules.d/60-carbide-cnc.rules"

check "smb.conf is valid"        testparm -s "$SMB"
check "share is named"           contains "$SMB" "[gcode]"
check "share user is enforced"   contains "$SMB" "valid users = cnc"
check "guest access is refused"  contains "$SMB" "map to guest = never"
check "no guest share"           absent   "$SMB" "guest ok = yes"
check "writes are synced"        contains "$SMB" "sync always = yes"
check "printing is off"          contains "$SMB" "load printers = no"

check "ruleset is valid"         nft -c -f "$NFT"
check "input defaults to drop"   contains "$NFT" "policy drop;"
check "forward defaults to drop" contains "$NFT" "chain forward"
check "samba tcp is open"        contains "$NFT" "tcp dport { 139, 445 } accept"
check "samba udp is open"        contains "$NFT" "udp dport { 137, 138 } accept"
check "ssh stays closed"         absent   "$NFT" "tcp dport 22"
check "mdns stays closed"        absent   "$NFT" "udp dport 5353"
check "ping stays closed"        absent   "$NFT" "echo-request"

check "hostname is applied"      contains "$WORK/closed/etc/hostname" "shopfloor"
check "seeded vendor present"    contains "$UDEV" 'ATTRS{idVendor}=="03eb"'
check "symlink is stable"        contains "$UDEV" 'SYMLINK+="shapeoko"'

# --- Every exception turned on ------------------------------------------

cat > "$WORK/open.conf" <<'CONF'
hostname=shopfloor
samba_user=cnc
samba_password=hunter2
enable_ssh=1
enable_mdns=1
enable_ping=1
usb_vendor_ids=1234 nothex 5678
CONF

check "open config renders" render "$WORK/open.conf" "$WORK/open"
NFT="$WORK/open/etc/nftables.conf"
UDEV="$WORK/open/etc/udev/rules.d/60-carbide-cnc.rules"

check "open ruleset is valid"    nft -c -f "$NFT"
check "ssh opens on request"     contains "$NFT" "tcp dport 22 accept"
check "mdns opens on request"    contains "$NFT" "udp dport 5353 accept"
check "ping opens on request"    contains "$NFT" "echo-request accept"
check "extra vendor accepted"    contains "$UDEV" 'ATTRS{idVendor}=="1234"'
check "second extra accepted"    contains "$UDEV" 'ATTRS{idVendor}=="5678"'
check "malformed vendor dropped" absent   "$UDEV" "nothex"

# --- Configurations that must be refused --------------------------------

cat > "$WORK/nopass.conf" <<'CONF'
samba_user=cnc
samba_password=
CONF
render "$WORK/nopass.conf" "$WORK/nopass" \
  && { fail=$((fail+1)); printf 'FAIL: an empty samba_password was accepted\n' >&2; } \
  || pass=$((pass+1))

cat > "$WORK/nouser.conf" <<'CONF'
samba_password=hunter2
CONF
render "$WORK/nouser.conf" "$WORK/nouser" \
  && { fail=$((fail+1)); printf 'FAIL: missing samba_user was accepted\n' >&2; } \
  || pass=$((pass+1))

# A hostname that would be rejected must fall back, not be passed through.
cat > "$WORK/badhost.conf" <<'CONF'
hostname=not a hostname
samba_user=cnc
samba_password=hunter2
CONF
check "bad hostname renders anyway" render "$WORK/badhost.conf" "$WORK/badhost"
check "bad hostname falls back" contains "$WORK/badhost/etc/hostname" "carbide-kiosk"

# A generator that cannot load its own library must abort before writing
# anything, rather than emitting a firewall with no rules in it.
(
  LIB_OVERRIDE="$WORK/no-such-lib"
  render "$WORK/closed.conf" "$WORK/nolib"
) && { fail=$((fail+1)); printf 'FAIL: a missing library did not abort the run\n' >&2; } \
  || pass=$((pass+1))
check "nothing is written without the library" \
  bash -c '[ ! -e "$1/etc/nftables.conf" ]' _ "$WORK/nolib"

printf 'render-config: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
