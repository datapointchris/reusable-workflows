# reusable-workflows

Reusable GitHub Actions workflows, called from other repositories with
`uses: datapointchris/reusable-workflows/.github/workflows/<file>@v1`. The
README says what each one does and what a caller writes.

## Layout

- `.github/workflows/python-semantic-release.yml` and `go-semantic-release.yml`
  are the product. Each carries its inputs and outputs under `on.workflow_call`.
- `.github/workflows/release.yml` releases this repository. It runs both
  workflows against `tests/fixtures/`, then cuts a version through
  `go-semantic-release.yml` and moves the major tag.
- `.github/workflows/validate.yml`, `.pre-commit-config.yaml` and the lint
  configs are generated from shared templates. A hand edit is overwritten on
  the next regeneration.

## What breaks callers

Every caller pins `@v1`, so a merge to `main` that releases reaches all of them
on their next run.

- **Renaming, retyping or removing an input or output is a breaking change.**
  Write it as `feat!:` or with a `BREAKING CHANGE:` footer. go-semantic-release
  then cuts 2.0.0, the major-tag job moves `v2`, and `v1` stays put. Adding an
  input with a default is not breaking.
- **A job's `permissions` can only narrow what the caller grants.** Asking for
  a scope the callers do not grant breaks every one of them. The README tells
  callers to grant `contents: write` and nothing else.
- **The repository must stay public.** A private repository's workflows can be
  called only from other private repositories.
- **Caller-level `env` does not reach a called workflow.** Anything a workflow
  needs from the caller is an input.

## Pinning

Third-party actions are pinned to a commit, with the release as a trailing
comment. `actions/*` actions are pinned to their major tag. goreleaser itself is
pinned by `version:`, never `latest`.

## Publishing stays out

PyPI's Trusted Publishing cannot name a reusable workflow as the publisher. A
publish job therefore lives in the caller and reads `released` and `tag` from
`python-semantic-release.yml`. Do not add one here.

## Testing a change

Nothing runs these locally. A pull request runs `validate.yml`, whose
actionlint checks each local `uses:` call against the called workflow's inputs.
The workflows themselves first execute on `main`, in `release.yml`, before the
major tag moves.

- `tests/fixtures/python` has its own `tag_format`, so it never matches a real
  tag and the noop run always computes a first release. `python-noop-outputs`
  fails when those outputs come back empty.
- `tests/fixtures/go` is built as a goreleaser snapshot, which uploads nothing.
- go-semantic-release's action returns without a version, and without failing,
  on any exit code from 60 to 69. That covers both "no release needed" and a
  run off the release branch. A dry run that reports no version has therefore
  proved only that the job started.
