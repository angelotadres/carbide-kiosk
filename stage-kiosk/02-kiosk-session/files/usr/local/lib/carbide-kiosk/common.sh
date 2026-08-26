# Shared helpers for the Carbide Motion Kiosk runtime scripts.
# Sourced, never executed.

KIOSK_CONF="${KIOSK_CONF:-/boot/firmware/kiosk.conf}"
KIOSK_DATA="${KIOSK_DATA:-/data}"

kiosk_log() { printf 'carbide-kiosk: %s\n' "$*" >&2; }
kiosk_die() { kiosk_log "$*"; exit 1; }

# Read one key from kiosk.conf, falling back to a default.
#
# Values are taken verbatim to the end of the line, so a '#' inside a password
# needs no escaping. Comments therefore only work on lines of their own.
kiosk_get() {
  local key="$1" default="${2-}" val
  if [ -r "$KIOSK_CONF" ]; then
    val="$(sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)\$/\\1/p" "$KIOSK_CONF" | tail -n 1)"
    val="${val%"${val##*[![:space:]]}"}"
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
  fi
  if [ -n "${val:-}" ]; then printf '%s\n' "$val"; else printf '%s\n' "$default"; fi
}

# Read a 0/1 flag. Anything other than an explicit truthy value is off, so a
# typo closes a port rather than opening one.
kiosk_enabled() {
  case "$(kiosk_get "$1" "${2:-0}")" in
    1|yes|true|on|YES|TRUE|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Reject anything that is not a plausible hostname before it reaches hostnamectl.
kiosk_valid_hostname() {
  printf '%s' "$1" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
}

# Four-digit hex, as lsusb prints them.
kiosk_valid_usb_id() {
  printf '%s' "$1" | grep -qE '^[0-9a-fA-F]{4}$'
}
