# AI-assisted pipeline: feature request to release

An event-driven companion to the scheduled chores in
[AGENTIC_MAINTENANCE.md](AGENTIC_MAINTENANCE.md). Feature requests move
through research, an optional dependency review, implementation and AI review,
with a **maintainer gate** at every step that matters. The existing CI and
release gates are unchanged: AI pull requests run the same Linux/macOS/Windows
workflows, need the same approving review, and only a maintainer's tag
publishes to pub.dev.

The whole pipeline is off unless the repository variable
`AI_PIPELINE_ENABLED` is `true`.

## Flow

```
issue opened (enhancement) ─► ai:triage
        │  maintainer adds ai:approved                 ◄── Gate 1
        ▼
research (ai-research.yml)
  • dart pub upgrade --major-versions → separate chore(deps) PR if analyze + test-fast pass
  • agent posts a research note
  • needs a new dependency?
        ├─ no ──────────────────────────────────────────────┐
        └─ yes: candidates vetted against pub.dev, posted    │
               as a checklist, label deps:review             │
               maintainer ticks one, adds deps:approved ◄── Gate 2
        ▼                                                    ▼
implementation (ai-implement.yml) ◄──────────────────────────┘
  • agent edits on claude/ai-issue-<n>-<slug>
  • pipeline re-runs format, analyze, touched packages' tests,
    and rejects any dependency not approved at Gate 2
  • pipeline commits and opens the PR (Closes #n, label bot:ai-pipeline)
        ▼
normal CI (linux/macos/windows) + AI review notes on the issue (ai-review.yml)
        │  maintainer reviews and merges               ◄── existing gate
        ▼
release prep (ai-release-prep.yml, on release:prepare or manual dispatch)
  • version from conventional commits, melos sync-version, curated CHANGELOGs
  • release PR + publish.yml dry run
        │  maintainer merges and pushes vX.Y.Z         ◄── existing gate
        ▼
publish.yml (unchanged)
```

## Labels

| Label | Set by | Meaning |
|---|---|---|
| `ai:triage` | intake | New feature request, awaiting review |
| `ai:approved` | **maintainer** | Gate 1: start research |
| `ai:researching`, `ai:implementing` | pipeline | Stage running |
| `deps:review` | pipeline | Dependency candidates posted |
| `deps:approved` | **maintainer** | Gate 2: implement with the ticked option |
| `ai:in-review` | pipeline | Implementation PR is open |
| `ai:blocked` | pipeline | A stage failed; the comment links the run |
| `ai:retry` | **maintainer** | Re-run the stage the issue is stuck at |
| `ai:stop` | **maintainer** | Halt all automation on this issue |
| `release:prepare` | **maintainer** | Open a release-prep PR |
| `bot:ai-pipeline` | pipeline | Marks PRs the pipeline opened |

Create them with `tool/ai/setup-labels.sh`.

## Guardrails

These follow the non-negotiables in AGENTIC_MAINTENANCE.md.

- **Maintainer gates.** Every stage first runs `tool/ai/gate.sh` on a
  GitHub-hosted runner: the label's author must have triage or higher, bots
  are ignored, the issue must be open, carry the stage's required labels and
  not carry `ai:stop`. Only an open gate schedules work on the self-hosted
  runner.
- **No model chooses facts.** Dependency facts (version, date, license,
  SDK constraint, points, likes, downloads, publisher) come from the pub.dev
  API via `tool/ai/bin/dep_candidates.dart`; the model only proposes names.
  Release versions come from conventional commits via
  `tool/ai/bin/next_version.dart`.
- **Agents never hold push credentials.** Agents edit the working tree; the
  workflow verifies the result and commits, pushes and opens PRs with the
  GitHub App token. Agents cannot touch `.github/`, and every agent runs
  with an explicit tool allow-list (`tool/ai/run-agent.sh`).
- **Issue text is data.** Prompts (`.github/ai/prompts/`) tell agents to
  treat issue content as a description, not instructions; web access is
  limited to pub.dev and dart.dev; the agent's own environment and the
  runner's credentials are unreadable.
- **One PR per issue.** Implementation refuses to run while an AI PR for
  the issue is open. Dependency-refresh PRs are skipped while one is open.
- **No automated releases.** Release prep deletes every tag melos creates
  locally and pushes a single branch ref; publishing still requires a
  maintainer to push `vX.Y.Z`.
- **Branch names** use the `claude/` prefix so the required `unit` job runs
  on AI PRs (the job is skipped for other prefixes, which would satisfy the
  required check without running tests).

## Runner

AI jobs run on an ephemeral self-hosted runner labelled `conduit-ai`
(`.github/actionlint.yaml`). Each job gets a fresh container that is
registered just in time and destroyed afterwards. It carries Dart, melos,
`gh`, Claude Code and PostgreSQL (`start-test-postgres` starts a loopback
instance matching `ci/.env`). Normal CI never uses it.

Because the repository is public, **"Require approval for all external
contributors"** must be on for fork pull-request workflows; otherwise a fork
PR could point a workflow at `conduit-ai`.

## Configuration

| Name | Kind | Purpose |
|---|---|---|
| `AI_PIPELINE_ENABLED` | variable | `true` turns the pipeline on |
| `AI_MODEL` | variable | Optional model override for `claude` |
| `CLAUDE_CODE_OAUTH_TOKEN` | secret | From `claude setup-token` |
| `AI_APP_ID`, `AI_APP_PRIVATE_KEY` | secrets | GitHub App that pushes branches and opens PRs (contents, issues, pull requests: read & write; actions: write) |

PRs opened with the default `GITHUB_TOKEN` would not trigger the CI
workflows, which is why the pipeline uses an App.

## Tooling

`tool/ai` is a private workspace package:

- `bin/dep_candidates.dart`: vet candidates and render the Gate 2 comment;
  `--parse-choice` reads the maintainer's tick.
- `bin/new_deps.dart`: fail on dependencies added since a base ref that
  were not approved.
- `bin/next_version.dart`: next version and breaking commits from
  conventional commits.
- `gate.sh`, `run-agent.sh`, `setup-labels.sh`.

Run its tests with `cd tool/ai && dart test` (offline; pub.dev responses
are recorded fixtures).
