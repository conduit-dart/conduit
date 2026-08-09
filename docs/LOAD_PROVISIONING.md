# Provisioning machines for scale tests — cost analysis

Where to run the `tool/load/` harness (scenarios in
[SCALE_TESTING.md](SCALE_TESTING.md)) when the answer has to be cheap.
Evaluated 2026-07, shortly after Hetzner's June 2026 repricing — check
current prices before large runs; the *structure* of this analysis ages
better than the numbers.

## Usage profile being provisioned for

Scale testing here is **bursty and small**: a full pooling-evidence
session is two machines for ~2–3 hours; a monthly soak adds ~4 hours.
Call it **10–15 machine-hours/month**, i.e. under 1% utilization of a
dedicated box. That single fact drives everything: any always-on machine
is paying 99% idle tax, so the comparison is really "existing hardware
at $0" vs "hourly-billed ephemeral VMs" vs "spot capacity".

## Options, ranked by cost for this profile

### Tier 0 — the existing Woodpecker host (marginal cost: $0)

The `load-test-smoke` CI lane already runs on the self-hosted runner.
Good for: smoke runs, leak tripwires, and **relative** matrix
comparisons (pool=1 vs pool=8 on identical hardware). Not good for:
publishable absolute numbers — generator, app, and DB share one host, so
they steal CPU from each other exactly when it matters. Use it until a
number needs to survive an argument.

### Tier 1 — ephemeral Hetzner ARM VMs (~€0.10 per session) ← recommended

Two hourly-billed CAX (Ampere ARM) instances created per session and
destroyed after (`tool/load/provision/provision.sh up|down`). Why this
specific shape:

- **Post-repricing, ARM is Hetzner's value line.** The June 2026
  adjustment raised AMD shared/dedicated lines (CPX/CCX) by ~113–176%
  while ARM (CAX) and Intel-shared (CX) rose ~30%
  ([Hetzner docs](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/),
  [analysis](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/)).
  Entry plans still start around €5.5–6/month (CX23/CAX11), with hourly
  billing rounded up and capped at the monthly price
  ([Hetzner](https://www.hetzner.com/cloud/cost-optimized)).
- **Fixed hourly rates in the ~$0.01–0.02 range for 4 vCPU undercut even
  Big-3 spot prices** for comparable capacity, with zero interruption
  risk ([comparison](https://cloudpricecheck.com/),
  [benchmarks](https://dev.to/dkechag/cloud-vm-benchmarks-2026-performance-price-1i1m)).
- **No interruptions matters here**: a 4-hour soak that gets evicted at
  hour 3 produced nothing. Spot's discount only pays off for workloads
  that checkpoint; k6 runs don't.
- Dart ships linux-arm64 SDKs and k6 publishes arm64 binaries, so the
  whole stack runs native.

Cost math at ~€0.01–0.03/h per VM: a 3-hour two-machine session rounds
to ≈ €0.06–0.18. Even weekly sessions plus a monthly soak stay **under
€1/month** — versus €12+/month for the cheapest pair of always-on VMs
doing the same work at <1% utilization.

### Tier 2 — Big-3 spot instances (cheapest raw compute, worst fit)

AWS/GCP/Azure spot runs 60–90% below on-demand but can be reclaimed
with ~2 minutes' notice
([spot pricing guide](https://cloudpricecheck.com/guides/spot-pricing-explained),
[GCP spot](https://cloud.google.com/spot-vms/pricing)). Justified only
when a test needs what Hetzner can't provide: a US/Asia region close to
a real user base, >10 Gbps generator bandwidth, or very large temporary
fleets. For short matrix runs (minutes per cell) interruption risk is
tolerable; never for soaks.

### Not cost-competitive for this profile

- **Grafana Cloud k6** (managed runners): excellent ergonomics, but
  subscription pricing is structured around teams running load tests
  continuously — orders of magnitude above €1/month for our usage. Worth
  revisiting only if load testing becomes a weekly product activity.
- **A dedicated bare-metal runner**: Hetzner dedicated/auction boxes are
  the right call at sustained utilization, not at <1%. The existing
  snowman host already fills the "always available, free" role.
- **Fly.io / per-second platforms**: per-second billing is attractive
  for sub-hour runs ([pricing](https://fly.io/pricing/)), but the
  firecracker-VM shape (small machines, regional pricing) doesn't beat
  Hetzner's hourly ARM rates at this scale, and the harness assumes
  plain VMs (VM service port, docker for postgres).

## Decision

Default to **Tier 0** for anything relative; use
**`tool/load/provision/provision.sh`** (Tier 1) whenever a number will
be cited in a PR or doc — including the pooling-default decision in
[CONNECTION_POOLING.md](CONNECTION_POOLING.md). Revisit if usage grows
past ~40 machine-hours/month (the point where a Hetzner auction box
starts to compete) or if a test needs geography/bandwidth Hetzner
doesn't offer (Tier 2 spot, short runs only).

## Sources

- [Hetzner June 2026 price adjustment (official)](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
- [Hetzner price increase analysis — CPX/CCX up to +176%](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/)
- [Hetzner cost-optimized cloud plans](https://www.hetzner.com/cloud/cost-optimized)
- [Cloud pricing comparison across providers](https://cloudpricecheck.com/)
- [Cloud spot pricing guide (AWS/Azure/GCP)](https://cloudpricecheck.com/guides/spot-pricing-explained)
- [Cloud VM benchmarks 2026: performance/price](https://dev.to/dkechag/cloud-vm-benchmarks-2026-performance-price-1i1m)
- [Fly.io pricing](https://fly.io/pricing/)
