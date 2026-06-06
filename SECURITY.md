# Security Policy

## Reporting a Vulnerability

Please report security issues **privately** — do not open a public issue.

- Preferred: open a private advisory via GitHub Private Vulnerability Reporting —
  <https://github.com/conduit-dart/conduit/security/advisories/new>
- Fallback: email `j4qfrost@gmail.com`.

Expect an acknowledgement within ~5 business days (best-effort, solo maintainer). Coordinated
disclosure on a mutually agreed timeline is preferred.

## Supported Versions

This project is pre-1.0. Security fixes land on the default branch; only the latest default-branch
state / current `v0.x` is supported. There are no backports to older tags.

| Version | Supported |
| ------- | --------- |
| latest default branch | ✅ |
| older tags | ❌ |

## Scope

**In scope** (please report):
- Remote or local code execution beyond what the user explicitly asked the tool to do (injection
  through untrusted input, path traversal in output / `--out` arguments, unsafe deserialization).
- Leakage of secrets, credentials, API keys, tokens, or private user content to unintended
  destinations.
- Authentication / authorization bypass or privilege escalation in any networked surface.
- Anything reachable by an unauthenticated client: injection, SSRF, IDOR, missing authorization
  on an endpoint, or session/token handling defects.
- **Deployment:** run behind TLS + a trusted reverse proxy or private network; keep `.env`,
  databases, and uploaded content out of the repo and off public paths.

**Out of scope:**
- Bugs in third-party / downstream tools and dependencies (report those upstream; we'll bump the
  dependency once a fix exists).
- Correctness bugs that produce wrong output but cross no trust boundary — file a normal issue.
- Self-inflicted misconfiguration on the operator's own host.
