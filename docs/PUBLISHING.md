# Publishing to pub.dev — first publish and trusted publishing

Runbook for the maintainer. Releases are tag-driven
(`.github/workflows/publish.yml`): pushing `vX.Y.Z` runs a
`dart pub publish --dry-run` gate over every package, then publishes
each one in runtime-dependency order with **OIDC trusted publishing**
(no stored pub.dev credentials). Trusted publishing has a precondition
CI cannot satisfy on its own: a package has to exist on pub.dev, and be
configured for automated publishing, before the workflow can publish it.

This document covers that one-time setup. The everyday release flow is
in [CONTRIBUTING.md § Releasing](../CONTRIBUTING.md#releasing).

## Current state (2026-10-03)

All 18 publishable packages are on pub.dev at `7.0.0` (published
2026-05-24). The five packages that were first published in 7.0.0 are
**not** under the `theconduit.dev` verified publisher — the pub.dev API
reports `publisherId: null` for them, so they are owned by an individual
uploader account:

| Package | First published | Publisher |
| --- | --- | --- |
| `conduit_sqlite` | 7.0.0 | none (uploader account) |
| `conduit_mysql` | 7.0.0 | none (uploader account) |
| `conduit_graph` | 7.0.0 | none (uploader account) |
| `conduit_graph_neo4j` | 7.0.0 | none (uploader account) |
| `conduit_graphql` | 7.0.0 | none (uploader account) |

Whether automated publishing is enabled on them is only visible on each
package's pub.dev **Admin** tab. Steps 3–4 below are the remaining work
for these five; step 1–2 are for any package added in the future.

Check the publisher of any package with:

```sh
curl -s https://pub.dev/api/packages/<name>/publisher
```

## 1. Prepare the new package

1. It is a member of the root `pubspec.yaml` `workspace:` list and has
   `resolution: workspace`.
2. It has `name`, `description`, `version` (equal to the workspace
   version — use `melos run sync-version`), `repository`,
   `issue_tracker`, a `LICENSE`, a `CHANGELOG.md` with a `## X.Y.Z`
   section, and a `README.md`.
3. It appears in the `sync-version` script in the root `pubspec.yaml`
   and is picked up by `tool/publish-order.py` (run it and confirm the
   package is listed in the right tier).
4. `dart pub publish --dry-run` in the package directory reports
   `Package has 0 warnings.`

## 2. First publish (credential-based, run locally)

A package that does not exist on pub.dev cannot have trusted publishing
configured, so the very first upload is done by hand by a maintainer
who will become its uploader.

```sh
git switch master && git pull --ff-only
melos bootstrap
cd packages/<pkg>
dart pub publish --dry-run   # must be clean
dart pub publish             # opens a browser for Google sign-in
```

Publish runtime dependencies first: if the new package depends on
another workspace package at the same version, that version must
already be visible on pub.dev (`tool/publish-order.py` gives the order).

`dart pub publish` stores an OAuth refresh token in
`~/.config/dart/pub-credentials.json` (Linux; `%APPDATA%\dart` on
Windows). That file is a long-lived credential: don't copy it to CI,
and run `dart pub logout` afterwards if the machine is shared.

## 3. Move the package under the verified publisher

On `https://pub.dev/packages/<pkg>/admin`, signed in as the uploader:

1. **Transfer to publisher** → `theconduit.dev`. This requires being an
   admin of that publisher. After the transfer, the package's
   uploaders are the publisher's members, not the individual account.
2. Confirm with the `curl … /publisher` command above.

## 4. Enable automated publishing (OIDC)

Same Admin tab → **Automated publishing** → **Enable publishing from
GitHub Actions**:

| Field | Value |
| --- | --- |
| Repository | `conduit-dart/conduit` |
| Tag pattern | `v{{version}}` |
| Publishing from `push` events | enabled |
| Publishing from `workflow_dispatch` events | enable only if you release via a dispatched (non-tag) run |
| Require GitHub Actions environment | leave off — `publish.yml` does not use an environment |

The tag pattern has to match what `publish.yml` triggers on
(`v*.*.*`) and the version in the package's `pubspec.yaml`, or pub.dev
rejects the OIDC token with a "tag does not match" error.

## 5. Verify without publishing

Run the release workflow as a dry run against `master`:

```sh
gh workflow run publish.yml --repo conduit-dart/conduit \
  -f version="$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*$/\1/p' pubspec.yaml)" \
  -f dry_run=true
```

The dry run proves the packages are publishable; it does **not**
exercise OIDC. The first real tag push after enabling step 4 is the
first end-to-end check — watch the `publish` job's per-package
"visible on pub.dev" lines. If one package fails, the packages before
it are already published; fix forward with a `+1` patch per
[CONTRIBUTING.md § Releasing](../CONTRIBUTING.md#releasing) (pub.dev
versions are immutable).

## Release rehearsal

To rehearse the full publish-and-consume round-trip without touching
pub.dev, publish to a self-hosted pub server first:
`PUB_SERVER_URL=… PUB_TOKEN=… melos run release-rehearsal`
(`tool/release-rehearsal.sh`).
