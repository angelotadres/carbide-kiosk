# shellcheck shell=bash
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

# The on-screen keyboard's appearance, assembled from kiosk.conf. Shared
# because both the session and the show/hide button need to launch it
# identically; a keyboard that changes colour when it is restarted looks
# broken.
#
# xvkbd draws with Athena widgets, which ignore QT_SCALE_FACTOR, so its type
# has to be sized here. letterFont and specialFont override the generic Font
# resource, which is why setting Font alone does nothing.
kiosk_keyboard_args() {
  local size special keys text gap accent

  # -compact drops the function key row. That row carries a double-width
  # "Backspace Delete" key which forces the whole layout wider than a 1920
  # pixel panel at a readable label size, clipping Return, Shift and Focus off
  # the right edge. A CNC controller has no use for F1 to F12.
  kiosk_enabled keyboard_function_keys 0 || printf '%s\n' "-compact"
  size="$(kiosk_get keyboard_font_size 36)"
  case "$size" in ''|*[!0-9]*) size=36 ;; esac
  special=$(( size * 5 / 9 ))
  [ "$special" -lt 12 ] && special=12

  keys="$(kiosk_get keyboard_key_colour '#46525a')"
  text="$(kiosk_get keyboard_text_colour '#ffffff')"
  # Lighter than the keys, not darker: a darker gap reads as a black band
  # across the keyboard, and rows of touching dark lines make the straight
  # edges appear to curve.
  gap="$(kiosk_get keyboard_gap_colour '#566370')"
  accent="$(kiosk_get keyboard_accent_colour '#4aa3df')"

  printf '%s\n' \
    "-xrm" "XVkbd*letterFont: -*-helvetica-bold-r-normal--${size}-*-*-*-*-*-iso8859-1" \
    "-xrm" "XVkbd*specialFont: -*-helvetica-bold-r-normal--${special}-*-*-*-*-*-iso8859-1" \
    "-xrm" "XVkbd*generalFont: -*-helvetica-bold-r-normal--${special}-*-*-*-*-*-iso8859-1" \
    "-xrm" "XVkbd*Form.defaultDistance: 4" \
    "-xrm" "XVkbd*Key.borderWidth: 0" \
    "-xrm" "XVkbd*Key.shadowWidth: 0" \
    "-xrm" "XVkbd*Background: $keys" \
    "-xrm" "XVkbd*specialBackground: $keys" \
    "-xrm" "XVkbd*Foreground: $text" \
    "-xrm" "XVkbd*form.background: $gap" \
    "-xrm" "XVkbd*highlightBackground: $accent" \
    "-xrm" "XVkbd*highlightForeground: #10161a" \
    "-xrm" "XVkbd*focusBackground: $accent"
}
