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
dart pub global run melos cache-source-win --no-select
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

## `cache-source` step — POSIX-only, and `cache-source-win` is also broken

After the two fixes above, the Windows `smoke` jobs get past `melos
bootstrap` (which now succeeds) but still fail — at the **next** command,
`melos cache-source`:

```
$ melos exec
  └> mkdir -p '$PUB_CACHE/hosted/pub.dev/MELOS_PACKAGE_NAME-...' && cp -rf ...
ERROR: [conduit_core]: The syntax of the command is incorrect.
ScriptException: The script cache-source failed to execute.
```

`"The syntax of the command is incorrect"` is a **`cmd.exe`** error string.
The `cache-source` melos script (defined in the root `pubspec.yaml` under
`melos.scripts`) uses POSIX shell syntax:

```yaml
cache-source:
  run: melos exec -- "mkdir -p '...' && cp -rf '...'"
```

`melos exec` runs the inner command through the platform's default shell —
`cmd.exe` on Windows — which understands neither `mkdir -p`, `&&` in that
form, nor `cp`. The repo **already ships a Windows variant**,
`cache-source-win`, which uses `mkdir` + `xcopy`:

```yaml
cache-source-win:
  run: melos exec -- mkdir %PUB_CACHE%\hosted\... && melos exec -- xcopy ...
```

but `windows.yml` was never switched over to it — both the `Setup Conduit`
and `Get Dependencies` steps still call the POSIX `cache-source`.

### Switched to `cache-source-win` — which exposed a deeper bug

In `.github/workflows/windows.yml`, both `... melos cache-source --no-select`
invocations were changed to `... melos cache-source-win --no-select`
(commit `dc8ef5a3`). That is the right *direction* — `cache-source-win` is
the Windows-intended variant — but PR #290's run `26279021133` is the
**first time `cache-source-win` has ever executed in CI** (added in PR #244,
never exercised), and it surfaced that the script itself is broken.

`cache-source-win` (root `pubspec.yaml` → `melos.scripts`) runs as:

```
melos exec -- mkdir %PUB_CACHE%\hosted\pub.dev\MELOS_PACKAGE_NAME-MELOS_PACKAGE_VERSION && melos exec -- xcopy MELOS_PACKAGE_PATH %PUB_CACHE%\... /Y /s /e
```

Two bugs, both visible in the run log:

1. **`MELOS_PACKAGE_*` tokens are not substituted.** `melos exec` exposes
   `MELOS_PACKAGE_NAME` / `MELOS_PACKAGE_VERSION` / `MELOS_PACKAGE_PATH` as
   **environment variables**, not literal string templates. In a `cmd.exe`
   command they must be written `%MELOS_PACKAGE_NAME%`. The script uses the
   bare tokens, so the executed command literally contained
   `...\pub.dev\MELOS_PACKAGE_NAME-MELOS_PACKAGE_VERSION`. (`%PUB_CACHE%`
   *did* expand — env vars work; the bare `MELOS_*` tokens did not.)

2. **`PUB_CACHE` carries a forward slash.** `setup-dart` sets
   `PUB_CACHE=C:\Users\runneradmin/.pub-cache` (mixed separators). cmd.exe's
   `mkdir` treats `/` as a switch introducer, so `/.pub-cache\...` parses as
   an invalid option → `The syntax of the command is incorrect.`

### Remaining work (not done — needs a real fix + CI iteration)

`cache-source-win` must be rewritten to (a) use `%MELOS_PACKAGE_NAME%` /
`%MELOS_PACKAGE_VERSION%` / `%MELOS_PACKAGE_PATH%`, and (b) hand cmd.exe an
all-backslash `PUB_CACHE`. This is no longer a one-line change, and each
attempt costs a multi-minute Windows CI run to verify, so it was
deliberately not ground out here. Until `cache-source-win` is fixed, the
Windows workflow cannot get past the source-caching step.

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
