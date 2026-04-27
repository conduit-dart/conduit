#!/usr/bin/env bash
# Read step logs from Woodpecker's sqlite DB on snowman without going
# through the UI or API. Lets you triage a failed gate locally:
#
#   ci/diagnose-step.sh                # list recent pipelines + states
#   ci/diagnose-step.sh <pipeline-id>  # show step states for that pipeline
#   ci/diagnose-step.sh <pipeline-id> <step-name>   # tail the step log
#
# Resolves <pipeline-id> as Woodpecker's internal id (`pipelines.id`),
# which is what shows up in URLs like /repos/4/pipeline/<number>/<workflow>.
# When unsure, run with no args.
#
# Reads /home/frosty/infra/ci/woodpecker/server-data/woodpecker.sqlite
# directly — no Woodpecker token required, but only works on snowman.

set -euo pipefail

DB="${WOODPECKER_DB:-/home/frosty/infra/ci/woodpecker/server-data/woodpecker.sqlite}"
TAIL="${TAIL_LINES:-200}"

if [ ! -f "$DB" ]; then
  echo "Woodpecker DB not found at $DB" >&2
  exit 1
fi

case "$#" in
  0)
    python3 - "$DB" <<'PY'
import sqlite3, sys, datetime
db = sys.argv[1]
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
cur = con.cursor()
print(f"{'id':>5} {'#':>4} {'repo':>4} {'branch':<25} {'event':<14} {'status':<10}  message")
print("-" * 110)
for r in cur.execute("""
    SELECT id, number, repo_id, branch, event, status, message
    FROM pipelines
    ORDER BY id DESC
    LIMIT 15
"""):
    msg = (r[6] or "").splitlines()[0][:50]
    print(f"{r[0]:>5} {r[1]:>4} {r[2]:>4} {r[3][:25]:<25} {r[4][:14]:<14} {r[5]:<10}  {msg}")
PY
    ;;
  1)
    PIPELINE_ID="$1"
    python3 - "$DB" "$PIPELINE_ID" <<'PY'
import sqlite3, sys
db, pid = sys.argv[1], sys.argv[2]
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
cur = con.cursor()
print(f"=== pipeline {pid} ===")
for r in cur.execute("SELECT id, number, branch, event, status, errors FROM pipelines WHERE id=?", (pid,)):
    print(f"id={r[0]} number={r[1]} branch={r[2]} event={r[3]} status={r[4]}")
    if r[5] and r[5] != 'null':
        print(f"errors: {r[5]}")
print()
print(f"{'step':<28} {'state':<10} {'exit':>5}")
print("-" * 50)
for r in cur.execute("SELECT name, state, exit_code FROM steps WHERE pipeline_id=? ORDER BY id", (pid,)):
    print(f"{r[0]:<28} {r[1]:<10} {r[2]:>5}")
PY
    ;;
  2)
    PIPELINE_ID="$1"
    STEP_NAME="$2"
    python3 - "$DB" "$PIPELINE_ID" "$STEP_NAME" "$TAIL" <<'PY'
import sqlite3, sys
db, pid, name, tail = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
cur = con.cursor()
row = cur.execute(
    "SELECT id, state, exit_code FROM steps WHERE pipeline_id=? AND name=?",
    (pid, name)
).fetchone()
if row is None:
    print(f"No step '{name}' in pipeline {pid}", file=sys.stderr)
    sys.exit(2)
sid, state, code = row
print(f"=== step {name} (pipeline={pid} id={sid}) state={state} exit={code} ===")
total = cur.execute("SELECT COUNT(*) FROM log_entries WHERE step_id=?", (sid,)).fetchone()[0]
start = max(0, total - tail)
for r in cur.execute(
    "SELECT line, data FROM log_entries WHERE step_id=? ORDER BY line LIMIT ? OFFSET ?",
    (sid, tail, start),
):
    line, data = r
    if data is None:
        continue
    txt = data.decode("utf-8", "replace") if isinstance(data, (bytes, bytearray)) else str(data)
    print(f"{line:>5}  {txt}")
print(f"\n=== showed {min(tail,total)} of {total} log lines ===")
PY
    ;;
  *)
    echo "Usage: $0 [pipeline_id [step_name]]" >&2
    exit 64
    ;;
esac
