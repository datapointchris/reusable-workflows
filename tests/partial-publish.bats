#!/usr/bin/env bats
# python-publish.yml's build and upload steps, against a local pypiserver at
# the version the index runs. The upload step uses the uv on PATH, which
# validate.yml sets up before the hooks run.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load helpers

  PACKAGES_DIR="$BATS_TEST_TMPDIR/index"
  mkdir -p "$PACKAGES_DIR"
  local port
  port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  uv tool run --from pypiserver==2.4.1 pypi-server run -p "$port" -a . -P . "$PACKAGES_DIR" \
    >"$BATS_TEST_TMPDIR/index.log" 2>&1 3>&- &
  INDEX_PID=$!
  INDEX="http://127.0.0.1:$port"
  local waited=0
  until curl -fsS "$INDEX/health" >/dev/null 2>&1; do
    if [ "$waited" -ge 600 ]; then
      echo "pypiserver did not start" >&2
      cat "$BATS_TEST_TMPDIR/index.log" >&2
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done

  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT/src/fixture_publish"
  touch "$PROJECT/src/fixture_publish/__init__.py"
  cat >"$PROJECT/pyproject.toml" <<'EOF'
[project]
name = "fixture-publish"
version = "0.1.0"

[build-system]
requires = ["uv_build>=0.9,<1"]
build-backend = "uv_build"
EOF
  cd "$PROJECT" || return 1
  export UV
  UV=$(command -v uv)
}

teardown() {
  if [ -n "${INDEX_PID:-}" ]; then
    kill "$INDEX_PID" 2>/dev/null || true
  fi
}

@test "a re-run of an upload that stopped after the wheel uploads the sdist" {
  run_step python-publish.yml publish build
  "$UV" publish --publish-url "$INDEX/" --username ci --password ci dist/*.whl

  PUBLISH_URL="$INDEX/" CHECK_URL="$INDEX/simple/" \
    UV_PUBLISH_USERNAME=ci UV_PUBLISH_PASSWORD=ci \
    run run_step python-publish.yml publish upload
  assert_success
  assert_output --partial "already exists"

  run ls "$PACKAGES_DIR"
  assert_output "fixture_publish-0.1.0-py3-none-any.whl
fixture_publish-0.1.0.tar.gz"
}
