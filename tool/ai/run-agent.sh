#!/usr/bin/env bash
# Run one Claude Code agent stage non-interactively.
#
#   tool/ai/run-agent.sh <prompt-file> <max-turns> <allowed-tools>
#
# The allowed-tools list is the stage's entire capability; anything not
# listed is denied (print mode never prompts). Reads under /proc, the
# runner's credential/state files and ~/.claude are always denied so the
# agent cannot read its own environment (which holds
# CLAUDE_CODE_OAUTH_TOKEN) or the runner registration. The checkout itself
# lives under /home/runner/_work and stays readable.
#
# Env: CLAUDE_CODE_OAUTH_TOKEN (required), AI_MODEL (optional).
# Writes the JSON transcript summary to .ai/<stage>-run.json.
set -euo pipefail

prompt_file=$1
max_turns=$2
allowed=$3

: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is not set}"
[ -f "$prompt_file" ] || { echo "no prompt file $prompt_file" >&2; exit 2; }
mkdir -p .ai

stage=$(basename "$prompt_file" .md)
model_args=()
if [ -n "${AI_MODEL:-}" ]; then model_args=(--model "$AI_MODEL"); fi

claude -p "$(cat "$prompt_file")" \
  "${model_args[@]}" \
  --max-turns "$max_turns" \
  --allowedTools "$allowed" \
  --disallowedTools "Read(/proc/**),Read(/home/runner/.credentials*),Read(/home/runner/.runner*),Read(/home/runner/.claude/**),Read(~/.claude/**)" \
  --output-format json \
  > ".ai/${stage}-run.json"

jq -r '"agent \(.subtype // "done"): \(.num_turns // "?") turns, \(((.duration_ms // 0) / 1000) | floor)s"' \
  ".ai/${stage}-run.json" || true
if jq -e '.is_error == true' ".ai/${stage}-run.json" >/dev/null 2>&1; then
  echo "agent reported an error" >&2
  exit 1
fi
