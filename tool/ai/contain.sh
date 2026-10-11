#!/usr/bin/env bash
# Run an untrusted command (an agent, or tests the agent wrote) so that it
# cannot reach the job's later steps.
#
#   tool/ai/contain.sh [--keep VAR]... <command> [args...]
#
# The command runs without the job's secrets (GH_TOKEN, GITHUB_TOKEN,
# CLAUDE_CODE_OAUTH_TOKEN, ...) unless one is named with --keep: the agent
# itself needs CLAUDE_CODE_OAUTH_TOKEN, nothing else does.
#
# A process in the job container can also affect later steps, which hold the
# GitHub App token, in two ways. This script closes both:
#
# - **Workflow command files.** Lines appended to $GITHUB_ENV / $GITHUB_PATH
#   become environment / PATH for every later step (LD_PRELOAD, BASH_ENV,
#   GIT_* ...). The command runs without those variables, and the files are
#   restored to their prior contents afterwards, so writes through a
#   remembered path are undone too.
# - **Leftover processes.** Anything the command started (daemons, setsid'd
#   children) would otherwise outlive it and could read a later step's
#   environment through /proc. Every process that did not exist before the
#   command ran is killed afterwards.
#
# Processes are identified by pid *and* start time, so a new process that
# reuses an old pid is still caught. The reaper uses only bash builtins, so
# it starts no process of its own.
#
# Reaping kills every new process the uid can see, so it only runs inside a
# container (its own pid namespace): /.dockerenv, or CONTAIN_REAP=1. On a
# shared host it would also kill unrelated processes, so it is skipped there.
# CONTAIN_REAP=0 turns it off everywhere (tests).
# Exits with the command's exit status.
set -uo pipefail

secrets=(GH_TOKEN GITHUB_TOKEN CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY
  ACTIONS_RUNTIME_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL)
declare -A keep=()
while [ "${1:-}" = --keep ]; do keep[${2:?--keep needs a variable name}]=1; shift 2; done
[ $# -gt 0 ] || { echo "usage: contain.sh [--keep VAR]... <command> [args...]" >&2; exit 2; }

unset_args=(-u GITHUB_ENV -u GITHUB_PATH -u GITHUB_OUTPUT -u GITHUB_STATE -u GITHUB_STEP_SUMMARY)
for v in "${secrets[@]}"; do
  [ -n "${keep[$v]:-}" ] || unset_args+=(-u "$v")
done

# Sets $t to the start time (field 22 of /proc/<pid>/stat) of a process, or
# to empty if it is gone. Sets a variable rather than printing, so callers
# need no command substitution (which would fork). The comm field may hold
# spaces and parentheses, so cut after the last ')'.
started() {
  local stat
  local -a f
  t=
  { read -r stat <"/proc/$1/stat"; } 2>/dev/null || return 0
  stat=${stat##*) }
  read -ra f <<<"$stat"
  t=${f[19]:-}
}

declare -A before=()
for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  started "$pid"
  before[$pid]=$t
done

# Snapshot the workflow command files (they are small text files).
files=()
declare -A saved=()
for v in GITHUB_ENV GITHUB_PATH GITHUB_OUTPUT GITHUB_STATE GITHUB_STEP_SUMMARY; do
  f=${!v:-}
  [ -n "$f" ] || continue
  files+=("$f")
  if [ -f "$f" ]; then saved[$f]=$(<"$f"); else saved[$f]=__absent__; fi
done

env "${unset_args[@]}" "$@"
status=$?

reap=0
if [ "${CONTAIN_REAP:-}" = 1 ] || { [ -e /.dockerenv ] && [ "${CONTAIN_REAP:-}" != 0 ]; }; then
  reap=1
elif [ "${CONTAIN_REAP:-}" != 0 ]; then
  echo "contain.sh: not in a container; leftover processes are not reaped" >&2
fi

# Reap until a pass finds nothing new: a dying process can fork once more.
for ((pass = 0; reap && pass < 50; pass++)); do
  found=0
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    [ "$pid" = "$$" ] && continue
    started "$pid"
    [ -n "$t" ] || continue
    [ "${before[$pid]+set}" = set ] && [ "${before[$pid]}" = "$t" ] && continue
    kill -9 "$pid" 2>/dev/null && found=1
  done
  [ "$found" = 0 ] && break
done

for f in "${files[@]}"; do
  if [ "${saved[$f]}" = __absent__ ]; then
    rm -f -- "$f"
  else
    # $(<f) drops trailing newlines; command files are line-oriented, so
    # restore with one.
    if [ -n "${saved[$f]}" ]; then printf '%s\n' "${saved[$f]}" >"$f"; else : >"$f"; fi
  fi
done

exit "$status"
