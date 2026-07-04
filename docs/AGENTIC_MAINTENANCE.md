# Periodic agentic maintenance with self-hosted models

Design notes for running scheduled, autonomous maintenance on this repo using
locally hosted LLMs. Written 2026-07. Nothing in this document is wired into
CI yet — it is a menu plus a rollout plan.

## Why this fits Conduit

The project already runs a **self-hosted Woodpecker CI** (`.woodpecker.yml`,
agent "snowman"). Woodpecker supports cron pipelines natively (repo settings →
*Cron*), and cron-triggered steps can be gated with `when: event: cron`. That
means periodic agent runs need no new infrastructure — only a model server and
an agent harness reachable from the CI agent.

Today no scheduled job exists anywhere (GitHub workflows trigger on
PR/push/tag only), so maintenance chores — dependency triage, doc link rot,
TODO aging, README drift — happen only when a human notices.

## Guardrails (non-negotiable)

1. **Agents never push to `master`.** Output is always a branch +
   pull request; the existing CI matrix is the merge gate.
2. **Scoped credentials.** A machine account with `contents:write` +
   `pull_requests:write` on this repo only. No org-wide token.
3. **Bounded runs.** Wall-clock timeout per task (15–30 min), iteration cap in
   the harness, and one PR per task per week maximum to avoid PR spam.
4. **Deterministic pre-checks first.** Anything expressible as a plain script
   (link checker, `dart pub outdated --json`, `dart analyze`) runs as a normal
   CI step; the model is only invoked to *act* on the findings.
5. **Label everything.** PRs get `bot:maintenance` so they can be filtered,
   bulk-closed, and excluded from release notes.

## Model options (self-hosted, July 2026)

| Tier | Model | Hardware | Fit |
| --- | --- | --- | --- |
| Small | Devstral Small 2 (24B) | 1× RTX 4090 / 32 GB Mac | ~68% SWE-bench Verified; enough for lint fixes, doc patches, dependency bumps. Best value for routine chores. |
| Mid | Qwen3-Coder-Next (80B MoE) | 96 GB (RTX PRO 6000) or 2× 4090 quantized | ~71–72% SWE-bench Verified; handles multi-file refactors and test authoring. |
| Mid | Devstral 2 (123B dense, 4-bit) | 96 GB VRAM | Same class as Qwen3-Coder-Next; stronger on instruction-following in long sessions. |
| Large | GLM-5.2 / DeepSeek V4 / Kimi K2.7 | multi-GPU server | Frontier-open agentic coding; only worth it if the box already exists. |

Serving: **Ollama** for the small tier (trivial setup), **vLLM** or
**llama.cpp server** for the MoE/large tiers (better throughput, paged KV).
All expose OpenAI-compatible endpoints, which every harness below accepts.

Open-weight models still trail closed frontier coders by ~17–27 points on
SWE-bench Verified, so the sweet spot is **chore-sized, well-specified tasks
with mechanical verification** — exactly what maintenance is.

## Harness options

- **OpenHands (headless)** — strongest CI story: `openhands -t "<task>"
  --headless`, Docker-sandboxed runtime, resume support, works with any
  OpenAI-compatible endpoint. Best default for scheduled runs.
- **Aider** — git-native (every edit is a commit), scriptable
  (`aider --message "<task>" --yes`), lighter weight; good for single-file
  chores like CHANGELOG hygiene or doc typo sweeps.
- **OpenCode / Goose** — terminal-native alternatives; comparable local-model
  support, weaker unattended/CI ergonomics than OpenHands.
- **Claude Code** — not self-hosted (Anthropic models only), but worth naming
  in the same system: use scheduled Claude Code cloud sessions for the *hard*
  tier (cross-package refactors, migration guides) and the local model for the
  routine tier. The two tiers produce PRs into the same review queue.

## Task menu (ranked by payoff ÷ risk)

| Task | Cadence | Tier | Verification |
| --- | --- | --- | --- |
| Dependency triage: run `melos run outdated`, bump safe minors, run tests | weekly | small | full test suite must pass |
| Docs link + typo sweep (`docs/**`, package READMEs) | weekly | small | link checker re-run, human skim |
| `dart fix` + analyzer-warning cleanup after SDK/lint bumps | on Dart release | small | `melos run analyze` clean |
| TODO triage: age the 7 in-tree `// todo:` comments into issues or patches | monthly | mid | issue text reviewed by human |
| Test-gap filling (e.g. `packages/common` has zero tests) | monthly | mid | new tests pass, coverage delta reported |
| Flaky-test hunt: rerun suite N×, bisect nondeterminism | monthly | mid | reproduction script attached to issue |
| CHANGELOG/README drift check against released API | per release | small | human review |

## Sketch: Woodpecker cron pipeline

Configured as a separate pipeline file once a cron is defined in the repo
settings (kept out of `.woodpecker.yml` so PR/push builds are untouched):

```yaml
# .woodpecker/maintenance.yml  (not yet committed — illustrative)
when:
  - event: cron
    cron: weekly-maintenance

steps:
  outdated-scan:
    image: dart:3.12
    commands:
      - dart pub global activate melos
      - melos bootstrap
      - melos exec -- "dart pub outdated --json" > /woodpecker/outdated.json

  agent-run:
    image: ghcr.io/all-hands-ai/openhands:latest
    environment:
      LLM_BASE_URL: http://snowman.local:11434/v1   # Ollama / vLLM endpoint
      LLM_MODEL: openai/devstral-small-2
      GITHUB_TOKEN:
        from_secret: maintenance_bot_token
    commands:
      - openhands --headless -t "Read /woodpecker/outdated.json. Bump safe
        minor/patch versions across the workspace, run 'melos run analyze'
        and the codable/open_api/password_hash/config test scope, and open
        a PR labeled bot:maintenance with the diff and test output."
```

## Rollout plan

1. **Phase 0 — deterministic only.** Add the cron with just the scan steps
   (outdated report, link checker) posting results to Discord/issue. No model.
2. **Phase 1 — one chore, small model.** Devstral Small 2 on Ollama +
   OpenHands headless doing the weekly dependency-triage PR. Measure: PR
   acceptance rate, review minutes per PR.
3. **Phase 2 — expand the menu** to doc sweeps and TODO triage if Phase 1
   PRs are merging with <10 min of review each.
4. **Phase 3 — mid-tier model** for test-gap and flake work, only if the
   hardware is already available; otherwise leave the hard tier to
   interactive/cloud sessions.

Kill criterion at every phase: if two consecutive PRs from a task are
rejected as noise, disable that task, not the whole system.
