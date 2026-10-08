#!/usr/bin/env bats
# release.yml's `move` step: the major tag follows the highest release in its
# major, so a re-run that finishes an older release never takes callers back.
#
# The repository has two commits, FIRST and SECOND, and a bare repository as
# its origin. Each test checks out the release commit the job would.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load helpers
  clear_git_environment

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init --quiet --bare "$ORIGIN"
  git init --quiet --initial-branch=main "$REPO"
  git -C "$REPO" remote add origin "$ORIGIN"
  FIRST=$(commit "$REPO" "feat: first")
  SECOND=$(commit "$REPO" "fix: second")
  cd "$REPO" || return 1
}

# Usage: move_major <version output> <commit the job checked out>
move_major() {
  git checkout --quiet --detach "$2"
  VERSION=$1 run_step release.yml major-tag move
}

origin_major() {
  git -C "$ORIGIN" rev-parse --verify --quiet refs/tags/v1
}

@test "a release moves its major tag onto itself" {
  lightweight_tag "$REPO" v1.0.0 "$FIRST"
  lightweight_tag "$REPO" v1.0.1 "$SECOND"
  lightweight_tag "$REPO" v1 "$FIRST"
  git push --quiet origin refs/tags/v1

  run move_major 1.0.1 "$SECOND"
  assert_success

  run origin_major
  assert_output "$SECOND"
}

@test "a re-run of an older release leaves the major tag on the newer one" {
  lightweight_tag "$REPO" v1.0.1 "$FIRST"
  lightweight_tag "$REPO" v1.0.2 "$SECOND"
  lightweight_tag "$REPO" v1 "$SECOND"
  git push --quiet origin refs/tags/v1

  run move_major 1.0.1 "$FIRST"
  assert_success
  assert_output --partial "v1.0.1 is older than v1.0.2, so v1 stays where it is"

  run origin_major
  assert_output "$SECOND"
}

@test "a newer major does not hold back the older major's tag" {
  lightweight_tag "$REPO" v1.0.3 "$FIRST"
  lightweight_tag "$REPO" v2.0.0 "$SECOND"

  run move_major 1.0.3 "$FIRST"
  assert_success

  run origin_major
  assert_output "$FIRST"
}
