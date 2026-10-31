# reusable-workflows

The release job every repository needs, written once and called with `uses:`.
Two workflows ship:

- `python-semantic-release.yml` versions a Python project from its
  conventional commits. It tags the version and creates the GitHub release.
- `go-semantic-release.yml` tags a version from the conventional commits and
  creates the GitHub release. It reads no language, so a repository that ships
  only a tag calls it too. On request it builds Go binaries and primes the Go
  module proxy.

Copied into each repository, a workflow changes one repository at a time.
Called by reference, as these are, one release here reaches every caller on its
next run. The caller's `release.yml` stays its own file.

Each workflow's inputs and outputs are described in the file itself, under
`on.workflow_call`.

## Starting from scratch

A repository with no release workflow writes one file:

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    branches: [main]                 # every push to main is a release candidate

permissions:
  contents: read                     # every job starts read-only and widens its own

concurrency:
  group: release-${{ github.ref }}   # one release at a time on this branch
  cancel-in-progress: false          # a canceled release can leave a tag with no release

jobs:
  validate:
    uses: ./.github/workflows/validate.yml   # the gate: CI passes before anything is cut

  release:
    needs: validate
    uses: datapointchris/reusable-workflows/.github/workflows/python-semantic-release.yml@v1
    permissions:
      contents: write                # the most a called job can hold is what this grants
```

Then it pushes the file and watches the first run:

```bash
git commit -m "ci: release from main" -- .github/workflows/release.yml  # a ci: commit cuts no version
git push origin main                            # the push to main is the trigger
gh run list --workflow release.yml --limit 1    # validate, then release, on that commit
gh release view                                 # proves it: the tag cut, with its notes
```

A Go module, or a repository that ships only a tag, names
`go-semantic-release.yml` instead. Its section below shows that call.

`validate` calls the repository's own CI workflow. That workflow needs
`workflow_call` among its triggers. Once a release job calls it, it needs no
push trigger on main of its own. With one, every job runs twice for each push.

A push whose commits since the last release call for no version cuts nothing.
The run stays green. `gh release view` then shows the previous release, or
none. The first `fix:` or `feat:` to reach main cuts one.

## Which workflow answers which question

| Ask | Surface | Reads |
| --- | --- | --- |
| What version does this Python project get next | `python-semantic-release.yml` | the caller's `[tool.semantic_release]` table |
| How does the release reach PyPI | a `publish` job in the caller | `released` and `tag` from `python-semantic-release.yml` |
| What version does this Go module, or tag-only repository, get next | `go-semantic-release.yml` | the caller's `.semrelrc`, when there is one |
| Where are this release's binaries | `goreleaser: true` | `.goreleaser.yaml` in `directory` |
| Why does `go install <module>@latest` install the last version | `prime-module-proxy: true` | `go.mod` at the repository root |
| Why does a `fix:` on a 0.x project cut 1.0.0 | `allow-initial-development-versions: true` | the commits since the last release |
| What would this run cut, without cutting it | `noop: true` for Python, `dry: true` for Go | the same commits and configuration |
| Why did a run on a moved branch cut nothing | the run's notice | the branch on `origin` |
| Why did the job go red after the tag was pushed | re-run the failed jobs | the tag the failed attempt pushed |

## The caller keeps the permissions, the concurrency group, the gate and the runner

The called jobs run on the caller's runners, against the caller's checkout.

- **`permissions: contents: write` on the calling job.** A called workflow can
  only narrow the permissions its caller grants. Both workflows commit or tag.
  Grant that scope and nothing else. A job asking for a scope the caller does
  not grant fails before it starts.
- **The `concurrency` group**, at the top of the calling workflow. There it
  covers the publish job beside the release as well.
- **The gate.** `needs:` on the calling job is what keeps an untested commit
  from being released.
- **The runner.** The `runs-on` input takes JSON, so a self-hosted pool is
  named by its labels: `runs-on: '["self-hosted","<label>"]'` under `with:`. A
  single label is a JSON string inside the YAML one, quotes included, the way
  the input's `default` writes it. That default is a GitHub-hosted Ubuntu
  runner.

Caller-level `env` does not reach a called workflow. Everything a workflow
takes from the caller arrives as an input.

## `python-semantic-release.yml` — a Python project versioned from its commits, configured by its own pyproject

```yaml
    with:
      directory: packages/app                  # where pyproject.toml sits; the root by default
      runs-on: '["self-hosted","<label>"]'     # a pool, as JSON
      noop: true                               # a trial: writes nothing, outputs still carry the release
