#!/usr/bin/env bash
# Runs each bench under packages/core/bench/, captures stdout to a file,
# and appends a fenced markdown block per bench to GITHUB_STEP_SUMMARY so
# the numbers show up inline on the run page. Non-gating: a single bench
# crashing prints the failure but does not abort the others.
#
# Run from packages/core/ (the workflow sets working-directory).
set -u

summary="${GITHUB_STEP_SUMMARY:-/dev/stderr}"

{
  echo "# Bench results"
  echo
  echo "_Non-gating microbenchmarks. See \`packages/core/bench/RESULTS.md\` for"
  echo "methodology, baseline, and the post-#267 verdict._"
  echo
} >> "$summary"

for bench in bench/predicate_construction_bench.dart \
             bench/ast_render_bench.dart \
             bench/query_e2e_bench.dart; do
  name="$(basename "$bench" .dart)"
  out="$(mktemp)"
  echo "::group::$name"
  if dart run "$bench" 2>&1 | tee "$out"; then
    status="ok"
  else
    status="FAILED"
  fi
  echo "::endgroup::"
  {
    echo "## $name ($status)"
    echo
    echo '```'
    cat "$out"
    echo '```'
    echo
  } >> "$summary"
  rm -f "$out"
done
