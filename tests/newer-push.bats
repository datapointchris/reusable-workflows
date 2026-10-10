#!/usr/bin/env bats
# Each workflow's `tip` step, against a bare repository as origin.
#
# The repository has two commits. FIRST is an earlier push, and SECOND is the
# one after it, which is where origin's main sits. Each test names the commit
# the run was started for.

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
  git -C "$REPO" push --quiet origin main
  cd "$REPO" || return 1

  export GITHUB_REF=refs/heads/main
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github-output"
  touch "$GITHUB_OUTPUT"
}

# Usage: go_tip <run's commit>
go_tip() {
  GITHUB_SHA=$1 run_step go-semantic-release.yml semver tip
}

# Usage: python_tip <run's commit>
python_tip() {
  GITHUB_SHA=$1 run_step python-semantic-release.yml release tip
}

# Usage: step_condition <workflow file> <job> <step id>
step_condition() {
  JOB="$2" ID="$3" yq '.jobs[strenv(JOB)].steps[] | select(.id == strenv(ID)) | .if' \
    "$WORKFLOWS/$1"
}

assert_released_here() {
  assert_success
  assert_output ""
  run cat "$GITHUB_OUTPUT"
  assert_output ""
}

# Usage: assert_superseded [origin's main]
assert_superseded() {
  assert_success
  assert_output "::notice::refs/heads/main is at ${1:-$SECOND}, past ${FIRST}, so the run for a later push releases these commits"
  run cat "$GITHUB_OUTPUT"
  assert_output "superseded=true"
}

@test "go: a run at the branch tip releases" {
  run go_tip "$SECOND"
  assert_released_here
}

@test "go: a run the branch has moved past leaves the release to the newer push" {
  run go_tip "$FIRST"
  assert_superseded
}

@test "go: a re-run finishing its own tag goes on after the branch moved" {
  lightweight_tag "$REPO" v0.1.0 "$FIRST"
  run go_tip "$FIRST"
  assert_released_here
}

@test "go: a tag naming no version does not hold the run" {
  lightweight_tag "$REPO" v1 "$FIRST"
  run go_tip "$FIRST"
  assert_superseded
}

@test "go: a branch origin does not have fails the run" {
  GITHUB_REF=refs/heads/gone run go_tip "$SECOND"
  assert_failure
  assert_output "::error::origin has no refs/heads/gone to release from"
}

@test "go: the release and finish steps skip a superseded run" {
  run step_condition go-semantic-release.yml semver semrel
  assert_output "\${{ steps.tip.outputs.superseded != 'true' }}"
  run step_condition go-semantic-release.yml semver finish
  assert_output --partial "steps.tip.outputs.superseded != 'true' &&"
}

@test "python: a run at the branch tip releases" {
  run python_tip "$SECOND"
  assert_released_here
}

@test "python: a run the branch has moved past leaves the release to the newer push" {
  run python_tip "$FIRST"
  assert_superseded
}

@test "python: a re-run finishing the tag on its version commit goes on" {
  # The failed attempt committed the version onto FIRST and tagged that.
  annotated_tag "$REPO" v0.1.0 "$SECOND"
  run python_tip "$FIRST"
  assert_released_here
}

@test "python: a re-run finishing a tag at its own commit goes on" {
  annotated_tag "$REPO" v0.1.0 "$FIRST"
  run python_tip "$FIRST"
  assert_released_here
}

@test "python: the newer push's release does not hold the run" {
  # SECOND is the newer push, and its run committed the version on top of it.
  version_commit=$(commit "$REPO" "chore(release): 0.1.0")
  annotated_tag "$REPO" v0.1.0 "$version_commit"
  git push --quiet origin main
  run python_tip "$FIRST"
  assert_superseded "$version_commit"
}

@test "python: a branch origin does not have fails the run" {
  GITHUB_REF=refs/heads/gone run python_tip "$SECOND"
  assert_failure
  assert_output "::error::origin has no refs/heads/gone to release from"
}

@test "python: the release and finish steps skip a superseded run" {
  run step_condition python-semantic-release.yml release release
  assert_output "\${{ steps.tip.outputs.superseded != 'true' }}"
  run step_condition python-semantic-release.yml release finish
  assert_output --partial "steps.tip.outputs.superseded != 'true' &&"
}
