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
  local size special keys text edge accent
  # Border drawn around every key, in pixels. The width arithmetic below
  # depends on it, so it is a variable rather than a literal.
  local border=2

  # -compact drops the function key row. A CNC controller has no use for F1
  # to F12, and the letter keys get the height it would have taken.
  kiosk_enabled keyboard_function_keys 0 || printf '%s\n' "-compact"
  size="$(kiosk_get keyboard_font_size 36)"
  case "$size" in ''|*[!0-9]*) size=36 ;; esac
  special=$(( size * 5 / 9 ))
  [ "$special" -lt 12 ] && special=12

  keys="$(kiosk_get keyboard_key_colour '#46525a')"
  text="$(kiosk_get keyboard_text_colour '#ffffff')"
  # Every gap between keys is painted in the key colour, so the only thing
  # that separates one key from the next is this outline. Painting the gaps
  # instead puts a stripe of a second colour clean across the keyboard
  # between every pair of rows, which is what the banding was.
  edge="$(kiosk_get keyboard_edge_colour '#5d6b77')"
  accent="$(kiosk_get keyboard_accent_colour '#4aa3df')"

  # Why the keys are given explicit widths at all.
  #
  # xvkbd puts each row of keys in its own Athena Form and then widens every
  # row to match the widest one, which is the number row. Athena's Form
  # remembers the width it had before that widening, and when the window is
  # later resized to keyboard_geometry it scales each row's keys by the new
  # width over that remembered width. For every row that was widened the
  # ratio is too large, so its keys are laid out past the right edge of the
  # row's own window, which clips them: Return, Shift and Focus came out
  # sliced in half. It is not a shortage of window width and not the label
  # size, which is why widening the window to 1920 and shrinking the labels
  # both failed to cure it.
  #
  # So give every row the same natural width and nothing is ever widened.
  # Against the number row's 15 keys the other rows fall short by 4, 8, 8, 8
  # and 20 pixels at xvkbd's own key widths, and each key also carries two
  # borders, so a row of n keys needs a further 2 * border * (15 - n). The
  # shortfall is added to the wide keys at the ends of each row, where a few
  # pixels do not show.
  local del=$(( 45 + 4 + 2 * border ))      # q row, 14 keys
  local ctrl=$(( 60 + 4 + 2 * border ))     # a row, 13 keys
  local ret=$(( 60 + 4 + 2 * border ))
  local lshift=$(( 75 + 4 + 2 * border ))   # z row, 13 keys
  local rshift=$(( 40 + 4 + 2 * border ))
  local space=$(( 80 + 8 + 6 * border ))    # space bar row, 12 keys
  local backspace=$(( 75 + 20 + 4 * border ))  # function key row, 13 keys

  # Keys are 60 pixels tall in the layout xvkbd builds before the window is
  # resized to keyboard_geometry. At xvkbd's own 30 the window has to stretch
  # more than twice as far vertically as it does horizontally, which blows the
  # gaps between rows up into bands far wider than the gaps between keys; at
  # 60 the two come out within a couple of pixels of each other.
  printf '%s\n' \
    "-xrm" "XVkbd*letterFont: -*-helvetica-bold-r-normal--${size}-*-*-*-*-*-iso8859-1" \
    "-xrm" "XVkbd*specialFont: -*-helvetica-bold-r-normal--${special}-*-*-*-*-*-iso8859-1" \
    "-xrm" "XVkbd*generalFont: -*-helvetica-bold-r-normal--${special}-*-*-*-*-*-iso8859-1" \
    "-xrm" "XVkbd*Form.defaultDistance: 4" \
    "-xrm" "XVkbd*Delete.width: $del" \
    "-xrm" "XVkbd*Control_L.width: $ctrl" \
    "-xrm" "XVkbd*Return.width: $ret" \
    "-xrm" "XVkbd*Shift_L.width: $lshift" \
    "-xrm" "XVkbd*Shift_R.width: $rshift" \
    "-xrm" "XVkbd*space.width: $space" \
    "-xrm" "XVkbd*BackSpace.width: $backspace" \
    "-xrm" "XVkbd*Command.height: 60" \
    "-xrm" "XVkbd*Repeater.height: 60" \
    "-xrm" "XVkbd*MainMenu.height: 60" \
    "-xrm" "XVkbd*Command.borderWidth: $border" \
    "-xrm" "XVkbd*Repeater.borderWidth: $border" \
    "-xrm" "XVkbd*MenuButton.borderWidth: $border" \
    "-xrm" "XVkbd*BorderColor: $edge" \
    "-xrm" "XVkbd*Background: $keys" \
    "-xrm" "XVkbd*specialBackground: $keys" \
    "-xrm" "XVkbd*Foreground: $text" \
    "-xrm" "XVkbd*highlightBackground: $accent" \
    "-xrm" "XVkbd*highlightForeground: #10161a" \
    "-xrm" "XVkbd*focusBackground: $accent"
}
