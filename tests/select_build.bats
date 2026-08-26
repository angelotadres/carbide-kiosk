#!/usr/bin/env bats
# Build selection is the one piece of fetch logic with a wrong answer that is
# silent: the image builds, boots, and runs the wrong Carbide Motion.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../scripts/fetch-carbide-motion.sh
  source "$REPO_ROOT/scripts/fetch-carbide-motion.sh"
}

@test "newest build wins when nothing is pinned" {
  run cm_select_build "" "$(printf 'carbidemotion-578.deb\ncarbidemotion-654.deb\ncarbidemotion-630.deb')"
  [ "$status" -eq 0 ]
  [ "$output" = "carbidemotion-654.deb" ]
}

@test "build numbers compare numerically, not lexically" {
  run cm_select_build "" "$(printf 'carbidemotion-99.deb\ncarbidemotion-100.deb')"
  [ "$status" -eq 0 ]
  [ "$output" = "carbidemotion-100.deb" ]
}

@test "a pinned build is honoured over a newer one" {
  run cm_select_build "630" "$(printf 'carbidemotion-630.deb\ncarbidemotion-654.deb')"
  [ "$status" -eq 0 ]
  [ "$output" = "carbidemotion-630.deb" ]
}

@test "a pinned build that is absent fails rather than falling back" {
  run cm_select_build "999" "$(printf 'carbidemotion-630.deb\ncarbidemotion-654.deb')"
  [ "$status" -ne 0 ]
}

@test "unparseable names are ignored" {
  run cm_select_build "" "$(printf 'carbidemotion-beta.deb\nREADME.md\n\ncarbidemotion-654.deb')"
  [ "$status" -eq 0 ]
  [ "$output" = "carbidemotion-654.deb" ]
}

@test "an empty candidate list fails" {
  run cm_select_build "" ""
  [ "$status" -ne 0 ]
}

@test "local listing finds only Carbide Motion packages" {
  local dir="$BATS_TEST_TMPDIR/deb"
  mkdir -p "$dir"
  touch "$dir/carbidemotion-654.deb" "$dir/carbidemotion-630.deb" "$dir/other.deb" "$dir/notes.txt"
  run cm_list_local "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'carbidemotion-630.deb\ncarbidemotion-654.deb')" ]
}

@test "local listing of a missing directory is empty, not an error" {
  run cm_list_local "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "offline package takes precedence over the network" {
  local dir="$BATS_TEST_TMPDIR/deb"
  mkdir -p "$dir"
  touch "$dir/carbidemotion-654.deb"
  # Any network call here is a bug: make one fatal.
  cm_list_remote() { return 1; }
  cm_verify_deb() { return 0; }
  CARBIDE_MOTION_DEB_DIR="$dir"
  run main "$dir"
  [ "$status" -eq 0 ]
  # bats folds stderr into $output, and the script logs its choice there.
  [ "${lines[-1]}" = "$dir/carbidemotion-654.deb" ]
}

@test "no offline package and no network is a hard failure" {
  cm_list_remote() { return 1; }
  CARBIDE_MOTION_DEB_DIR="$BATS_TEST_TMPDIR/absent"
  run main "$BATS_TEST_TMPDIR/out"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unreachable"* ]]
}
