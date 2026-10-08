#!/usr/bin/env bats
# The `finish` step of each workflow: on a run that cut no version, it creates
# the GitHub release for a tag an earlier attempt of this run pushed, and leaves
# every other tag alone. The release is Latest only when no newer full release
# exists.
#
# The repository has two commits. FIRST is an earlier push, and SECOND is the
# one after it. Each test names the commit the run was started for.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load helpers
  clear_git_environment
  start_api_stub

  REPO="$BATS_TEST_TMPDIR/repo"
  git init --quiet --initial-branch=main "$REPO"
  FIRST=$(commit "$REPO" "feat: first")
  SECOND=$(commit "$REPO" "fix: second")
  cd "$REPO" || return 1

  export GITHUB_REPOSITORY=owner/demo
  export GH_TOKEN=test-token
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github-output"
  touch "$GITHUB_OUTPUT"
}

teardown() {
  stop_api_stub
}

# Usage: python_finish <run's commit> <tag output> <version output> <is_prerelease output>
python_finish() {
  GITHUB_SHA=$1 TAG=$2 VERSION=$3 PRERELEASE=$4 run_step python-semantic-release.yml release finish
}

# Usage: go_finish <run's commit>
go_finish() {
  GITHUB_SHA=$1 run_step go-semantic-release.yml semver finish
}

created() {
  jq -cS . "$API_STATE/created"
}

@test "python: a re-run creates the release for the tag its failed attempt pushed" {
  # The failed attempt committed the version onto FIRST and tagged that.
  annotated_tag "$REPO" v0.1.0 "$SECOND"
  run python_finish "$FIRST" v0.1.0 0.1.0 false
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"true","name":"v0.1.0","prerelease":false,"tag_name":"v0.1.0"}'
  run cat "$GITHUB_OUTPUT"
  assert_output "released=true"
  run cat "$API_STATE/requests"
  assert_output "GET /repos/owner/demo/releases/tags/v0.1.0 Bearer test-token
POST /repos/owner/demo/releases Bearer test-token"
}

@test "python: a re-run after a newer release leaves the newer one Latest" {
  annotated_tag "$REPO" v0.1.0 "$SECOND"
  annotated_tag "$REPO" v0.2.0 "$(commit "$REPO" "feat: third")"
  run python_finish "$FIRST" v0.1.0 0.1.0 false
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"false","name":"v0.1.0","prerelease":false,"tag_name":"v0.1.0"}'
}

@test "python: only a full release of the same tag format outranks the tag" {
  annotated_tag "$REPO" pkg-v0.1.0 "$SECOND"
  annotated_tag "$REPO" app-v9.0.0 "$SECOND"
  annotated_tag "$REPO" pkg-v0.2.0-rc.1 "$(commit "$REPO" "feat: third")"
  run python_finish "$FIRST" pkg-v0.1.0 0.1.0 false
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"true","name":"pkg-v0.1.0","prerelease":false,"tag_name":"pkg-v0.1.0"}'
}

@test "python: a prerelease tag on the run's own commit is created as a prerelease" {
  # With no version file to change, there is no version commit, and the tag
  # sits on the commit the run was started for.
  annotated_tag "$REPO" v1.0.0-rc.1 "$SECOND"
  run python_finish "$SECOND" v1.0.0-rc.1 1.0.0-rc.1 true
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"false","name":"v1.0.0-rc.1","prerelease":true,"tag_name":"v1.0.0-rc.1"}'
}

@test "python: an older release's tag behind the run's commit is left alone, unasked" {
  annotated_tag "$REPO" v0.1.0 "$FIRST"
  run python_finish "$SECOND" v0.1.0 0.1.0 false
  assert_success

  assert [ ! -e "$API_STATE/requests" ]
  assert [ ! -s "$GITHUB_OUTPUT" ]
}

@test "python: a tag whose release exists is left alone" {
  annotated_tag "$REPO" v0.1.0 "$SECOND"
  touch "$API_STATE/releases/v0.1.0"
  run python_finish "$FIRST" v0.1.0 0.1.0 false
  assert_success

  assert [ ! -e "$API_STATE/created" ]
  assert [ ! -s "$GITHUB_OUTPUT" ]
}

@test "python: a lookup GitHub cannot answer fails the step and creates nothing" {
  annotated_tag "$REPO" v0.1.0 "$SECOND"
  echo 500 >"$API_STATE/lookup-status"
  run python_finish "$FIRST" v0.1.0 0.1.0 false
  assert_failure
  assert_output --partial "looking up the release for v0.1.0 returned HTTP 500"

  assert [ ! -e "$API_STATE/created" ]
}

@test "go: a re-run creates the release for the tag its failed attempt pushed" {
  lightweight_tag "$REPO" v1.1.0 "$FIRST"
  touch "$API_STATE/releases/v1.1.0"
  lightweight_tag "$REPO" v1.2.0 "$SECOND"
  run go_finish "$SECOND"
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"true","name":"v1.2.0","prerelease":false,"tag_name":"v1.2.0"}'
  run cat "$GITHUB_OUTPUT"
  assert_output "version=1.2.0"
}

@test "go: a re-run after a newer release leaves the newer one Latest" {
  lightweight_tag "$REPO" v1.1.0 "$SECOND"
  lightweight_tag "$REPO" v1.2.0 "$(commit "$REPO" "feat: third")"
  run go_finish "$SECOND"
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"false","name":"v1.1.0","prerelease":false,"tag_name":"v1.1.0"}'
}

@test "go: a newer prerelease does not keep a release from Latest" {
  lightweight_tag "$REPO" v1.2.0 "$SECOND"
  lightweight_tag "$REPO" v1.3.0-rc.1 "$(commit "$REPO" "feat: third")"
  run go_finish "$SECOND"
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"true","name":"v1.2.0","prerelease":false,"tag_name":"v1.2.0"}'
}

@test "go: a prerelease tag is created as a prerelease" {
  lightweight_tag "$REPO" v2.0.0-rc.1 "$SECOND"
  run go_finish "$SECOND"
  assert_success

  run created
  assert_output '{"generate_release_notes":true,"make_latest":"false","name":"v2.0.0-rc.1","prerelease":true,"tag_name":"v2.0.0-rc.1"}'
  run cat "$GITHUB_OUTPUT"
  assert_output "version=2.0.0-rc.1"
}

@test "go: a major tag on the run's commit is no release tag, and nothing is asked" {
  # release.yml moves v1 onto each release commit, and the release's own tag
  # sits behind the commit this run was started for.
  lightweight_tag "$REPO" v1.1.0 "$FIRST"
  lightweight_tag "$REPO" v1 "$SECOND"
  run go_finish "$SECOND"
  assert_success

  assert [ ! -e "$API_STATE/requests" ]
  assert [ ! -s "$GITHUB_OUTPUT" ]
}

@test "go: a tag whose release exists is left alone" {
  lightweight_tag "$REPO" v1.2.0 "$SECOND"
  touch "$API_STATE/releases/v1.2.0"
  run go_finish "$SECOND"
  assert_success

  assert [ ! -e "$API_STATE/created" ]
  assert [ ! -s "$GITHUB_OUTPUT" ]
}

@test "go: a lookup GitHub cannot answer fails the step and creates nothing" {
  lightweight_tag "$REPO" v1.2.0 "$SECOND"
  echo 500 >"$API_STATE/lookup-status"
  run go_finish "$SECOND"
  assert_failure
  assert_output --partial "looking up the release for v1.2.0 returned HTTP 500"

  assert [ ! -e "$API_STATE/created" ]
}
