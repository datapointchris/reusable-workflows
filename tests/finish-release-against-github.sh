#!/usr/bin/env bash
# Runs both workflows' `finish` steps against GitHub itself, on scratch tags at
# this run's commit, and checks the releases they create. fixtures.yml runs it
# on a branch push, with GH_TOKEN granted contents: write. Every release and tag
# it makes is deleted on exit.
set -euo pipefail

workflows="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows"
work=$(mktemp -d)
api="repos/${GITHUB_REPOSITORY}"

# Both tags sort below every 1.x release, and neither matches the Python
# fixture's tag_format, so no other job in the run sees a release to cut.
python_version="0.${GITHUB_RUN_ATTEMPT}.${GITHUB_RUN_ID}-rc.1"
python_tag="scratch-v${python_version}"
go_tag="v0.${GITHUB_RUN_ATTEMPT}.${GITHUB_RUN_ID}"

cleanup() {
  local tag id
  for tag in "$python_tag" "$go_tag"; do
    if id=$(gh api "${api}/releases/tags/${tag}" --jq .id 2>/dev/null); then
      gh api --method DELETE "${api}/releases/${id}" || true
    fi
    git push --quiet origin --delete "refs/tags/${tag}" 2>/dev/null || true
  done
}
trap cleanup EXIT

# Usage: step_script <workflow file> <job> <step id>
step_script() {
  local path="$work/$2-$3.sh"
  JOB="$2" ID="$3" yq '.jobs[strenv(JOB)].steps[] | select(.id == strenv(ID)) | .run' \
    "$workflows/$1" >"$path"
  if [ ! -s "$path" ]; then
    echo "::error::no step with id $3 in job $2 of $1" >&2
    return 1
  fi
  echo "$path"
}

# Usage: run_step <script> <output file>
run_step() {
  : >"$2"
  GITHUB_OUTPUT="$2" bash --noprofile --norc -eo pipefail "$1"
}

# Usage: expect <what is checked> <actual> <expected>
expect() {
  if [ "$2" != "$3" ]; then
    echo "::error::$1 is '$2', where '$3' was expected"
    exit 1
  fi
  echo "ok: $1 is '$3'"
}

latest() {
  local tag
  if tag=$(gh api "${api}/releases/latest" --jq .tag_name 2>/dev/null); then
    echo "$tag"
  else
    echo none
  fi
}

release_field() {
  gh api "${api}/releases/tags/$1" --jq ".$2"
}

latest_before=$(latest)
git tag "$python_tag" "$GITHUB_SHA"
git tag "$go_tag" "$GITHUB_SHA"
git push --quiet origin "refs/tags/${python_tag}" "refs/tags/${go_tag}"

python_finish=$(step_script python-semantic-release.yml release finish)
TAG=$python_tag VERSION=$python_version PRERELEASE=true \
  run_step "$python_finish" "$work/python-output"
expect "the Python step's output" "$(cat "$work/python-output")" "released=true"
expect "the Python release's prerelease flag" "$(release_field "$python_tag" prerelease)" true

go_finish=$(step_script go-semantic-release.yml semver finish)
run_step "$go_finish" "$work/go-output"
expect "the Go step's output" "$(cat "$work/go-output")" "version=${go_tag#v}"
expect "the Go release's prerelease flag" "$(release_field "$go_tag" prerelease)" false
expect "the Go release's draft flag" "$(release_field "$go_tag" draft)" false
expect "the Latest release after both steps" "$(latest)" "$latest_before"

run_step "$go_finish" "$work/go-again-output"
expect "a second Go run's output, once the release exists" "$(cat "$work/go-again-output")" ""

# goreleaser, uploading to a release that exists, edits it twice. Neither edit
# carries make_latest unless the caller's .goreleaser.yaml sets one, so these
# are the requests a re-run's goreleaser job sends.
id=$(release_field "$go_tag" id)
gh api --method PATCH "${api}/releases/${id}" -f name="$go_tag" -f tag_name="$go_tag" \
  -F draft=false -F prerelease=false -f body="Scratch release notes." >/dev/null
gh api --method PATCH "${api}/releases/${id}" -F draft=false -f name="$go_tag" >/dev/null
expect "the Latest release after goreleaser's edits" "$(latest)" "$latest_before"
