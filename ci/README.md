# CI gates and deployment readiness

This directory holds the artifacts that drive CI for both **Woodpecker**
(self-hosted on snowman, see `~/infra/ci/`) and **GitHub Actions**
(`.github/workflows/`). The two pipelines run the same set of gates with
slightly different transports.

`.woodpecker.yml` is the authoritative pipeline for self-hosted runs.

## What "deployable state" means

A commit on `master` is considered deployable when **every gate below
is green** for that commit. A failure of any single gate is enough to
block a release; treat each one as an independent contract.

| Gate | What it proves | Where it runs | Approx. time |
| --- | --- | --- | --- |
| `lint` | Workspace-wide `dart analyze` clean across all 13 packages. | every PR + push | ~30s |
| `build-runner-tests` | The `conduit_build_runner` package's own unit tests pass — `ChannelBuilder`, `SerializableBuilder`, `RegistryBuilder` all emit the expected source. | every PR + push | ~5s |
| `workspace-unit-tests` | Pure-Dart unit tests across `conduit_codable`, `conduit_open_api`, `conduit_password_hash`, `conduit_runtime`, `conduit_config` — no Postgres needed. | every PR + push | ~30s |
| `aot-smoke` (`ci/aot-smoke.sh`) | A scaffolded channel-only Conduit app survives `dart run build_runner build && dart compile exe`, and the resulting binary boots `bootstrap()` and resolves `RuntimeContext.current[Channel]` to the generated runtime. **Failure here means the new AOT path documented in `docs/AOT_WITHOUT_BUILD.md` is broken.** | every PR + push | ~45s |
| `legacy-smoke` (`ci/legacy-smoke.sh`) | A `conduit create -t db_and_auth --offline wildfire` project survives `conduit build` and `conduit db generate`, and `conduit build` produces an executable at `<projectRoot>/<packageName>.aot`. Mirrors the `smoke` job in `.github/workflows/linux.yml`. **Failure here means the legacy mirror-based path is broken**, which is a regression while the build_runner migration is in flight. | every PR + push | ~2 min |
| `core-integration-tests` | Full `conduit_core` test suite against a Postgres 18.0 service container. Same matrix as the GitHub `unit` job. Verified on snowman: 1046 tests pass, 7 skipped, 0 fail. | every PR + push | ~5 min |

## Inputs the gates consume

- `ci/.env` — Postgres connection variables for `conduit_core` integration tests. The Woodpecker pipeline overrides these to point at the in-pipeline `postgres` service (host `postgres`, port `5432`); the GitHub Actions matrix uses host `localhost` port `15432` via the published service mapping. Either way the test env vars (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `TEST_DB_ENV_VAR`, `TEST_VALUE`, `TEST_BOOL`) come from this file.
- `ci/docker-compose.yaml` — local-dev Postgres service for `melos run test-unit` work. Not used by CI.
- `ci/ssl/`, `ci/conduit.cert.pem`, `ci/conduit.key.pem` — TLS material the integration tests load when exercising HTTPS paths.
- `ci/aot-smoke.sh`, `ci/legacy-smoke.sh` — see file headers; both are bash, both expect `PUB_CACHE` and `PATH` set to the workspace pub cache by the surrounding pipeline.

## What's *not* a deployable-state gate

- The five `conduit_runtime` tests in `test/build_test.dart`,
  `test/context_test.dart`, `test/project_analyzer_test.dart` are
  expected to fail in the current environment (path-resolution issues
  pre-existing on `origin/master e6248ca2` — verified by running them
  against a clean worktree of that commit). They are excluded from
  `workspace-unit-tests` for now; un-excluding requires fixing the
  upstream issue.
- Multi-arch Docker image builds (`docker:` and `docker-flutter:` jobs
  in `.github/workflows/publish.yml`) only run on `chore:`-prefixed
  master commits and require Docker Hub + GHCR credentials. They are
  release-time, not PR-time.
- Pub publishing (`pub:` job in `publish.yml`) requires `PUB_CREDENTIALS`
  and is also release-time only.
- Doc deploys (`docs.yml`) only run when a PR with a `docs/*` head
  branch is merged.

## Running the pipeline locally

The `.woodpecker.yml` is plain enough to reproduce by hand against any
`dart:beta` Docker image. The shortest path:

```sh
# Bootstrap the workspace once
docker run --rm \
  -v "$PWD":/conduit -v conduit-pub-cache:/root/.pub-cache \
  -w /conduit dart:beta bash -c '
    dart pub global activate melos
    export PATH="$PATH:/root/.pub-cache/bin"
    melos bootstrap
'

# Then run any gate against the same volume:
docker run --rm \
  -v "$PWD":/conduit -v conduit-pub-cache:/root/.pub-cache \
  -w /conduit dart:beta bash -c '
    export PATH="$PATH:/root/.pub-cache/bin:$PWD/.pub-cache/bin"
    melos run analyze              # lint
    cd packages/build_runner && dart test       # build-runner-tests
    bash ci/aot-smoke.sh                         # aot-smoke
'
```

For the integration-tests gate, start the Postgres service first:

```sh
docker compose -f ci/docker-compose.yaml up -d postgres
```

then run `cd packages/core && . ../../ci/.env && dart test`.

## Why two pipelines

GitHub Actions runs the public-facing PR signal — that's what blocks
merge to `master` for collaborators. Woodpecker on snowman is the
private signal: faster iteration, no minute caps, ability to gate on
local-only artifacts (e.g. multi-arch images cached on the host). Both
read this file for the contract; if a gate diverges between the two,
that's a bug in whichever side drifted.
