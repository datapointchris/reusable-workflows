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

# Puts a `uv` on PATH that runs `uv run [options] python <args>` as
# `python3 <args>`. GitHub's runner image carries no uv, and finding a Python is
# uv's part, which fixtures.yml exercises by running the workflow itself.
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
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}
