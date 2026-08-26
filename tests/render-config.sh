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
not_in_tree() { ! grep -rqF -- "$2" "$1" 2>/dev/null; }
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
check "ssh is closed by default" absent   "$NFT" "dport 22"
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
# enable_ssh alone must not open the port: an open port onto an account
# nobody can authenticate against is worse than no port at all.
check "enable_ssh without a credential stays shut" absent "$NFT" "dport 22"
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
  test ! -e "$WORK/nolib/etc/nftables.conf"

# --- ssh, which only opens with a credential ----------------------------

cat > "$WORK/sshkey.conf" <<'CONF'
samba_user=cnc
samba_password=hunter2
enable_ssh=1
ssh_authorized_key=ssh-ed25519 AAAATESTKEY carbide@test
CONF
check "key config renders" render "$WORK/sshkey.conf" "$WORK/sshkey"
NFT="$WORK/sshkey/etc/nftables.conf"
SSHD="$WORK/sshkey/etc/ssh/sshd_config.d/carbide-kiosk.conf"
check "ssh ruleset is valid"     nft -c -f "$NFT"
check "port 22 opens with a key" contains "$NFT" "tcp dport 22 ct state new"
check "passwords are refused"    contains "$SSHD" "PasswordAuthentication no"
check "root cannot log in"       contains "$SSHD" "PermitRootLogin no"
check "only kiosk may log in"    contains "$SSHD" "AllowUsers kiosk"
check "host key is persistent"   contains "$SSHD" "HostKey /data/ssh/"
check "brute force is limited"   contains "$SSHD" "MaxAuthTries 3"
check "no empty passwords"       contains "$SSHD" "PermitEmptyPasswords no"
check "no port forwarding"       contains "$SSHD" "AllowTcpForwarding no"

cat > "$WORK/sshpw.conf" <<'CONF'
samba_user=cnc
samba_password=hunter2
enable_ssh=1
ssh_password=troubleshooting
CONF
check "password config renders"  render "$WORK/sshpw.conf" "$WORK/sshpw"
check "port 22 opens with a password" contains "$WORK/sshpw/etc/nftables.conf" "tcp dport 22 ct state new"
check "password login allowed"   contains "$WORK/sshpw/etc/ssh/sshd_config.d/carbide-kiosk.conf" "PasswordAuthentication yes"
# The ssh password is applied with chpasswd, never written to a file. It must
# not turn up anywhere in the generated configuration.
check "ssh password is written nowhere" not_in_tree "$WORK/sshpw" "troubleshooting"

printf 'render-config: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
