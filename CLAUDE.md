# reusable-workflows

Reusable GitHub Actions workflows, called from other repositories with
`uses: datapointchris/reusable-workflows/.github/workflows/<file>@v1`. The
README says what each one does and what a caller writes.

## Layout

- `.github/workflows/python-semantic-release.yml` and `go-semantic-release.yml`
  are the product. Each carries its inputs and outputs under `on.workflow_call`.
- `.github/workflows/fixtures.yml` runs both against `tests/fixtures/`.
- `.github/workflows/release.yml` releases this repository. It calls
  `fixtures.yml`, then cuts a version through `go-semantic-release.yml` and
  moves the major tag.
- `.github/workflows/validate.yml`, `.pre-commit-config.yaml` and the lint
  configs are generated from shared templates. A hand edit is overwritten on
  the next regeneration.

## What breaks callers

Every caller pins `@v1`, so a merge to `main` that releases reaches all of them
on their next run.

- **Renaming, retyping or removing an input or output breaks every caller.**
  Release it with the subject `chore(release-major): …`, the one subject
  `.semrelrc` majors on. The major-tag job then moves `v2`, and `v1` stays
  where it was. `feat!:` is a minor here. Adding an input with a default breaks
  nothing.
- **A job's `permissions` can only narrow what the caller grants.** Asking for
  a scope the callers do not grant fails every caller's run before a job
  starts. The README tells callers to grant `contents: write` and nothing else.
- **The repository must stay public.** A private repository's workflows can be
  called only from other private repositories.
- **Caller-level `env` does not reach a called workflow.** Anything a workflow
  needs from the caller is an input.

## Never write the breaking-change trailer in a commit message

Those words, either number, colon or not, subject or body, cut a major release
here. The commit analyzer matches them unanchored against the raw message and
ORs the result with the configured major rules, so `.semrelrc` cannot stop it
and it majors even a `fix:` commit.

A major moves `v2` and leaves `v1` behind, so every caller pinned `@v1` stops
receiving fixes, and nothing tells them. **The ban covers a commit that merely
discusses the trailer.** Name it some other way, "that marker", and never quote
it. The same holds for a pull request body, which becomes the merge commit.

## Pinning

Third-party actions are pinned to a commit, with the release as a trailing
comment. `actions/*` actions are pinned to their major tag. The tools those
actions would otherwise fetch are pinned in the workflow:

- semantic-release v2.31.0, downloaded by URL and checked against its sha256,
  and its four plugins by `name@version` in `custom-arguments`.
- goreleaser by `version: v2.17.0`.

A pin moves only in a commit here, and `fixtures.yml` runs the new version
before any caller sees it.

## Publishing stays out

PyPI's Trusted Publishing cannot name a reusable workflow as the publisher. A
publish job therefore lives in the caller and reads `released` and `tag` from
`python-semantic-release.yml`. Do not add one here.

## Testing a change

The workflows run only on GitHub. `fixtures.yml` runs on every push to a branch
other than `main`, and `release.yml` runs it again on `main` before cutting a
version. A pull request also runs `validate.yml`, whose actionlint checks each
local `uses:` call against the called workflow's inputs.

Their tools run locally against the fixtures:

- `semantic-release -v --noop version` from `tests/fixtures/python`, with
  python-semantic-release 9.21.2. The fixture's release group matches every
  branch, and no tag matches its own `tag_format`, so it always computes
  `fixture-v0.1.0`. `python-noop-outputs` fails when those outputs come back
  empty.
- `goreleaser release --snapshot --clean` in `tests/fixtures/go`, with
  goreleaser v2.17.0. The snapshot uploads nothing.

go-semantic-release's action returns without a version, and without failing, on
any exit code from 60 to 69. That covers both "no release needed" and a run off
the release branch. `goreleaser-snapshot` on a branch therefore proves the
`semver` job runs, and says nothing about the version it would cut.
