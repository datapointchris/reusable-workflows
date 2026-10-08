#!/usr/bin/env bash
# Shared helpers. Loaded by every suite.

WORKFLOWS="$BATS_TEST_DIRNAME/../.github/workflows"

# A commit from a linked worktree exports GIT_DIR and GIT_INDEX_FILE into each
# hook, and GIT_DIR outranks `git -C`. Without this, a test's scratch
# repository is built inside the repository being committed.
clear_git_environment() {
  local name
  while read -r name; do
    unset "$name"
  done < <(git rev-parse --local-env-vars)
}

# Writes a step's run: script, found by its id, to a file and echoes the path.
#
# Usage: step_script <workflow file> <job> <step id>
step_script() {
  local path="$BATS_TEST_TMPDIR/$3.sh"
  JOB="$2" ID="$3" yq '.jobs[strenv(JOB)].steps[] | select(.id == strenv(ID)) | .run' \
    "$WORKFLOWS/$1" >"$path"
  if [ ! -s "$path" ]; then
    echo "no step with id $3 in job $2 of $1" >&2
    return 1
  fi
  echo "$path"
}

# Runs a step's script with the shell GitHub runs a bash step with.
#
# Usage: run_step <workflow file> <job> <step id>
run_step() {
  local script
  script=$(step_script "$1" "$2" "$3") || return 1
  bash --noprofile --norc -eo pipefail "$script"
}

# Commits with no change, under a fixed identity, and echoes the commit.
#
# Usage: commit <repository> <message>
commit() {
  git -C "$1" -c user.email=test@example.invalid -c user.name=Test \
    -c commit.gpgsign=false commit --quiet --allow-empty -m "$2"
  git -C "$1" rev-parse HEAD
}

# Tags a commit the way each tool does: python-semantic-release annotates its
# tags, and provider-github creates a lightweight ref.
#
# Usage: annotated_tag <repository> <tag> <commit>
#        lightweight_tag <repository> <tag> <commit>
annotated_tag() {
  git -C "$1" -c user.email=test@example.invalid -c user.name=Test \
    -c tag.gpgsign=false tag -a "$2" -m "$2" "$3"
}
lightweight_tag() {
  git -C "$1" tag "$2" "$3"
}

# Writes a `uv` that runs `uv run [options] python <args>` as `python3 <args>`,
# and points UV at it. GitHub's runner image carries no uv, and finding a
# Python is uv's part, which fixtures.yml exercises by running the workflow
# itself.
stub_uv() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/uv" <<'EOF'
#!/usr/bin/env bash
[ "$1" = run ] || exit 2
shift
while [ $# -gt 0 ] && [ "$1" != python ]; do shift; done
[ $# -gt 0 ] || exit 2
shift
exec python3 "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/uv"
  export UV="$BATS_TEST_TMPDIR/bin/uv"
}

# Starts tests/github-api-stub.py and points GITHUB_API_URL at it. API_STATE is
# the directory it answers from and records into.
start_api_stub() {
  API_STATE="$BATS_TEST_TMPDIR/api"
  mkdir -p "$API_STATE/releases"
  python3 "$BATS_TEST_DIRNAME/github-api-stub.py" "$API_STATE" 3>&- &
  API_PID=$!
  local waited=0 port
  until [ -s "$API_STATE/port" ]; do
    if [ "$waited" -ge 50 ]; then
      echo "the API stub did not start" >&2
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  port=$(cat "$API_STATE/port")
  export GITHUB_API_URL="http://127.0.0.1:$port"
}

stop_api_stub() {
  if [ -n "${API_PID:-}" ]; then
    kill "$API_PID" 2>/dev/null || true
  fi
}
