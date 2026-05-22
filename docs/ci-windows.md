# Windows CI notes

The Windows workflow (`.github/workflows/windows.yml`) mirrors `linux.yml` /
`macos.yml` but runs on `windows-latest`. This doc records the
Windows-specific gotchas that bit the workflow during bring-up (PR #290) so
future contributors don't re-trip them.

## Shell

All `run:` steps are pinned to `bash` via a top-level `defaults.run.shell`.
`windows-latest` runs `run:` steps in PowerShell by default, but the
setup blocks are bash and shared verbatim with the Linux/macOS workflows.
Git Bash ships on the runner image, so the three platform workflows stay in
lockstep by forcing `shell: bash`.

The bash that GitHub Actions uses on Windows is **Git Bash**
(`C:\Program Files\Git\bin\bash.EXE`), invoked with `-e -o pipefail`.

## Root cause of the red `smoke` jobs (`melos: command not found`, exit 127)

The Windows `smoke` jobs failed at the `melos bootstrap` line with
`command not found` (exit code 127). There were **two** distinct
Windows-only problems stacked on top of each other.

### Problem 1 — `PUB_CACHE` is a Windows-style path

`dart-lang/setup-dart@v1` exports `PUB_CACHE` into the job environment as a
**Windows-style path**, e.g.:

```
PUB_CACHE: C:\Users\runneradmin/.pub-cache
```

Git Bash's `PATH` is colon-separated and its entries must be **POSIX paths**
(`/c/Users/...`). A Windows-style entry with a drive letter and backslashes
(`C:\Users\runneradmin/.pub-cache/bin`) is not a resolvable `PATH`
component, so this:

```bash
export PATH="$PATH:$PUB_CACHE/bin"
```

silently adds an unusable entry. Convert with `cygpath -u` (ships with Git
Bash) first:

```bash
PUB_CACHE_POSIX="$(cygpath -u "$PUB_CACHE")"
export PATH="$PATH:$PUB_CACHE_POSIX/bin"
echo "$PUB_CACHE_POSIX/bin" >> "$GITHUB_PATH"
```

On Linux/macOS this never bites because `PUB_CACHE` is a POSIX path there.

### Problem 2 — Git Bash will not resolve a bare `.bat` launcher (the real blocker)

Fixing the `PATH` form alone was **not enough** — the second Windows run
still failed at exit 127. On Windows, `dart pub global activate melos`
installs the launcher as **`melos.bat`**. Windows' own command resolution
uses `PATHEXT` to find `melos.bat` when you type `melos`, but **Git Bash
does not honour `PATHEXT`**. So even with `.pub-cache/bin` correctly on
`PATH`, a bare `melos` is unresolvable from a bash step and exits 127.

### Fix

Invoke melos through Dart's package runner instead of the PATH launcher:

```bash
dart pub global run melos bootstrap
dart pub global run melos cache-source --no-select
```

`dart pub global run melos` is launcher-name agnostic and behaves
identically on Linux, macOS, and Windows. The `cygpath` conversion is kept
because later steps still expect `.pub-cache/bin` (and the `conduit`
executable installed there) to be a valid `PATH` entry.

Notes:

- Do **not** overwrite the `PUB_CACHE` env var itself — Dart already has the
  correct Windows-style value from `setup-dart`. The original workflow also
  re-`echo`'d `PUB_CACHE` into `$GITHUB_ENV` with the same value (a no-op);
  that line was removed.
- `export PATH=...` only affects the current step's shell. The
  `>> "$GITHUB_PATH"` line is what carries the directory to *later* steps.
- An alternative to `dart pub global run melos` is calling `melos.bat`
  explicitly, but that would diverge from the Linux/macOS workflows. The
  `dart pub global run` form keeps all three in lockstep.

## Why the `unit` job showed up as skipped

`unit` has `needs: smoke`. When `smoke` fails, GitHub Actions skips `unit`
as a downstream dependency — it is **not** the `if:` branch-prefix guard
misfiring. The `if:` condition (`startsWith(github.head_ref, 'feat/') || ...`)
is satisfied by the `feat/windows-ci` branch. Once `smoke` is green, `unit`
runs normally.

## Postgres on Windows runners

Windows runners cannot host Linux `services:` containers (which `linux.yml`
uses for Postgres). `windows.yml` instead provisions Postgres natively with
`ikalnytskyi/action-setup-postgres@v8`, the same action `macos.yml` relies
on — it supports Linux, macOS, and Windows.

## Line endings

There is currently no `.gitattributes` in the repo. The CI scripts under
`ci/` are plain bash and are executed by Git Bash on Windows; they have not
needed CRLF/LF normalization so far. If a future shell script starts failing
on Windows with errors like `\r: command not found`, add a `.gitattributes`
entry forcing LF (`*.sh text eol=lf`) before reaching for workflow changes.
