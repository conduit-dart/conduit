#!/usr/bin/env bash
# Create or update the AI pipeline's labels (idempotent).
#   tool/ai/setup-labels.sh [owner/repo]
set -euo pipefail
repo=${1:-conduit-dart/conduit}
while IFS='|' read -r name color description; do
  gh label create "$name" --repo "$repo" --color "$color" --description "$description" --force
done <<'LABELS'
ai:triage|d4c5f9|AI pipeline: feature request awaiting maintainer review
ai:approved|0e8a16|AI pipeline Gate 1: maintainer approved, start research
ai:researching|c5def5|AI pipeline: research stage running
deps:review|fbca04|AI pipeline: dependency candidates posted, awaiting Gate 2
deps:approved|0e8a16|AI pipeline Gate 2: maintainer picked a dependency option
ai:implementing|c5def5|AI pipeline: implementation stage running
ai:in-review|1d76db|AI pipeline: implementation PR open
ai:blocked|b60205|AI pipeline: a stage failed; see the issue comments
ai:retry|fef2c0|AI pipeline: maintainer asks to re-run the stuck stage
ai:stop|000000|AI pipeline: halt all automation on this issue
release:prepare|5319e7|AI pipeline: open a release-prep PR
bot:ai-pipeline|ededed|Pull request opened by the AI pipeline
LABELS