```

Everything but those inputs comes from the caller's `[tool.semantic_release]`
table. A table naming files to stamp, through `version_toml` or
`version_variables`, gets the version written into them. That change is
committed, and the tag goes on the commit. A caller whose version is read from
the tag stamps no file. Its release tags the caller's own commit and writes no
commit.

The release body is the changelog, built from the same commits. No
`CHANGELOG.md` is written or tracked.

A first release's notes read "Initial Release". Otherwise they would list every
commit in the history with its body. GitHub refuses a release body over 125,000
characters. A caller wanting the full list sets `mask_initial_release = false`
under `[tool.semantic_release.changelog.default_templates]`. A key the caller
sets always wins over the workflow's default.

The step that reads the table and python-semantic-release both run under a
pinned uv. uv downloads Python 3.11 or later when the runner has none, so a
self-hosted runner needs no Python. It needs no Docker either. uv is pinned for
Linux on x86_64 and aarch64. Any other architecture fails the run with `no uv
build is pinned`.

## Publishing to PyPI stays in the caller, because Trusted Publishing cannot name a reusable workflow

PyPI's Trusted Publishing names the workflow file that uploads, and it cannot
name a reusable workflow. So the upload runs in a job of the caller's own,
reading this workflow's outputs. The job sits in the same workflow as the
release. A tag pushed with `GITHUB_TOKEN` starts no other workflow run, so a
publish keyed on `release: published` or `push: tags` never fires.

```yaml
  publish:
    needs: release
    if: needs.release.outputs.released == 'true'
    runs-on: ubuntu-latest
    environment: pypi
    permissions:
      id-token: write                            # Trusted Publishing's credential, held by this job alone
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ needs.release.outputs.tag }}    # the tag, never the branch, which may have moved
      - uses: astral-sh/setup-uv@<commit>          # a third-party action, pinned to a commit
      - run: uv build
      - run: uv publish
```

## `go-semantic-release.yml` — a tag from the commits for any repository, with Go's build and proxy on request

```yaml
  release:
    needs: validate
    uses: datapointchris/reusable-workflows/.github/workflows/go-semantic-release.yml@v1
    permissions:
      contents: write
    with:
      goreleaser: true                           # build from .goreleaser.yaml, upload to the release
      prime-module-proxy: true                   # fetch the version through proxy.golang.org
      allow-initial-development-versions: true   # keep 0.x on 0.x
```

It reads the caller's `.semrelrc` when there is one. The `version` output
carries the version cut, with no leading `v`. It is empty when the commits
since the last release call for none.

It tags the commit the run was started for, never the branch's tip. A push
landing mid-run is never released without passing the caller's gate.

- `goreleaser` builds the tag just cut rather than the branch, which may have
  moved since.
- `prime-module-proxy` closes a gap. Until the proxy has the tag, `go install
  <module>@latest` installs the previous version and exits 0. The fetch is its
  own job, so a failed fetch leaves goreleaser running. The run still goes red,
  and re-running the failed job retries the fetch.
- `prime-module-proxy` refuses a `directory` other than the root, before
  checkout. A module in a subdirectory resolves only from a `<dir>/vX.Y.Z` tag,
  and this workflow cuts the root's `vX.Y.Z`.
- `allow-initial-development-versions` keeps a 0.x version on 0.x. Without it,
  the next `fix:` or `feat:` cuts 1.0.0.

The runner must be Linux x64. The semantic-release binary is downloaded for
linux/amd64.

go-semantic-release's analyzer majors a release on the breaking-change marker
anywhere in any commit message, and a caller's `.semrelrc` cannot switch that
off. A major on a Go module with no `/vN` path strands every
`go install …@latest`. So the guard is a commit hook refusing the marker,
before the commit reaches main.

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

Releasing from the older commit fails. `go-semantic-release.yml` tags it
through the API, and GitHub refuses `GITHUB_TOKEN` a tag behind a push that
changed a workflow file. The token holds no `workflows` permission.
`python-semantic-release.yml` fails on whichever run pushes second. GitHub
answers 403 to its tag, or the moved branch refuses its version commit as
non-fast-forward.

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

## Callers pin `@v1`, and a change reaches them only through a release

```bash
gh release view -R datapointchris/reusable-workflows   # the release v1 points at, and its notes
```

`v1` moves to every 1.x.y release. A change that would break a caller is
released as 2.0.0 and moves `v2`, and `v1` stays where it was. A re-run that
finishes an older release's failed attempt never moves `v1` back onto it.

Every push runs both workflows against the projects under `tests/fixtures`: on
a branch before it merges, and on `main` before a version is cut. The Python
workflow computes a release without writing one. The Go workflow builds a
goreleaser snapshot. On a branch, both finish steps also create a release on
GitHub itself, on scratch tags the run deletes.

The tools inside are pinned too: semantic-release and its plugins, goreleaser,
uv, and python-semantic-release by its version on PyPI. Handed no binary,
the go-semantic-release action downloads the newest semantic-release on every
run, and that binary downloads the newest plugins. Either would change how
every caller's version is worked out, with no commit here. A version of any of
them moves only in a commit here, and reaches callers only through a release.
