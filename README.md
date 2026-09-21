# reusable-workflows

GitHub Actions workflows that other repositories call with `uses:`, so a job
every repository needs is written once.

Each workflow's inputs and outputs are described in the file itself, under
`on.workflow_call`.

## python-semantic-release.yml

Versions a Python project from its conventional commits. It writes the version
into `pyproject.toml`, commits it, tags, and creates the GitHub release. The
release body is the changelog. Everything else comes from the caller's
`[tool.semantic_release]` table.

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  ci:
    uses: ./.github/workflows/ci.yml

  release:
    needs: ci
    uses: datapointchris/reusable-workflows/.github/workflows/python-semantic-release.yml@v1
    permissions:
      contents: write
```

Publishing to PyPI stays in the caller. PyPI's Trusted Publishing cannot name
a reusable workflow as the publisher, so the upload runs in a job of the
caller's own, reading this workflow's outputs:

```yaml
  publish:
    needs: release
    if: needs.release.outputs.released == 'true'
    runs-on: ubuntu-latest
    environment: pypi
    permissions:
      id-token: write
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ needs.release.outputs.tag }}
      - uses: astral-sh/setup-uv@v7
      - run: uv build
      - run: uv publish
```

## go-semantic-release.yml

Tags a version from the conventional commits since the last release and creates
the GitHub release. It reads the caller's `.semrelrc` when there is one.
go-semantic-release reads no language, so a repository that ships only a tag
calls it too.

```yaml
  release:
    needs: ci
    uses: datapointchris/reusable-workflows/.github/workflows/go-semantic-release.yml@v1
    permissions:
      contents: write
    with:
      goreleaser: true
```

Its options:

- `goreleaser` builds the new version from `.goreleaser.yaml` and uploads the
  binaries to its release.
- `prime-module-proxy` fetches the new version through `proxy.golang.org`.
  Until the proxy has it, `go install <module>@latest` installs the previous
  version and exits 0.
- `allow-initial-development-versions` keeps a 0.x version on 0.x. Without it,
  the next change of any kind cuts 1.0.0.

## What the caller keeps

The called jobs run on the caller's runners, against the caller's checkout.

- **`permissions: contents: write` on the calling job.** A called workflow can
  only narrow the permissions its caller grants, and both workflows commit or
  tag.
- **The `concurrency` group**, at the top of the calling workflow. There it
  covers the publish job beside the release as well.
- **The gate.** `needs:` on the calling job is what keeps an untested commit
  from being released.
- **The runner.** `runs-on` takes JSON, so a private repository can name a
  self-hosted pool: `runs-on: '["self-hosted","linux"]'`. It defaults to
  `ubuntu-latest`.

## Versions

Pin `@v1`. `v1` moves to every 1.x.y release. A change that would break a
caller is released as 2.0.0 and moves `v2`, and `v1` stays where it was.

Each release first runs both workflows against the projects under
`tests/fixtures`. The Python workflow computes a release without writing one,
and the Go workflow builds a goreleaser snapshot. The major tag moves only once
both pass.
