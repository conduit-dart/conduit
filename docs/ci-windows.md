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

## `PUB_CACHE` is a Windows-style path — convert it before touching `PATH`

This was the root cause of the first red Windows run (`smoke` jobs failed
with `melos: command not found`, exit code 127).

`dart-lang/setup-dart@v1` exports `PUB_CACHE` into the job environment as a
**Windows-style path**, e.g.:

```
PUB_CACHE: C:\Users\runneradmin/.pub-cache
```

`dart pub global activate melos` then installs the `melos` launcher under
`%PUB_CACHE%\bin`. To call `melos` from a later command in the same step,
that directory must be on `PATH`.

The trap: Git Bash's `PATH` is colon-separated and its entries must be
**POSIX paths** (`/c/Users/...`). A Windows-style entry containing a drive
letter and backslashes (`C:\Users\runneradmin/.pub-cache/bin`) is not a
resolvable `PATH` component in Git Bash. So this:

```bash
export PATH="$PATH:$PUB_CACHE/bin"   # $PUB_CACHE = C:\Users\...\.pub-cache
```

silently adds an unusable entry, and the next line — `melos bootstrap` —
fails with `command not found` (exit 127).

On Linux/macOS the same code works only because `PUB_CACHE` was derived from
`$HOME` there, which is already a POSIX path.

### Fix

Convert `PUB_CACHE` to a POSIX path with `cygpath -u` (ships with Git Bash)
before putting it on `PATH`:

```bash
PUB_CACHE_POSIX="$(cygpath -u "$PUB_CACHE")"
export PATH="$PATH:$PUB_CACHE_POSIX/bin"
echo "$PUB_CACHE_POSIX/bin" >> "$GITHUB_PATH"
```

Notes:

- Do **not** overwrite the `PUB_CACHE` env var itself. Dart already has the
  correct Windows-style value from `setup-dart`; only the bash `PATH` needs
  the POSIX form. The old workflow re-`echo`'d `PUB_CACHE` into `$GITHUB_ENV`
  with the same value — a no-op that was removed.
- `export PATH=...` only affects the current step's shell, which is enough
  for the `melos` calls that follow in the same `run:` block. The
  `>> "$GITHUB_PATH"` line is what carries the directory to *later* steps.
- `cygpath` is the canonical converter; `$HOME` would also work as a POSIX
  base, but reusing the env var `setup-dart` actually set keeps the cache
  directory authoritative and avoids a second source of truth.

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
