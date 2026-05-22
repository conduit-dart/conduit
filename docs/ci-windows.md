# Windows CI notes

The Windows workflow (`.github/workflows/windows.yml`) mirrors `linux.yml` /
`macos.yml` but runs on `windows-latest`. It was brought up in PR #290. This
doc records the Windows-specific gotchas hit during that bring-up so future
contributors don't re-trip them.

Windows CI is **green** as of the `feat/windows-ci` work: `smoke` (beta +
main) and `unit` all pass.

## Shell

All `run:` steps are pinned to `bash` via a top-level `defaults.run.shell`.
`windows-latest` runs `run:` steps in PowerShell by default, but the setup
blocks are bash and shared with the Linux/macOS workflows; forcing
`shell: bash` keeps the three in lockstep. The bash GitHub Actions uses on
Windows is **Git Bash** (`C:\Program Files\Git\bin\bash.EXE`), invoked with
`-e -o pipefail`.

Two consequences of Git Bash that bit this workflow, both below: it does not
honour `PATHEXT` (so a bare `melos` / `conduit` does not resolve to the
`.bat` launcher), and `melos exec` spawns its per-package commands through
**`cmd.exe`**, not bash.

## The bring-up failures, in the order they surfaced

### 1. `melos: command not found` (exit 127)

`dart pub global activate melos` installs the launcher as `melos.bat`.
Git Bash does not honour `PATHEXT`, so a bare `melos` is unresolvable even
with `.pub-cache/bin` on `PATH`. Also, `dart-lang/setup-dart` exports
`PUB_CACHE` as a Windows-style path (`C:\Users\runneradmin/.pub-cache`),
which is not a valid POSIX `PATH` entry.

**Fix:** invoke melos as `dart pub global run melos` (launcher-name
agnostic, identical on all three platforms), and convert `PUB_CACHE` with
`cygpath -u` before putting `.pub-cache/bin` on `PATH`.

### 2. `cache-source` is POSIX-only → use `cache-source-win`

The `cache-source` melos script (root `pubspec.yaml`) uses `mkdir -p` /
`cp`. `melos exec` runs per-package commands through `cmd.exe` on Windows,
which has neither. The repo ships a `cache-source-win` variant (mkdir +
xcopy); `windows.yml` calls that instead.

### 3. `cache-source-win` fails — forward slash in `PUB_CACHE`

`setup-dart` sets `PUB_CACHE=C:\Users\runneradmin/.pub-cache` — mixed
separators. `cmd.exe`'s `mkdir` rejects the embedded forward slash with
`The syntax of the command is incorrect.`

Note: `cache-source-win` uses the bare tokens `MELOS_PACKAGE_NAME` etc.
That is **correct** — melos substitutes those tokens itself at exec time
(the command melos *echoes* still shows the literal template, which is
misleading; the Linux run echoes the same literal tokens and works). The
forward slash was the only bug.

**Fix:** `windows.yml` normalizes `PUB_CACHE` to all-backslashes
(`export PUB_CACHE="${PUB_CACHE//\//\\}"`) and persists it via
`$GITHUB_ENV` so the `cmd.exe` children melos spawns inherit it.

### 4. `conduit: command not found` in the AOT smoke (exit 127)

`ci/template-aot-smoke.sh` calls a bare `conduit`. Same `.bat` problem as
melos: the CLI installs as `conduit.bat`.

**Fix:** `windows.yml`'s `Template AOT smoke` step defines `conduit` as an
exported bash function routed through `dart pub global run conduit`, so the
shared smoke script is left untouched.

### 5. `conduit create` crash — "Cannot extract a file path from a d URI"

A genuine conduit-CLI bug, not a CI issue. `create.dart`'s `_truepath()`
round-tripped a filesystem path through `Uri.parse(path).toFilePath()`. On
Windows a path like `D:\a\conduit` parses as a URI whose **scheme is the
drive letter `d`**, and `toFilePath()` then throws. On POSIX it worked only
by accident (a leading-slash path parses as a schemeless URI).

**Fix:** `_truepath()` now uses `package:path`'s `canonicalize()` directly —
`path` already arrives as a filesystem path, so it must not go through
`Uri.parse`. This makes `conduit create` work on Windows for the first time.

### 6. `dart pub get` cannot resolve the override paths

`ci/template-aot-smoke.sh` writes `$WORKSPACE` into the generated
`pubspec_overrides.yaml` as `path:` dependencies. `$WORKSPACE` defaulted to
a Git Bash path (`/d/a/conduit/conduit`), which Windows `dart pub` cannot
resolve.

**Fix:** `windows.yml` exports `CI_WORKSPACE="$(pwd -W)"` (the script
already honours `CI_WORKSPACE`); `pwd -W` yields the Windows-form path
`D:/a/conduit/conduit`, which `pub` accepts. No shared-script change.

## Why the `unit` job can show as skipped

`unit` has `needs: smoke`. When `smoke` fails, GitHub Actions skips `unit`
as a downstream dependency — it is **not** the `if:` branch-prefix guard
misfiring. The `if:` condition (`startsWith(github.head_ref, 'feat/') ||
...`) is satisfied by branches like `feat/windows-ci`. Once `smoke` is
green, `unit` runs.

## Postgres on Windows runners

Windows runners cannot host Linux `services:` containers (which `linux.yml`
uses for Postgres). `windows.yml` provisions Postgres natively with
`ikalnytskyi/action-setup-postgres@v8`, the same action `macos.yml` uses —
it supports Linux, macOS, and Windows.

## Line endings

There is no `.gitattributes` in the repo. The `ci/` scripts are bash, run by
Git Bash on Windows, and have not needed CRLF/LF normalization. If a shell
script starts failing on Windows with `\r: command not found`, add a
`.gitattributes` entry forcing LF (`*.sh text eol=lf`) before reaching for
workflow changes.

## CI cost

`windows.yml` carries `paths-ignore` for `**.md` and `docs/**`, so editing
this file does not burn a Windows CI matrix. `linux.yml` / `macos.yml` do
not yet have that filter — a reasonable follow-up.
