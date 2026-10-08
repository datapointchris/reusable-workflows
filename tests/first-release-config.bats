#!/usr/bin/env bats
# python-semantic-release.yml's `config` step. It writes the caller's
# [tool.semantic_release] table as the JSON config the action loads, with
# mask_initial_release defaulted to true.

load "$HOME/.local/lib/bats-support/load.bash"
load "$HOME/.local/lib/bats-assert/load.bash"

setup() {
  load helpers
  clear_git_environment
  stub_uv
  export PYPROJECT="$BATS_TEST_TMPDIR/pyproject.toml"
  export CONFIG="$BATS_TEST_TMPDIR/semantic-release.json"
}

config_step() {
  run_step python-semantic-release.yml release config
}

@test "the caller's table gains the default and keeps every key it had" {
  cat >"$PYPROJECT" <<'EOF'
[project]
name = "demo"
version = "0.0.0"

[tool.semantic_release]
version_toml = ["pyproject.toml:project.version"]
commit_message = "build(release): {version}"
build_command = """
    pip install uv
    uv lock --upgrade-package demo
"""

[tool.semantic_release.branches.main]
match = "main"
EOF

  run config_step
  assert_success

  run jq -c '.semantic_release.changelog' "$CONFIG"
  assert_output '{"default_templates":{"mask_initial_release":true}}'

  run jq -cS '.semantic_release | del(.changelog)' "$CONFIG"
  assert_output "$(jq -cnS '{
    version_toml: ["pyproject.toml:project.version"],
    commit_message: "build(release): {version}",
    build_command: "    pip install uv\n    uv lock --upgrade-package demo\n",
    branches: {main: {match: "main"}}
  }')"
}

@test "a caller that turns the mask off keeps it off" {
  cat >"$PYPROJECT" <<'EOF'
[tool.semantic_release.changelog.default_templates]
mask_initial_release = false
changelog_file = "HISTORY.md"
EOF

  run config_step
  assert_success

  run jq -c '.semantic_release.changelog.default_templates' "$CONFIG"
  assert_output '{"mask_initial_release":false,"changelog_file":"HISTORY.md"}'
}

@test "a pyproject with no semantic_release table gets the default alone" {
  cat >"$PYPROJECT" <<'EOF'
[project]
name = "demo"
EOF

  run config_step
  assert_success

  run jq -c '.' "$CONFIG"
  assert_output '{"semantic_release":{"changelog":{"default_templates":{"mask_initial_release":true}}}}'
}
