#!/usr/bin/env bash
# Gate check for the AI pipeline (.github/workflows/ai-*.yml).
#
# Runs on a GitHub-hosted runner *before* any job is scheduled on the
# self-hosted `conduit-ai` runner. Writes `ok=true|false` and `reason=...`
# to $GITHUB_OUTPUT; never fails the job itself, so a closed gate shows up
# as a skipped stage rather than a red X.
#
# Env:
#   GH_TOKEN            token with issues:read
#   REPO                owner/name
#   ISSUE               issue number
#   ENABLED             value of vars.AI_PIPELINE_ENABLED ("true" to run)
#   SENDER              github.event.sender.login
#   SENDER_TYPE         github.event.sender.type ("User", "Bot", ...)
#   REQUIRED_LABELS     space-separated labels the issue must carry
#   SKIP_SENDER_CHECK   "1" for workflow_dispatch (dispatch already needs write)
#   TRIGGERS            value of vars.AI_PIPELINE_TRIGGERS: logins (space or
#                       comma separated) allowed to drive the pipeline. Empty
#                       means anyone with triage or higher. The model runs on
#                       the subscription of whoever ran `claude setup-token`,
#                       so restrict this to that person when using one.
#   ACTOR               github.triggering_actor (checked on workflow_dispatch)
set -euo pipefail

out() { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/stdout}"; }

# Is $1 in the TRIGGERS allowlist? An empty allowlist allows everyone.
allowed() {
  [ -z "${TRIGGERS//[ ,]/}" ] && return 0
  local login
  for login in ${TRIGGERS//,/ }; do
    [ "${login,,}" = "${1,,}" ] && return 0
  done
  return 1
}
close() {
  echo "gate closed: $1"
  out ok false
  out reason "$1"
  exit 0
}

[ "${ENABLED:-}" = "true" ] || close "AI_PIPELINE_ENABLED is not 'true'"
[[ "${ISSUE:-}" =~ ^[0-9]+$ ]] || close "no issue number"

if [ "${SKIP_SENDER_CHECK:-0}" != "1" ]; then
  [ "${SENDER_TYPE:-}" != "Bot" ] || close "sender ${SENDER} is a bot"
  role=$(gh api "repos/${REPO}/collaborators/${SENDER}/permission" --jq .role_name 2>/dev/null || echo none)
  case "$role" in
    admin|maintain|write|triage) ;;
    *) close "sender ${SENDER} has role '${role}', needs triage or higher" ;;
  esac
  allowed "$SENDER" || close "sender ${SENDER} is not in AI_PIPELINE_TRIGGERS"
else
  # Dispatches from the pipeline's own workflows run as a bot (the App, or
  # github-actions[bot] for ai-retry); a person dispatching by hand must be
  # on the allowlist.
  case "${ACTOR:-}" in
    *"[bot]") ;;
    *) allowed "${ACTOR:-}" || close "dispatcher ${ACTOR:-unknown} is not in AI_PIPELINE_TRIGGERS" ;;
  esac
fi

issue=$(gh api "repos/${REPO}/issues/${ISSUE}" --jq '{state: .state, pr: (.pull_request != null), labels: [.labels[].name]}')
[ "$(jq -r .pr <<<"$issue")" = "false" ] || close "#${ISSUE} is a pull request, not an issue"
[ "$(jq -r .state <<<"$issue")" = "open" ] || close "#${ISSUE} is not open"
jq -e '.labels | index("ai:stop") | not' <<<"$issue" >/dev/null || close "#${ISSUE} carries ai:stop"
for label in ${REQUIRED_LABELS:-}; do
  jq -e --arg l "$label" '.labels | index($l)' <<<"$issue" >/dev/null \
    || close "#${ISSUE} is missing label ${label}"
done

echo "gate open for #${ISSUE}"
out ok true
out reason open
