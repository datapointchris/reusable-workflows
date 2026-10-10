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

A first release's notes read "Initial Release". Otherwise they would list every
commit in the history with its body. GitHub refuses a release body over 125,000
characters. A caller wanting the full list sets
`mask_initial_release = false` under
`[tool.semantic_release.changelog.default_templates]`.

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
  validate:
    uses: ./.github/workflows/validate.yml

  release:
    needs: validate
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
    needs: validate
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
  the next `fix:` or `feat:` cuts 1.0.0.

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
  `ubuntu-latest`. `go-semantic-release.yml` needs a Linux x64 runner.

## A failed release is finished by re-running it

Each tool pushes the tag before it creates the GitHub release. When creating
the release fails, re-run the failed jobs. The re-run creates the release for
that tag, with notes GitHub generates, and reports it as cut:
`python-semantic-release.yml` sets `released` to `true`, and
`go-semantic-release.yml` sets `version`. The publish job, goreleaser and the
module proxy then run as they would have.

A re-run acts only on a tag at or after the commit the run was started for. An
older release's tag missing its release is left alone.

A re-run can come after a newer release has been cut. The release it creates is
then not marked Latest, and the newer release keeps that mark.

## A run the branch has moved past leaves the release to the newer push

A push landing while a run waits on its gate starts a run of its own. That run
resolves from the same last release, so it releases the older run's commits as
well. The `concurrency` group does not stop the two overlapping. It queues the
newer run, and the older one is already past the point of being queued.

Releasing from the older commit fails. `go-semantic-release.yml` tags it through
the API, and GitHub refuses `GITHUB_TOKEN` a tag behind a push that changed a
workflow file. The token holds no `workflows` permission.
`python-semantic-release.yml` pushes a version commit onto it, and the moved
branch refuses that as non-fast-forward.

So both workflows read the branch on `origin` before cutting anything. When it
has moved past the run's commit, the run writes a notice and cuts nothing.
`version` comes back empty and `released` comes back `false`, so goreleaser,
the module proxy and a publish job skip.

A re-run finishing a failed attempt goes on. That attempt's tag sits at the
run's commit, or on the version commit it made directly on top. No newer run
creates that release.

A push landing in the seconds between the check and the tag still fails the
run. When the newer run fails its gate, these commits wait for the next push
that passes it.

## Versions

Pin `@v1`. `v1` moves to every 1.x.y release. A change that would break a
caller is released as 2.0.0 and moves `v2`, and `v1` stays where it was.

Every push runs both workflows against the projects under `tests/fixtures`: on
a branch before it merges, and on `main` before the major tag moves. The Python
workflow computes a release without writing one, and the Go workflow builds a
goreleaser snapshot.

The tools inside are pinned too: semantic-release and its plugins, goreleaser,
uv, and python-semantic-release through its action's commit. A new version of
any of them reaches callers only through a release here.
