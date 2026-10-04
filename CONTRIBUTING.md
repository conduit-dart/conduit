# Contributing

Welcome to the project. All PRs are welcome, though I will be critical of PRs to
the best of my ability. I want to find developers who can help check my work and
also help foster newcomers so that they can help keep me accountable as well.
Thank you for your support. If you have any questions, please reach out on the
[discord server](https://discord.gg/FyJj45NXPx). If I don't respond on the
server, feel free to reach out to me (frosty#1337).

## Branching

If you have a change you want to commit create a branch with the below naming
conventions and topic names.

```
docs/<description>
fix/<username>-<description>
feature/<username>-<description>
refactor/<username>-<description>
```

If the scope of the issue changes for any reason, please rebranch and use the
appropriate anming convention.

## Local Testing

While we do provide CI/CD through github actions, it is slow to get results on
the CI. You should set up your environment in order to run tests locally before
pushing commits.

### Setup

To set up your testing environment, a general rule is to follow what is provided
in the CI configurations. There are workflow files under (.github/workflows) for
each platform, which should give you an idea about how to set up your
environment appropriately. Provide a database with the appropriate
configurations. I highly recommend that you
[install docker](https://docs.docker.com/get-docker/) and use the provided
docker compose file at (ci/docker-compose.yaml) which sets up a similar database
used in the github CI.

### Running Tests

Currently there are three tests that need to be run to hit all the tests:

```bash
melos test-unit
dart tool/generated_test_runner.dart
```

The first will run all the unit tests in conduit and all its dependencies. The
last two test cli components and string-compiled code respectively.

## PR Acceptance Requirements

Please document the intent of the pull request. All non-documentation pull
requests must also include automated tests that cover the new code, including
failure cases. In the case that tests work locally, but not on the CI, please
mention @j4qfrost on the PR. If I don't respond, the best way to contact me is
through discord.

## Commits

The project uses [melos](https://pub.dev/packages/melos) for tooling, which
provides autoversioning based on
[conventional commits](https://www.conventionalcommits.org/en/v1.0.0/). Commits
to `master` will usually be squashed from PRs, so make sure that the PR name
uses conventional commits — it feeds melos versioning and the generated
CHANGELOGs; you do NOT need to use conventional commits on each commit to your
branch. Merging does not publish anything; releases are cut from tags (see
[Releasing](#releasing)).

## Releasing

Maintainers only. Releases are tag-driven through
`.github/workflows/publish.yml`; every package in the workspace is released
at the same version.

1. On a green `master`, set the workspace `version:` in the root
   `pubspec.yaml`, run `melos run sync-version`, and make sure every
   `packages/*/CHANGELOG.md` has a `## X.Y.Z` section. Land that as a PR.
2. Dry-run the release from the Actions tab (`Release` workflow,
   `workflow_dispatch`, `dry_run: true`), or with
   `gh workflow run publish.yml -f version=X.Y.Z -f dry_run=true`. It runs
   `dart pub publish --dry-run` for every package.
3. Push the tag: `git tag -a vX.Y.Z -m "Conduit X.Y.Z" && git push origin vX.Y.Z`.
   CI checks the tag against `pubspec.yaml`, publishes each package to pub.dev
   in dependency order via OIDC trusted publishing, creates the GitHub
   release, and pushes the Docker images.

A package that has never been on pub.dev cannot be published by CI. Follow
[docs/PUBLISHING.md](docs/PUBLISHING.md) for the one-time manual first publish
and trusted-publisher setup before tagging a release that includes it.

### Rollback

pub.dev versions are immutable: you cannot overwrite a version, and there is
no unpublish once 7 days have passed since upload. So rollback means
**fix forward**: revert the breaking change on `master`, release `X.Y.Z+1`
through the same tag flow, and then mark the bad version **retracted** on each
affected package's pub.dev Admin tab so the solver stops picking it for new
resolutions (retraction is allowed for 7 days after publishing). If the
release only partly published (the `publish` job stopped mid-way), the
already-published packages stay published; ship the rest in `X.Y.Z+1` rather
than trying to re-run `X.Y.Z`. Docker images are tagged per version, so
re-point users at the previous `vX.Y.Z-<channel>` tag while the patch ships.

### Deprecation policy

Public API is anything exported from a package's top-level library (for
example `package:conduit_core/conduit_core.dart`) plus the `conduit` CLI's
commands and flags.

- Deprecate in a release of major version N with `@Deprecated('Use X
  instead; removed in N+1.0.0')` (or a CLI warning on stderr), a CHANGELOG
  entry, and a note in the next `docs/migration/` guide.
- Keep the deprecated API working for all of major N — at least one full
  major release of warnings.
- Remove it no earlier than N+1.0.0, and list the removal in that version's
  migration guide.

Security fixes are the only exception; they may change behaviour in a patch
release, called out in the CHANGELOG.

## Licensing

The predessor project, [Aqueduct](https://www.github.com/stablekernel/aquedect),
and the corresponding dependencies will retain their BSD and MIT licenses
copyrighted by stablekernel. Any subsequent work done on Conduit and changes to
dependencies will fall under the BSD-2 liecense attirbuted to conduit-dart and
fellow contributors. So any additional package created from scratch for this
mono-repo must contain the root level license.
