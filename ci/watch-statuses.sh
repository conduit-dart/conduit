#!/usr/bin/env bash
# Stream Woodpecker gate transitions for a given commit by polling
# forgejo's commit-statuses API. One stdout line per status change so
# the Monitor tool emits one notification per gate transition.
#
# Env:
#   FORGEJO_TOKEN — required, scope: read:repository
#   COMMIT_SHA    — commit to watch (defaults to HEAD)
#   POLL_SECS     — poll interval in seconds (default 20)
#
# Exits 0 once every status is terminal (success/failure/error).

set -euo pipefail

: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN}"
SHA="${COMMIT_SHA:-$(git rev-parse HEAD)}"
POLL="${POLL_SECS:-20}"
API="https://snowman.tailddc637.ts.net:8443/api/v1/repos/j4qfrost/conduit/commits/${SHA}/statuses"

# Map: context -> last_state (success / failure / pending / error)
declare -A LAST

terminal_state() {
  case "$1" in
    success|failure|error) return 0 ;;
    *) return 1 ;;
  esac
}

while true; do
  # Pull statuses; one entry per gate per attempt. Newest first.
  body=$(curl -sk -H "Authorization: token $FORGEJO_TOKEN" "$API" || echo '[]')

  # Parse with python3 (no jq). Emit one line per (context,status) pair.
  echo "$body" | python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
seen = {}
# API returns newest first; keep the latest per context.
for s in data:
    ctx = s.get("context","")
    if ctx not in seen:
        seen[ctx] = (s.get("status",""), s.get("description",""), s.get("target_url",""))
for ctx, (st, desc, url) in seen.items():
    print(f"{ctx}\t{st}\t{desc}\t{url}")
' > /tmp/wp_states.txt

  # Diff against LAST.
  while IFS=$'\t' read -r ctx st desc url; do
    [ -z "$ctx" ] && continue
    prev="${LAST[$ctx]:-}"
    if [ "$st" != "$prev" ]; then
      printf '[%s] %s -> %s  %s\n' "$(date -u +%H:%M:%S)" "$ctx" "$st" "$desc"
      LAST[$ctx]="$st"
    fi
  done < /tmp/wp_states.txt

  # If we have at least one state recorded and ALL are terminal, exit.
  if [ "${#LAST[@]}" -gt 0 ]; then
    all_done=1
    for ctx in "${!LAST[@]}"; do
      terminal_state "${LAST[$ctx]}" || { all_done=0; break; }
    done
    [ "$all_done" -eq 1 ] && {
      echo "[$(date -u +%H:%M:%S)] all gates terminal"
      exit 0
    }
  fi

  sleep "$POLL"
done
