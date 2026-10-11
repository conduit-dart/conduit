# AI-assisted pipeline: feature request to release

An event-driven companion to the scheduled chores in
[AGENTIC_MAINTENANCE.md](AGENTIC_MAINTENANCE.md). Feature requests and bug
reports move through research, an optional dependency review, implementation
and AI review,
with a **maintainer gate** at every step that matters. The existing CI and
release gates are unchanged: AI pull requests run the same Linux/macOS/Windows
workflows, need the same approving review, and only a maintainer's tag
publishes to pub.dev.

The whole pipeline is off unless the repository variable
`AI_PIPELINE_ENABLED` is `true`.

## Flow

```
issue opened (enhancement or bug) ─► ai:triage
        │  maintainer adds ai:approved                 ◄── Gate 1
        ▼
research (ai-research.yml)
  • lists outdated direct dependencies (report only, no upgrade PR)
  • agent posts a research note
  • too large for one PR? ── yes: sub-issues proposed, label split:review
        │                    maintainer adds split:approved   ◄── split gate
        │                    ai-split.yml creates linked sub-issues, each
        │                    starting again at Gate 1; this issue becomes
        │                    ai:tracking and closes with its last sub-issue
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

## Splitting large issues

When an issue bundles independent features, or is too large to review as
one pull request, research proposes a split instead of handing off to
implementation. It posts a **Proposed split** comment: a table of two to
six parts in landing order, with each part's dependencies, and the plan as
an editable JSON block. Parts that need a maintainer (workflow or CI image
changes, secrets, infrastructure the runner cannot test) are marked manual.
The pipeline validates the plan (`tool/ai/bin/split_plan.dart`): a part may
only depend on earlier parts, and titles are one line.

A maintainer then chooses:

- **Accept:** add `split:approved`. `ai-split.yml` (GitHub-hosted, no model)
  reads the plan back from the comment, so edits to the JSON count. It
  creates each part as a sub-issue of this one, marks it blocked by the
  parts it depends on, and labels it `ai:triage`, or `ai:manual` for manual
  parts, which the pipeline never runs. This issue gets `ai:tracking`.
- **Decline:** remove `split:review` and add `ai:retry` to implement the
  issue as a single PR.
- **Re-research:** remove `split:review`, then remove and re-add
  `ai:approved`.

Each sub-issue goes through the whole flow on its own: Gate 1, research,
Gate 2 if needed, its own PR. Start a part only once the parts it depends
on are closed. When the last sub-issue closes, `ai-cleanup.yml` closes the
tracking issue.

An issue whose implementation was blocked as too large can be re-researched
the same way (remove and re-add `ai:approved`): research reads the blocked
report in the comments and will usually propose a split.

## Bug reports

Issues labelled `bug` (the bug report template applies it) are ingested the
same way as feature requests and pass the same gates. The difference is in
what the agents do:

- **Research** reproduces the bug and posts a **Root cause** section with
  `path:line` references, or says plainly that it could not reproduce it
  and what information is missing.
- **Implementation** writes the regression test first, confirms it fails,
  then makes the smallest fix for that root cause and titles the PR
  `fix(<scope>): …`.

Issues opened before the pipeline existed (or without a label) can enter at
Gate 1 directly: adding `ai:approved` starts research; `ai:triage` is not
required.

## Labels

| Label | Set by | Meaning |
|---|---|---|
| `ai:triage` | intake | New feature request or bug report, awaiting review |
| `ai:approved` | **maintainer** | Gate 1: start research |
| `ai:researching`, `ai:implementing` | pipeline | Stage running |
| `split:review` | pipeline | Sub-issues proposed, awaiting the split gate |
| `split:approved` | **maintainer** | Create the proposed sub-issues |
| `ai:tracking` | pipeline | Split into sub-issues; no further stages run on it |
| `ai:manual` | pipeline | Sub-issue a maintainer must do; the pipeline skips it |
| `deps:review` | pipeline | Dependency candidates posted |
| `deps:approved` | **maintainer** | Gate 2: implement with the ticked option |
| `ai:in-review` | pipeline | Implementation PR is open |
| `ai:blocked` | pipeline | A stage failed; the comment links the run |
| `ai:retry` | **maintainer** | Re-run the stage the issue is stuck at |
| `ai:stop` | **maintainer** | Halt all automation on this issue |
| `release:prepare` | **maintainer** | Open a release-prep PR |
| `bot:ai-pipeline` | pipeline | Marks PRs the pipeline opened |

Create them with `tool/ai/setup-labels.sh`.

Closing an issue removes its stage labels (`ai:triage`, `ai:researching`,
`ai:implementing`, `ai:in-review`, `ai:blocked`, `ai:retry`, `deps:review`,
`split:review`) through `ai-cleanup.yml`. The labels a maintainer applied stay as a record.

## Guardrails

These follow the non-negotiables in AGENTIC_MAINTENANCE.md.

- **Maintainer gates.** Every stage first runs `tool/ai/gate.sh` on a
  GitHub-hosted runner: the label's author must have triage or higher, bots
  are ignored, the issue must be open, carry the stage's required labels and
  not carry `ai:stop` (or a stage-specific blocker such as `ai:tracking`).
  Only an open gate schedules work on the self-hosted runner.
- **No model chooses facts.** Dependency facts (version, date, license,
  SDK constraint, points, likes, downloads, publisher) come from the pub.dev
  API via `tool/ai/bin/dep_candidates.dart`; the model only proposes names.
  Release versions come from conventional commits via
  `tool/ai/bin/next_version.dart`.
- **Agents never hold push credentials.** Agents edit the working tree; the
  workflow verifies the result and commits, pushes and opens PRs with the
  GitHub App token, which never sits in the workspace (see *Containing the
  agent*). Agents cannot change protected paths (`.github/`, `tool/ai/`,
  CI and lint configuration, the root `pubspec.yaml`), and every agent runs
  with an explicit tool allow-list (`tool/ai/run-agent.sh`).
- **Issue text is data.** Prompts (`.github/ai/prompts/`) tell agents to
  treat issue content as a description, not instructions; web access through
  the agent's tools is limited to pub.dev and dart.dev, and its Read tool
  cannot open the runner's credential files. Those rules bind only the
  agent's own tools, which is why the next section exists.
- **One PR per issue.** Implementation refuses to run while an AI PR for
  the issue is open. Research never opens dependency PRs: it only reports
  what is outdated, and upgrades come through Dependabot with full CI.
- **No automated releases.** Release prep deletes every tag melos creates
  locally and pushes a single branch ref; publishing still requires a
  maintainer to push `vX.Y.Z`.
- **Branch names** use the `claude/` prefix so the required `unit` job runs
  on AI PRs (the job is skipped for other prefixes, which would satisfy the
  required check without running tests).

### Containing the agent

The tool allow-list is not a sandbox. Code the agent runs through an allowed
command (`dart`, `melos`, the tests it writes) can do anything the runner
user can, and even `git log` or `git diff` can write any file through
`--output`. A planted `core.fsmonitor` in `.git/config` then runs code at
the pipeline's next git command. So everything after an agent step assumes
the agent may have tampered with the container, and the steps that hold the
App token rely only on things the agent cannot change:

- **No credentials in the workspace.** Checkouts use
  `persist-credentials: false` and take no `token:` input (action post steps
  receive the same inputs). The App token is passed to `git push` for that
  one command, and `create-github-app-token` runs with
  `skip-token-revoke: true` because its post step runs action code from a
  directory the agent can write to; the job's last step revokes the token
  instead.
- **`tool/ai/contain.sh`** wraps the agent and every later run of
  agent-influenced code (tests, analysis, the Dart tools, which load the pub
  cache). The command runs without the job's secrets and without the
  `$GITHUB_ENV` / `$GITHUB_PATH` / `$GITHUB_OUTPUT` files, which are restored
  afterwards, so it cannot set environment variables such as `LD_PRELOAD`
  for later steps. Every process it started is then killed, matched by pid
  and start time, so nothing outlives it to read a later step's environment.
- **Git is checked before it runs.** A fingerprint of `.git/config`,
  `.git/info`, hooks, alternates and the user's git configuration is taken
  before the agent starts and compared before any later git command.
- **The tree is checked before anything in it runs.** Research and review
  may change only `.ai/`; implementation fails on protected paths, checked
  locally and again against GitHub's own compare of the pushed branch (the
  local checks trust an object store the agent could write to; a branch that
  fails is deleted).
- **A fixed `PATH`** without user-writable directories, and `gh` reads no
  configuration (`GH_CONFIG_DIR` points at a directory nobody can create).
- **The review job has read-only permissions.** A separate GitHub-hosted job
  posts the review it produced.

What remains: during its own step the agent can still read
`CLAUDE_CODE_OAUTH_TOKEN` (through `/proc`), and the runner limits only
where that could be sent (see the runner's egress allow-list). Moving the
token out of the job entirely needs a host-side credential proxy.

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
| `AI_PIPELINE_TRIGGERS` | variable | Logins (space or comma separated) allowed to drive the pipeline: their labels open gates, their manual dispatches run, and AI review runs on PRs they open. Empty means anyone with triage or higher. |
| `AI_MODEL` | variable | Optional model override for `claude` |
| `CLAUDE_CODE_OAUTH_TOKEN` | secret | From `claude setup-token` |
| `AI_APP_ID`, `AI_APP_PRIVATE_KEY` | secrets | GitHub App that pushes branches and opens PRs (contents, issues, pull requests: read & write; actions: write) |

Set these as **repository** variables (Settings → Secrets and variables →
Actions → Variables). Environment variables are not visible to these
workflows: the jobs declare no `environment:`, and job-level `if:`
conditions are evaluated before any environment applies.

PRs opened with the default `GITHUB_TOKEN` would not trigger the CI
workflows, which is why the pipeline uses an App.

**Subscription tokens are personal.** A `CLAUDE_CODE_OAUTH_TOKEN` from
`claude setup-token` bills the subscription of whoever generated it. When
using one, set `AI_PIPELINE_TRIGGERS` to that person so other maintainers
cannot spend it; for a pipeline the whole team drives, use an
`ANTHROPIC_API_KEY` from the Claude Console instead.

## Tooling

`tool/ai` is a private workspace package:

- `bin/dep_candidates.dart`: vet candidates and render the Gate 2 comment;
  `--parse-choice` reads the maintainer's tick.
- `bin/new_deps.dart`: fail on dependencies added since a base ref that
  were not approved.
- `bin/split_plan.dart`: validate a split plan, render the proposal
  comment, and read the approved plan back from it.
- `bin/next_version.dart`: next version and breaking commits from
  conventional commits.
- `gate.sh`, `run-agent.sh`, `contain.sh`, `setup-labels.sh`, and `outdated_report.jq` (the research note's outdated-dependency table).

Run its tests with `cd tool/ai && dart test` (offline; pub.dev responses
are recorded fixtures).
