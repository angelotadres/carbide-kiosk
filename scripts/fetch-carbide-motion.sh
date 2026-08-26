#!/usr/bin/env bash
# Acquire the Carbide Motion Raspberry Pi package.
#
# Carbide Motion is proprietary and is never redistributed by this repository.
# A package placed in CARBIDE_MOTION_DEB_DIR is always preferred; otherwise the
# newest build is downloaded from Carbide 3D's public bucket, mirroring what
# https://carbide3d.com/carbidemotion/pi/ does in the browser.
set -euo pipefail

CARBIDE_MOTION_REPO_URL="${CARBIDE_MOTION_REPO_URL:-https://motion-pi.us-east-1.linodeobjects.com}"
CARBIDE_MOTION_DEB_DIR="${CARBIDE_MOTION_DEB_DIR:-deb}"
CARBIDE_MOTION_BUILD="${CARBIDE_MOTION_BUILD:-}"
CARBIDE_MOTION_ARCH="${CARBIDE_MOTION_ARCH:-armhf}"
# Overridable so the ar/tar fallback can be exercised on a host that has
# dpkg-deb, which is the only place that path has ever been wrong.
CM_DPKG_DEB="${CM_DPKG_DEB:-dpkg-deb}"

die() { printf 'fetch-carbide-motion: %s\n' "$*" >&2; exit 1; }
log() { printf 'fetch-carbide-motion: %s\n' "$*" >&2; }

# Reduce a list of package filenames to the one to install. With a pinned build
# only that exact build is acceptable; otherwise the highest build number wins.
cm_select_build() {
  local pin="$1" names="$2" best="" best_num=-1 name num
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    num="${name#carbidemotion-}"
    num="${num%.deb}"
    case "$num" in ''|*[!0-9]*) continue ;; esac
    if [ -n "$pin" ]; then
      [ "$num" = "$pin" ] && { printf '%s\n' "$name"; return 0; }
      continue
    fi
    if [ "$num" -gt "$best_num" ]; then best_num="$num"; best="$name"; fi
  done <<< "$names"
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

cm_list_local() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name 'carbidemotion-*.deb' -type f -exec basename {} \; 2>/dev/null | sort
}

cm_list_remote() {
  curl -fsS --max-time 60 "$CARBIDE_MOTION_REPO_URL" \
    | tr '<' '\n' \
    | tr '>' '\n' \
    | grep -oE '^carbidemotion-[0-9]+\.deb$' \
    | sort -u
}

# A wrong-architecture package installs cleanly and then fails to launch, so the
# check belongs here rather than at first boot.
cm_deb_field() {
  local deb="$1" field="$2" control
  if command -v "$CM_DPKG_DEB" >/dev/null 2>&1; then
    "$CM_DPKG_DEB" --field "$deb" "$field" 2>/dev/null
    return
  fi
  # dpkg-deb is absent when the build host is not Debian; ar and tar are not.
  # Streamed rather than extracted, so a relative path stays valid.
  control="$(ar p "$deb" control.tar.xz 2>/dev/null | tar -xJO ./control 2>/dev/null)"
  [ -n "$control" ] \
    || control="$(ar p "$deb" control.tar.xz 2>/dev/null | tar -xJO control 2>/dev/null)"
  printf '%s\n' "$control" \
    | awk -v f="$field:" '$1 == f { $1 = ""; sub(/^ /, ""); print }'
}

cm_verify_deb() {
  local deb="$1" arch
  [ -s "$deb" ] || die "package is empty: $deb"
  [ -n "$(cm_deb_field "$deb" Package)" ] || die "not a valid Debian package: $deb"
  arch="$(cm_deb_field "$deb" Architecture)"
  [ "$arch" = "$CARBIDE_MOTION_ARCH" ] \
    || die "package architecture is '$arch', expected '$CARBIDE_MOTION_ARCH': $deb"
}

cm_record_checksum() {
  local deb="$1"
  sha256sum "$deb" | awk '{print $1}' > "$deb.sha256"
  log "sha256 $(cat "$deb.sha256")"
}

main() {
  local dest="${1:-$CARBIDE_MOTION_DEB_DIR}" local_names remote_names chosen
  mkdir -p "$dest"

  local_names="$(cm_list_local "$CARBIDE_MOTION_DEB_DIR")"
  if chosen="$(cm_select_build "$CARBIDE_MOTION_BUILD" "$local_names")"; then
    log "using offline package $CARBIDE_MOTION_DEB_DIR/$chosen"
    cm_verify_deb "$CARBIDE_MOTION_DEB_DIR/$chosen"
    printf '%s\n' "$CARBIDE_MOTION_DEB_DIR/$chosen"
    return 0
  fi

  remote_names="$(cm_list_remote)" \
    || die "no offline package in '$CARBIDE_MOTION_DEB_DIR' and the Carbide 3D bucket is unreachable"
  chosen="$(cm_select_build "$CARBIDE_MOTION_BUILD" "$remote_names")" \
    || die "no package matching build '${CARBIDE_MOTION_BUILD:-newest}' in $CARBIDE_MOTION_REPO_URL"

  log "downloading $chosen from $CARBIDE_MOTION_REPO_URL"
  curl -fsS --max-time 300 -o "$dest/$chosen" "$CARBIDE_MOTION_REPO_URL/$chosen" \
    || die "download failed: $CARBIDE_MOTION_REPO_URL/$chosen"
  cm_verify_deb "$dest/$chosen"
  cm_record_checksum "$dest/$chosen"
  printf '%s\n' "$dest/$chosen"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
